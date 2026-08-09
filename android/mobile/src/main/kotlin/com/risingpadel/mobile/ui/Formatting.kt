package com.risingpadel.mobile.ui

import com.risingpadel.core.model.ShotType
import com.risingpadel.core.model.SyncState
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

private val dateFormatter: DateTimeFormatter =
    DateTimeFormatter.ofPattern("d MMM yyyy · HH:mm", Locale("es", "ES"))

fun formatSessionDate(epochMs: Long): String =
    dateFormatter.format(Instant.ofEpochMilli(epochMs).atZone(ZoneId.systemDefault()))

fun formatDuration(seconds: Long): String {
    val hours = seconds / 3_600
    val minutes = (seconds % 3_600) / 60
    return if (hours > 0) "${hours}h ${minutes}min" else "${minutes}min"
}

fun ShotType.label(): String = when (this) {
    ShotType.FOREHAND -> "Derecha"
    ShotType.BACKHAND -> "Revés"
    ShotType.FOREHAND_VOLLEY -> "Volea de derecha"
    ShotType.BACKHAND_VOLLEY -> "Volea de revés"
    ShotType.BANDEJA -> "Bandeja"
    ShotType.VIBORA -> "Víbora"
    ShotType.SMASH -> "Smash"
    ShotType.SERVE -> "Saque"
    ShotType.UNKNOWN -> "Sin clasificar"
}

/**
 * Cómo acabó un partido de la liga.
 *
 * Existe porque el resto de la app trataba "todo lo que no sea victoria" como derrota, y
 * eso metía en la racha dos cosas que no lo son: los empates y, sobre todo, los partidos
 * guardados desde un entreno sin marcador. Ese "sin resultado" salía como D y contaba
 * como partido perdido en la racha y en el porcentaje de victorias sin que nadie hubiera
 * perdido nada.
 */
object ResultadoDePartido {
    const val SIN_RESULTADO = "sin resultado"

    fun letra(resultado: String): String = when (resultado) {
        "victoria" -> "V"
        "empate" -> "E"
        SIN_RESULTADO -> "—"
        else -> "D"
    }

    fun nombre(resultado: String): String = when (resultado) {
        "victoria" -> "Victoria"
        "empate" -> "Empate"
        SIN_RESULTADO -> "Sin resultado"
        else -> "Derrota"
    }

    /**
     * ¿Cuenta este partido para la racha y para el porcentaje de victorias?
     *
     * Un entreno sin marcador no cuenta: meterlo en el denominador bajaría el porcentaje
     * de victorias por haber entrenado, que es exactamente al revés.
     */
    fun cuenta(resultado: String): Boolean = resultado != SIN_RESULTADO
}

fun SyncState.label(): String = when (this) {
    SyncState.PENDING -> "Pendiente de subir"
    SyncState.SYNCED -> "En la liga"
    SyncState.FAILED -> "Falló la subida"
    SyncState.NEEDS_AUTH -> "Reconecta la liga"
}

fun zoneLabel(key: String): String = when (key) {
    "z1" -> "Z1 · suave"
    "z2" -> "Z2 · ligero"
    "z3" -> "Z3 · moderado"
    "z4" -> "Z4 · intenso"
    "z5" -> "Z5 · máximo"
    else -> key
}
