package com.risingpadel.core.settings

import com.risingpadel.core.detection.Sensitivity
import com.risingpadel.core.model.PlayerProfile
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * Los ajustes que el móvil replica al reloj.
 *
 * Es el subconjunto de preferencias que **el reloj necesita para medir** y que solo se
 * pueden configurar cómodamente en el móvil: escribir un alias o elegir la muñeca en una
 * pantalla de 45 mm es una mala idea.
 *
 * Deliberadamente **no** entran aquí:
 * - `trackScore`, `deuceFormat` y `setsToWin`: se deciden en el reloj al empezar el
 *   partido, que es cuando el jugador sabe si va a llevar marcador. Replicarlos desde el
 *   móvil pisaría lo que acaba de elegir en la muñeca.
 * - La URL de la liga y el token: el reloj no habla con la liga, habla con el móvil. Un
 *   token es una credencial y cuantos menos sitios la tengan, mejor.
 */
@Serializable
data class DeviceSettings(
    val profile: PlayerProfile = PlayerProfile(),
    val sensitivity: Sensitivity = Sensitivity.MEDIUM,
    /** Consentimiento explícito para medir y compartir datos de salud. */
    val shareHealth: Boolean = false,
    /** Modo de recogida de datos de entrenamiento. Ver `docs/training-data.md`. */
    val collectTrainingData: Boolean = false,
    /** Alias del jugador, para poder validar el modelo dejándolo fuera. */
    val playerAlias: String = DEFAULT_ALIAS,
    /**
     * Cuándo se editaron estos ajustes en el dispositivo de origen.
     *
     * Es lo que hace que la replicación sea segura: el Data Layer y WatchConnectivity
     * **reentregan** el último estado al reconectar, así que sin marca de tiempo un
     * cambio hecho en el reloj lo pisaría un contexto viejo del móvil.
     */
    val updatedAtEpochMs: Long = 0L,
) {

    /**
     * Aplica [incoming] solo si es más reciente que lo que ya hay.
     *
     * Empate = gana lo local. Dos ediciones en el mismo milisegundo en dos dispositivos
     * distintos no pasa en la práctica, y ante la duda es preferible respetar lo que el
     * jugador tiene delante.
     */
    fun mergedWith(incoming: DeviceSettings): DeviceSettings =
        if (incoming.updatedAtEpochMs > updatedAtEpochMs) incoming else this

    companion object {
        const val DEFAULT_ALIAS = "anon"
        const val MAX_ALIAS_LENGTH = 24

        private val json = Json { encodeDefaults = true; ignoreUnknownKeys = true }

        /**
         * Normaliza el alias: minúsculas, sin espacios y acotado.
         *
         * El alias es la clave de agrupación en la validación leave-one-player-out, así
         * que "Marta" y "marta " tienen que ser el mismo jugador; si no, el modelo se
         * valida contra sí mismo y el número sale inflado.
         */
        fun sanitizeAlias(raw: String): String {
            val trimmed = raw.trim().lowercase().replace(WHITESPACE, "-")
            return if (trimmed.isEmpty()) DEFAULT_ALIAS else trimmed.take(MAX_ALIAS_LENGTH)
        }

        fun encode(settings: DeviceSettings): String =
            json.encodeToString(serializer(), settings)

        /** Devuelve null si el payload no es legible: mejor ignorarlo que romper. */
        fun decode(payload: String): DeviceSettings? =
            runCatching { json.decodeFromString(serializer(), payload) }.getOrNull()

        private val WHITESPACE = Regex("\\s+")
    }
}
