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
    ShotType.OVERHEAD -> "Bandeja / smash"
    ShotType.SERVE -> "Saque"
    ShotType.UNKNOWN -> "Sin clasificar"
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
