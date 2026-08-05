package com.risingpadel.mobile.data

import android.content.Context
import com.risingpadel.core.liga.LigaState
import com.risingpadel.core.liga.LigaTemporada
import kotlinx.serialization.json.Json
import java.io.File

/**
 * La liga en Android: el mismo fichero-estado que iOS y la app Expo.
 *
 * Guardar y exportar son la misma operación — el fichero ES el backup — así que un
 * historial importado del iPhone (o de la Expo) vive aquí sin transformación, y el
 * export vuelve allí igual. El dominio y las métricas viven en el core, con tests.
 */
class LigaStore(context: Context) {

    private val file = File(context.filesDir, "liga/estado.json")
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    fun load(): LigaState =
        runCatching { json.decodeFromString(LigaState.serializer(), file.readText()) }
            .getOrDefault(LigaState())

    fun save(state: LigaState) {
        file.parentFile?.mkdirs()
        file.writeText(json.encodeToString(LigaState.serializer(), state))
    }

    /** Importa un backup (sustituye el estado entero, como en iOS). Null si no es válido. */
    fun import(payload: String): LigaState? =
        runCatching { json.decodeFromString(LigaState.serializer(), payload) }
            .getOrNull()
            ?.also { save(it) }

    fun export(): String = json.encodeToString(LigaState.serializer(), load())

    /**
     * Cierra la temporada en curso (si la hay) en la víspera y abre la siguiente hoy —
     * la misma semántica que iOS: sin solapes ni días huérfanos.
     */
    fun startTemporada(objetivoPartidos: Int?): LigaState {
        val hoy = hoyIso()
        val state = load()
        val cerradas = state.temporadas.map { temporada ->
            if (temporada.enCurso) temporada.copy(fechaFin = vispera(hoy)) else temporada
        }
        val nueva = LigaTemporada(
            id = System.currentTimeMillis(),
            nombre = "Temporada ${state.temporadas.size + 1}",
            fechaInicio = hoy,
            objetivoPartidos = objetivoPartidos,
        )
        return state.copy(temporadas = cerradas + nueva).also(::save)
    }

    private fun hoyIso(): String =
        java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.ROOT)
            .format(java.util.Date())

    private fun vispera(iso: String): String {
        val formato = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.ROOT)
        val fecha = formato.parse(iso) ?: return iso
        return formato.format(java.util.Date(fecha.time - 24 * 60 * 60 * 1000))
    }
}
