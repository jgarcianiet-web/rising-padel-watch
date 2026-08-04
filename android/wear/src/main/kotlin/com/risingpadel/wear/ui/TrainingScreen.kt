package com.risingpadel.wear.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.Chip
import androidx.wear.compose.material.ChipDefaults
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import com.risingpadel.core.model.ShotType
import com.risingpadel.wear.training.TrainingUiState

/**
 * Modo de recogida de datos para entrenar el clasificador.
 *
 * La pantalla es deliberadamente aburrida: elige tipo, dale a grabar, pega treinta
 * golpes de ese tipo y para. Lo que la hace útil es que **la etiqueta se pone antes de
 * golpear**, no después mirando gráficas — que es donde fracasa el enfoque de "grábalo
 * todo y ya lo etiquetaremos".
 */
@Composable
fun TrainingScreen(
    state: TrainingUiState,
    onLabelChange: (ShotType) -> Unit,
    onStart: () -> Unit,
    onStop: () -> Unit,
    onSendToPhone: () -> Unit,
    onExit: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 10.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        if (state.recording) {
            Text(
                text = "${state.capturedInBatch}",
                style = MaterialTheme.typography.display1,
            )
            Text(
                text = state.label.label(),
                style = MaterialTheme.typography.caption1,
                color = MaterialTheme.colors.primary,
                textAlign = TextAlign.Center,
            )
            Text(
                text = "Da 30-40 golpes solo de este tipo",
                style = MaterialTheme.typography.caption3,
                textAlign = TextAlign.Center,
                color = MaterialTheme.colors.onSurfaceVariant,
                modifier = Modifier.fillMaxWidth(),
            )
            Button(onClick = onStop, modifier = Modifier.padding(top = 8.dp)) {
                Text("Parar tanda")
            }
        } else {
            Text(
                text = "Datos de entrenamiento",
                style = MaterialTheme.typography.caption1,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center,
            )
            // Toque = siguiente tipo. Se recorre la lista de golpes de la misma forma
            // que se graban: uno detrás de otro.
            Chip(
                onClick = { onLabelChange(state.label.next()) },
                label = { Text(state.label.label(), style = MaterialTheme.typography.caption1) },
                secondaryLabel = { Text("Tipo a grabar", style = MaterialTheme.typography.caption3) },
                colors = ChipDefaults.secondaryChipColors(),
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 6.dp),
            )
            Text(
                text = "${state.totalStored} guardados · ${state.storedBytes / 1024} KB",
                style = MaterialTheme.typography.caption3,
                color = MaterialTheme.colors.onSurfaceVariant,
                modifier = Modifier.padding(top = 4.dp),
            )
            Button(onClick = onStart, modifier = Modifier.padding(top = 6.dp)) {
                Text("Grabar")
            }
            if (state.totalStored > 0) {
                Chip(
                    onClick = onSendToPhone,
                    label = { Text("Enviar al móvil", style = MaterialTheme.typography.caption2) },
                    colors = ChipDefaults.secondaryChipColors(),
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 4.dp),
                )
            }
            Button(onClick = onExit, modifier = Modifier.padding(top = 4.dp)) {
                Text("Salir")
            }
        }
    }
}

/** Siguiente tipo de golpe, saltándose UNKNOWN: no es algo que se pueda grabar a propósito. */
private fun ShotType.next(): ShotType {
    val recordable = ShotType.entries.filter { it != ShotType.UNKNOWN }
    val index = recordable.indexOf(this)
    return recordable[(index + 1) % recordable.size]
}

@Preview(device = "id:wearos_small_round", showSystemUi = true)
@Composable
private fun TrainingPreview() {
    MaterialTheme {
        TrainingScreen(
            state = TrainingUiState(label = ShotType.BACKHAND, totalStored = 340, storedBytes = 2_400_000),
            onLabelChange = {},
            onStart = {},
            onStop = {},
            onSendToPhone = {},
            onExit = {},
        )
    }
}
