package com.risingpadel.core.sync

import com.risingpadel.core.model.PadelSession
import com.risingpadel.core.net.HttpTransport
import com.risingpadel.core.net.HttpTransportException
import com.risingpadel.core.net.JdkHttpTransport
import kotlinx.serialization.json.Json

/**
 * Configuración de la app de liga con la que se sincroniza.
 *
 * El token **no** se persiste junto a las sesiones: vive en Keychain /
 * EncryptedSharedPreferences y se inyecta aquí en el momento de sincronizar.
 */
data class LeagueConfig(
    val baseUrl: String,
    val token: String,
) {
    val isUsable: Boolean get() = baseUrl.isNotBlank() && token.isNotBlank()
}

sealed interface UploadOutcome {
    /** El servidor la aceptó. [created] es false si ya existía (respuesta 200 idempotente). */
    data class Success(val remoteId: String?, val created: Boolean) : UploadOutcome

    /** 400/409/esquema no soportado: reintentar no lo va a arreglar. */
    data class PermanentFailure(val code: String?, val message: String) : UploadOutcome

    /** 401: hace falta que el usuario vuelva a conectar la liga. */
    data class AuthFailure(val message: String) : UploadOutcome

    /** 429: reintentar respetando Retry-After. */
    data class RateLimited(val retryAfterSeconds: Long?) : UploadOutcome

    /** Red caída o 5xx: reintentar con backoff. */
    data class TransientFailure(val message: String) : UploadOutcome
}

class LeagueApiClient(
    private val transport: HttpTransport = JdkHttpTransport(),
    private val json: Json = defaultJson,
) {

    /**
     * Sube una sesión. Es idempotente vía cabecera `Idempotency-Key`, así que reintentar
     * la misma sesión nunca duplica.
     *
     * Si el servidor responde 413 se reintenta una sola vez sin la serie de golpeos,
     * que es lo único que puede hacer grande el payload.
     */
    suspend fun upload(
        config: LeagueConfig,
        session: PadelSession,
        shareHealth: Boolean,
        includeEvents: Boolean = true,
    ): UploadOutcome {
        return when (val first = post(config, session, shareHealth, includeEvents)) {
            is PostResult.Done -> first.outcome
            PostResult.TooLarge -> if (includeEvents) {
                when (val retry = post(config, session, shareHealth, includeEvents = false)) {
                    is PostResult.Done -> retry.outcome
                    PostResult.TooLarge -> tooLargeFailure()
                }
            } else {
                tooLargeFailure()
            }
        }
    }

    private fun tooLargeFailure() = UploadOutcome.PermanentFailure(
        code = "payload_too_large",
        message = "El servidor rechazó el payload por tamaño incluso sin la serie de golpeos",
    )

    /**
     * Partidos del jugador en una ventana temporal, para poder vincular la sesión.
     * Devuelve null si la liga no implementa el endpoint (404): la app degrada a
     * introducir el identificador a mano.
     */
    suspend fun matches(config: LeagueConfig, fromEpochMs: Long, toEpochMs: Long): List<MatchSummary>? {
        val url = buildUrl(config.baseUrl, "v1/me/matches") +
            "?from=${isoUtc(fromEpochMs)}&to=${isoUtc(toEpochMs)}"
        val response = try {
            transport.request("GET", url, authHeaders(config), null)
        } catch (e: HttpTransportException) {
            return null
        }
        if (response.code == 404 || response.code !in 200..299) return null
        return runCatching { json.decodeFromString(MatchesResponse.serializer(), response.body).matches }
            .getOrNull()
    }

    /** 413 no es un desenlace final: dispara el reintento sin la serie de golpeos. */
    private sealed interface PostResult {
        data class Done(val outcome: UploadOutcome) : PostResult
        data object TooLarge : PostResult
    }

    private suspend fun post(
        config: LeagueConfig,
        session: PadelSession,
        shareHealth: Boolean,
        includeEvents: Boolean,
    ): PostResult {
        val payload = session.toPayload(shareHealth = shareHealth, includeEvents = includeEvents)
        val body = json.encodeToString(SessionPayload.serializer(), payload)
        val url = buildUrl(config.baseUrl, "v1/padel-sessions")

        val response = try {
            transport.request(
                method = "POST",
                url = url,
                headers = authHeaders(config) + mapOf(
                    "Content-Type" to "application/json",
                    // La clave de idempotencia es el propio sessionId: reintentar no duplica.
                    "Idempotency-Key" to session.sessionId,
                ),
                body = body,
            )
        } catch (e: HttpTransportException) {
            return PostResult.Done(UploadOutcome.TransientFailure(e.message ?: "fallo de red"))
        }

        if (response.code == 413) return PostResult.TooLarge

        val outcome = when (response.code) {
            200, 201 -> {
                val ref = runCatching {
                    json.decodeFromString(SessionRefResponse.serializer(), response.body)
                }.getOrNull()
                UploadOutcome.Success(remoteId = ref?.id, created = response.code == 201)
            }

            401, 403 -> UploadOutcome.AuthFailure(errorMessage(response.body) ?: "Token no válido")

            400, 409, 422 -> UploadOutcome.PermanentFailure(
                code = errorCode(response.body),
                message = errorMessage(response.body) ?: "El servidor rechazó la sesión (${response.code})",
            )

            429 -> UploadOutcome.RateLimited(response.header("Retry-After")?.toLongOrNull())

            else -> UploadOutcome.TransientFailure(
                errorMessage(response.body) ?: "Error del servidor (${response.code})"
            )
        }
        return PostResult.Done(outcome)
    }

    private fun authHeaders(config: LeagueConfig) = mapOf(
        "Authorization" to "Bearer ${config.token}",
        "Accept" to "application/json",
    )

    private fun errorBody(body: String): ApiErrorBody? =
        runCatching { json.decodeFromString(ApiErrorResponse.serializer(), body).error }.getOrNull()

    private fun errorCode(body: String): String? = errorBody(body)?.code

    private fun errorMessage(body: String): String? = errorBody(body)?.message?.takeIf { it.isNotBlank() }

    companion object {
        val defaultJson = Json {
            ignoreUnknownKeys = true
            explicitNulls = false
            encodeDefaults = true
        }

        internal fun buildUrl(baseUrl: String, path: String): String =
            baseUrl.trimEnd('/') + "/" + path.trimStart('/')
    }
}
