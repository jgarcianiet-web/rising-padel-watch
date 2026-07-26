package com.risingpadel.wear.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
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
import androidx.wear.compose.material.Switch
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.ToggleChip
import com.risingpadel.core.level.label
import com.risingpadel.core.model.ShotType
import com.risingpadel.core.score.DeuceFormat
import com.risingpadel.wear.service.SessionStatus
import com.risingpadel.wear.service.SessionUiState

@Composable
fun PadelWearScreen(
    state: SessionUiState,
    healthPermissionDenied: Boolean,
    trackScore: Boolean,
    deuceFormat: DeuceFormat,
    onTrackScoreChange: (Boolean) -> Unit,
    onDeuceFormatChange: (DeuceFormat) -> Unit,
    collectTrainingData: Boolean,
    onOpenTraining: () -> Unit,
    onStart: () -> Unit,
    onStop: () -> Unit,
    onDone: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        when (state.status) {
            SessionStatus.IDLE -> IdleContent(
                healthPermissionDenied = healthPermissionDenied,
                trackScore = trackScore,
                deuceFormat = deuceFormat,
                onTrackScoreChange = onTrackScoreChange,
                onDeuceFormatChange = onDeuceFormatChange,
                collectTrainingData = collectTrainingData,
                onOpenTraining = onOpenTraining,
                onStart = onStart,
            )
            SessionStatus.PREPARING -> LoadingContent("Preparando…")
            SessionStatus.RECORDING -> RecordingContent(state, onStop)
            SessionStatus.SAVING -> LoadingContent("Guardando…")
            SessionStatus.SAVED -> SummaryContent(state, onDone)
            SessionStatus.ERROR -> ErrorContent(state.errorMessage, onDone)
        }
    }
}

@Composable
private fun IdleContent(
    healthPermissionDenied: Boolean,
    trackScore: Boolean,
    deuceFormat: DeuceFormat,
    onTrackScoreChange: (Boolean) -> Unit,
    onDeuceFormatChange: (DeuceFormat) -> Unit,
    collectTrainingData: Boolean,
    onOpenTraining: () -> Unit,
    onStart: () -> Unit,
) {
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
    // El marcador se decide aquí, al empezar: un entreno suelto no lo necesita y un
    // partido de liga sí.
    ToggleChip(
        checked = trackScore,
        onCheckedChange = onTrackScoreChange,
        label = { Text("Llevar marcador", style = MaterialTheme.typography.caption1) },
        toggleControl = { Switch(checked = trackScore) },
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 8.dp),
    )

    // El formato de 40-40 solo importa si se lleva marcador, así que solo aparece
    // entonces. En una pantalla de reloj cada fila que sobra es una que estorba.
    if (trackScore) {
        // Toque = siguiente formato. Un selector de tres opciones no cabe en una pantalla
        // redonda sin comerse el botón de empezar, y es un ajuste que se toca una vez.
        Chip(
            onClick = { onDeuceFormatChange(deuceFormat.next()) },
            label = { Text(deuceFormat.label, style = MaterialTheme.typography.caption1) },
            secondaryLabel = { Text("A 40-40", style = MaterialTheme.typography.caption3) },
            colors = ChipDefaults.secondaryChipColors(),
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 4.dp),
        )
    }

    Button(onClick = onStart, modifier = Modifier.padding(top = 8.dp)) {
        Text("Empezar")
    }

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

/** Siguiente formato en la rueda, para el chip que cicla. */
private fun DeuceFormat.next(): DeuceFormat =
    DeuceFormat.entries[(ordinal + 1) % DeuceFormat.entries.size]

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
private fun RecordingContent(state: SessionUiState, onStop: () -> Unit) {
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
    ShotType.OVERHEAD -> "Bandeja / smash"
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
            trackScore = true,
            deuceFormat = DeuceFormat.STAR_POINT,
            onTrackScoreChange = {},
            onDeuceFormatChange = {},
            collectTrainingData = false,
            onOpenTraining = {},
            onStart = {},
            onStop = {},
            onDone = {},
        )
    }
}
