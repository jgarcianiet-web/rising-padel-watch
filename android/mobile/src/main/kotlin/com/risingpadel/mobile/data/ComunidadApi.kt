package com.risingpadel.mobile.data

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

/**
 * La comunidad en Android: el mismo servidor y las mismas rutas que iOS.
 *
 * El token de la cuenta ES la identidad, así que vive en EncryptedSharedPreferences —
 * el equivalente al Llavero — igual que el token de la liga. Sin push todavía: el
 * "está jugando" se consulta al abrir (FCM es un tramo aparte).
 */
class ComunidadApi(context: Context, private val baseUrl: () -> String) {

    companion object {
        /** El servidor oficial, de serie: el mismo que lleva iOS. */
        const val SERVIDOR_OFICIAL =
            "https://rising-padel-live.rising-padel-2d82dd5fe2.workers.dev"
    }

    data class Post(
        val id: Int,
        val alias: String,
        val texto: String,
        val creado: String,
        val reacciones: Int,
        val miReaccion: Boolean,
        val comentarios: Int,
    )

    data class Usuario(val alias: String, val siguiendo: Boolean)
    data class EnVivo(val alias: String, val sessionId: String)
    data class RankingFila(val alias: String, val partidos: Int, val victorias: Int, val golpeos: Int)

    private val secure = EncryptedSharedPreferences.create(
        context,
        "comunidad",
        MasterKey.Builder(context).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build(),
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
    )

    private val json = Json { ignoreUnknownKeys = true }

    var alias: String?
        get() = secure.getString("alias", null)
        private set(value) = secure.edit().putString("alias", value).apply()

    private var token: String?
        get() = secure.getString("token", null)
        set(value) = secure.edit().putString("token", value).apply()

    val tieneCuenta: Boolean get() = alias != null && token != null

    /** Crea la cuenta; devuelve null si fue bien o el mensaje de error. */
    suspend fun registrar(aliasNuevo: String): String? {
        val respuesta = llamar(
            "POST", "v1/comunidad/registro",
            body = buildJsonObject { put("alias", aliasNuevo.lowercase().trim()) },
            auth = false,
        ) ?: return "Sin conexión con la comunidad"
        val error = respuesta.jsonObject["error"]?.jsonObject
        if (error != null) return error["message"]?.jsonPrimitive?.content ?: "Error"
        alias = respuesta.jsonObject["alias"]?.jsonPrimitive?.content
        token = respuesta.jsonObject["token"]?.jsonPrimitive?.content
        return null
    }

    suspend fun muro(): List<Post> {
        val respuesta = llamar("GET", "v1/comunidad/muro") ?: return emptyList()
        return respuesta.jsonObject["posts"]?.jsonArray.orEmpty().map { fila ->
            val o = fila.jsonObject
            Post(
                id = o["id"]!!.jsonPrimitive.int,
                alias = o["alias"]!!.jsonPrimitive.content,
                texto = o["text"]!!.jsonPrimitive.content,
                creado = o["creado"]!!.jsonPrimitive.content.take(10),
                reacciones = o["reacciones"]?.jsonPrimitive?.int ?: 0,
                miReaccion = o["miReaccion"]?.jsonPrimitive?.contentOrNullSafe() != null,
                comentarios = o["comentarios"]?.jsonPrimitive?.int ?: 0,
            )
        }
    }

    suspend fun publicar(texto: String) {
        val etiquetas = texto.split(" ").filter { it.startsWith("@") }
            .map { it.removePrefix("@").lowercase() }
        llamar("POST", "v1/comunidad/publicar", buildJsonObject {
            put("texto", texto)
            put("etiquetas", kotlinx.serialization.json.JsonArray(
                etiquetas.map { kotlinx.serialization.json.JsonPrimitive(it) }
            ))
        })
    }

    suspend fun reaccionar(postId: Int) {
        llamar("POST", "v1/comunidad/reaccion", buildJsonObject {
            put("postId", postId)
            put("emoji", "🎾")
        })
    }

    suspend fun buscar(q: String): List<Usuario> {
        val codificado = URLEncoder.encode(q, "UTF-8")
        val respuesta = llamar("GET", "v1/comunidad/usuarios?q=$codificado") ?: return emptyList()
        return respuesta.jsonObject["usuarios"]?.jsonArray.orEmpty().map { fila ->
            val o = fila.jsonObject
            Usuario(
                alias = o["alias"]!!.jsonPrimitive.content,
                siguiendo = (o["siguiendo"]?.jsonPrimitive?.int ?: 0) != 0,
            )
        }
    }

    suspend fun seguir(usuario: Usuario) {
        llamar(if (usuario.siguiendo) "DELETE" else "POST", "v1/comunidad/seguir/${usuario.alias}")
    }

    suspend fun jugando(): List<EnVivo> {
        val respuesta = llamar("GET", "v1/comunidad/en-vivo") ?: return emptyList()
        return respuesta.jsonObject["jugando"]?.jsonArray.orEmpty().map { fila ->
            val o = fila.jsonObject
            EnVivo(o["alias"]!!.jsonPrimitive.content, o["sessionId"]!!.jsonPrimitive.content)
        }
    }

    suspend fun ranking(): List<RankingFila> {
        val respuesta = llamar("GET", "v1/comunidad/ranking") ?: return emptyList()
        return respuesta.jsonObject["ranking"]?.jsonArray.orEmpty().map { fila ->
            val o = fila.jsonObject
            RankingFila(
                alias = o["alias"]!!.jsonPrimitive.content,
                partidos = o["partidos"]?.jsonPrimitive?.int ?: 0,
                victorias = o["victorias"]?.jsonPrimitive?.int ?: 0,
                golpeos = o["golpeos"]?.jsonPrimitive?.int ?: 0,
            )
        }
    }

    /** El último estado en vivo de una sesión, en crudo, para el visor. */
    suspend fun estadoEnVivo(sessionId: String): JsonObject? =
        llamar("GET", "v1/live/$sessionId", auth = false)?.jsonObject

    /**
     * Republica el estado en vivo que llega del reloj Wear. El token de la cuenta
     * identifica al jugador: el servidor avisa a sus seguidores con el primer estado y
     * apunta el resultado al ranking con el último (completed).
     */
    suspend fun publicarEnVivo(sessionId: String, estadoJson: String): Boolean {
        if (token == null) return false
        val estado = runCatching { json.parseToJsonElement(estadoJson).jsonObject }
            .getOrNull() ?: return false
        return llamar("PUT", "v1/live/$sessionId", body = estado) != null
    }

    // ─── HTTP ───

    private suspend fun llamar(
        metodo: String,
        ruta: String,
        body: JsonObject? = null,
        auth: Boolean = true,
    ): kotlinx.serialization.json.JsonElement? = withContext(Dispatchers.IO) {
        val raiz = baseUrl().trim().trimEnd('/')
        if (raiz.isEmpty()) return@withContext null
        runCatching {
            val conexion = URL("$raiz/$ruta").openConnection() as HttpURLConnection
            conexion.requestMethod = metodo
            conexion.connectTimeout = 10_000
            conexion.readTimeout = 15_000
            if (auth) token?.let { conexion.setRequestProperty("Authorization", "Bearer $it") }
            if (body != null) {
                conexion.doOutput = true
                conexion.setRequestProperty("Content-Type", "application/json")
                conexion.outputStream.use { it.write(body.toString().toByteArray()) }
            }
            val texto = (if (conexion.responseCode < 400) conexion.inputStream else conexion.errorStream)
                ?.bufferedReader()?.use { it.readText() }.orEmpty()
            if (texto.isBlank()) buildJsonObject {} else json.parseToJsonElement(texto)
        }.getOrNull()
    }
}

private fun kotlinx.serialization.json.JsonPrimitive.contentOrNullSafe(): String? =
    if (this is kotlinx.serialization.json.JsonNull) null else content
