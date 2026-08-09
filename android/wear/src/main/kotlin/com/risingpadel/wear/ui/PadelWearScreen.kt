package com.risingpadel.wear.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.Chip
import androidx.wear.compose.material.ChipDefaults
import androidx.wear.compose.material.CircularProgressIndicator
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import com.risingpadel.core.level.label
import com.risingpadel.core.model.ShotType
import com.risingpadel.core.score.DeuceFormat
import com.risingpadel.wear.service.SessionStatus
import com.risingpadel.wear.service.SessionUiState

@Composable
fun PadelWearScreen(
    state: SessionUiState,
    healthPermissionDenied: Boolean,
    deuceFormat: DeuceFormat,
    collectTrainingData: Boolean,
    onOpenTraining: () -> Unit,
    onOpenRutinas: () -> Unit,
    onStartMatch: (DeuceFormat) -> Unit,
    onStartFree: () -> Unit,
    onStop: () -> Unit,
    onSkipStep: () -> Unit,
    onDone: () -> Unit,
) {
    // Con varios botones la columna no cabe en un reloj pequeño; sin scroll, lo de
    // abajo queda directamente inalcanzable.
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 12.dp, vertical = 20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        when (state.status) {
            SessionStatus.IDLE -> IdleContent(
                healthPermissionDenied = healthPermissionDenied,
                deuceFormat = deuceFormat,
                collectTrainingData = collectTrainingData,
                onOpenTraining = onOpenTraining,
                onOpenRutinas = onOpenRutinas,
                onStartMatch = onStartMatch,
                onStartFree = onStartFree,
            )
            SessionStatus.PREPARING -> LoadingContent("Preparando…")
            SessionStatus.RECORDING -> RecordingContent(state, onStop, onSkipStep)
            SessionStatus.SAVING -> LoadingContent("Guardando…")
            SessionStatus.SAVED -> SummaryContent(state, onDone)
            SessionStatus.ERROR -> ErrorContent(state.errorMessage, onDone)
        }
    }
}

/**
 * Dos decisiones y ya: Partido (elige el 40-40 y arranca con marcador) o Entreno
 * (arranca sin marcador al momento). Nada de interruptores ni formularios: en la
 * puerta de la pista se elige qué se va a jugar, no se configura nada.
 */
@Composable
private fun IdleContent(
    healthPermissionDenied: Boolean,
    deuceFormat: DeuceFormat,
    collectTrainingData: Boolean,
    onOpenTraining: () -> Unit,
    onOpenRutinas: () -> Unit,
    onStartMatch: (DeuceFormat) -> Unit,
    onStartFree: () -> Unit,
) {
    // Al salir del estado IDLE este composable abandona la composición, así que la
    // subpantalla de formato se resetea sola al volver: no hace falta limpiarla.
    var choosingFormat by remember { mutableStateOf(false) }

    if (choosingFormat) {
        FormatChooser(
            lastUsed = deuceFormat,
            onPick = onStartMatch,
            onBack = { choosingFormat = false },
        )
        return
    }

    Text(
        text = "Rising Padel",
        style = MaterialTheme.typography.title3,
        textAlign = TextAlign.Center,
    )
    if (healthPermissionDenied) {
        Text(
            text = "Sin permiso de FC: se contarán golpeos, pero no datos de salud",
            style = MaterialTheme.typography.caption2,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(vertical = 6.dp),
        )
    }
    Chip(
        onClick = { choosingFormat = true },
        label = { Text("Partido", style = MaterialTheme.typography.button) },
        colors = ChipDefaults.primaryChipColors(),
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 8.dp),
    )
    Chip(
        onClick = onStartFree,
        label = { Text("Entreno", style = MaterialTheme.typography.button) },
        colors = ChipDefaults.secondaryChipColors(),
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 4.dp),
    )
    // Entreno con guion: el reloj canta el ejercicio y lleva la cuenta.
    Chip(
        onClick = onOpenRutinas,
        label = { Text("Rutina", style = MaterialTheme.typography.button) },
        colors = ChipDefaults.secondaryChipColors(),
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 4.dp),
    )

    // Solo aparece si el usuario ha activado la recogida de datos en el móvil: es un
    // modo para quien está construyendo el dataset, no para jugar.
    if (collectTrainingData) {
        Chip(
            onClick = onOpenTraining,
            label = { Text("Datos de entrenamiento", style = MaterialTheme.typography.caption2) },
            colors = ChipDefaults.secondaryChipColors(),
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 4.dp),
        )
    }
}

/**
 * Elegir el formato ES arrancar el partido: un toque, sin pantalla extra de
 * confirmación. El último formato usado va resaltado.
 */
@Composable
private fun FormatChooser(
    lastUsed: DeuceFormat,
    onPick: (DeuceFormat) -> Unit,
    onBack: () -> Unit,
) {
    Text(
        text = "¿A 40-40?",
        style = MaterialTheme.typography.caption1,
        textAlign = TextAlign.Center,
    )
    DeuceFormat.entries.forEach { format ->
        Chip(
            onClick = { onPick(format) },
            label = { Text(format.label, style = MaterialTheme.typography.caption1) },
            colors = if (format == lastUsed) {
                ChipDefaults.primaryChipColors()
            } else {
                ChipDefaults.secondaryChipColors()
            },
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 4.dp),
        )
    }
    Chip(
        onClick = onBack,
        label = { Text("Atrás", style = MaterialTheme.typography.caption2) },
        colors = ChipDefaults.childChipColors(),
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 4.dp),
    )
}

@Composable
private fun LoadingContent(label: String) {
    CircularProgressIndicator()
    Text(
        text = label,
        style = MaterialTheme.typography.caption1,
        modifier = Modifier.padding(top = 8.dp),
    )
}

@Composable
private fun RecordingContent(
    state: SessionUiState,
    onStop: () -> Unit,
    onSkipStep: () -> Unit,
) {
    // Con rutina, lo que manda es el ejercicio: el contador de golpeos de la sesión
    // entera no dice nada útil a mitad de una tanda de veinte bandejas.
    state.rutina?.let { progreso ->
        RutinaEnCursoPanel(progreso = progreso, onSaltar = onSkipStep)
        Button(onClick = onStop, modifier = Modifier.padding(top = 6.dp)) {
            Text("Parar")
        }
        return
    }
    if (state.rutinaTerminada) {
        RutinaTerminadaPanel(onParar = onStop)
        return
    }

    Text(
        text = "${state.shotCount}",
        style = MaterialTheme.typography.display1,
    )
    Text(
        text = "golpeos",
        style = MaterialTheme.typography.caption1,
    )
    Text(
        text = buildString {
            append(formatDuration(state.elapsedSeconds))
            state.heartRateBpm?.let { append(" · $it ppm") }
        },
        style = MaterialTheme.typography.caption2,
        modifier = Modifier.padding(top = 4.dp),
    )
    state.lastShotType?.let {
        Text(
            text = it.label(),
            style = MaterialTheme.typography.caption2,
            color = MaterialTheme.colors.primary,
        )
    }
    if (state.wrongWristWarning) {
        Text(
            text = "Reloj en la muñeca sin pala: el conteo no será fiable",
            style = MaterialTheme.typography.caption3,
            textAlign = TextAlign.Center,
            color = MaterialTheme.colors.error,
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 4.dp),
        )
    }
    Button(onClick = onStop, modifier = Modifier.padding(top = 10.dp)) {
        Text("Parar")
    }
}

@Composable
private fun SummaryContent(state: SessionUiState, onDone: () -> Unit) {
    Text("Sesión guardada", style = MaterialTheme.typography.title3, textAlign = TextAlign.Center)
    Text(
        text = "${state.shotCount} golpeos · ${formatDuration(state.elapsedSeconds)}",
        style = MaterialTheme.typography.caption1,
        modifier = Modifier.padding(top = 6.dp),
    )
    // El nivel se enseña al acabar y no en vivo: mirarlo subir y bajar entre puntos no
    // aporta nada y distrae del partido.
    state.level?.let { level ->
        Text(
            text = level.label(),
            style = MaterialTheme.typography.caption1,
            color = MaterialTheme.colors.primary,
            modifier = Modifier.padding(top = 4.dp),
        )
    }
    state.errorMessage?.let {
        Text(
            text = it,
            style = MaterialTheme.typography.caption3,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(top = 6.dp),
        )
    }
    Button(onClick = onDone, modifier = Modifier.padding(top = 10.dp)) {
        Text("Hecho")
    }
}

@Composable
private fun ErrorContent(message: String?, onDone: () -> Unit) {
    Text(
        text = message ?: "No se pudo medir la sesión",
        style = MaterialTheme.typography.caption1,
        textAlign = TextAlign.Center,
        color = MaterialTheme.colors.error,
    )
    Button(onClick = onDone, modifier = Modifier.padding(top = 10.dp)) {
        Text("Cerrar")
    }
}

private fun formatDuration(seconds: Long): String {
    val minutes = seconds / 60
    val remaining = seconds % 60
    return "%d:%02d".format(minutes, remaining)
}

internal fun ShotType.label(): String = when (this) {
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

@Preview(device = "id:wearos_small_round", showSystemUi = true)
@Composable
private fun RecordingPreview() {
    MaterialTheme {
        PadelWearScreen(
            state = SessionUiState(
                status = SessionStatus.RECORDING,
                elapsedSeconds = 1_845,
                shotCount = 214,
                heartRateBpm = 143,
                lastShotType = ShotType.FOREHAND,
            ),
            healthPermissionDenied = false,
            deuceFormat = DeuceFormat.STAR_POINT,
            collectTrainingData = false,
            onOpenTraining = {},
            onOpenRutinas = {},
            onStartMatch = {},
            onStartFree = {},
            onStop = {},
            onSkipStep = {},
            onDone = {},
        )
    }
}
