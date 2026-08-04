package com.risingpadel.wear.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.Chip
import androidx.wear.compose.material.ChipDefaults
import androidx.wear.compose.material.CompactChip
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import com.risingpadel.core.score.DeuceFormat
import com.risingpadel.core.score.MatchScore
import com.risingpadel.core.score.ScoreRules
import com.risingpadel.core.score.Side

/**
 * Marcador del partido.
 *
 * La pantalla entera son dos zonas de toque: **mitad de arriba, punto nuestro; mitad de
 * abajo, punto suyo**. No hay botones que acertar porque entre punto y punto hay tres
 * segundos y una pala en la mano.
 *
 * **Mantener pulsado deshace el último punto**, directo y sin menús: es la corrección
 * frecuente y en mitad de un partido no hay tiempo que perder. Finalizar tiene su propio
 * botón pequeño en la franja central — es la acción rara, y pasa por una confirmación
 * porque un punto mal anotado se deshace pero una sesión cerrada no.
 *
 * No se usa deslizar para nada: el deslizamiento horizontal está tomado por el gesto de
 * volver atrás del sistema.
 */
@Composable
fun ScoreScreen(
    score: MatchScore,
    shotCount: Int,
    onPoint: (Side) -> Unit,
    onUndo: () -> Unit,
    onStop: () -> Unit,
) {
    var confirmStop by remember { mutableStateOf(false) }

    if (confirmStop) {
        ConfirmStop(
            onStop = onStop,
            onDismiss = { confirmStop = false },
        )
        return
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .pointerInput(Unit) {
                detectTapGestures(
                    onTap = { offset: Offset ->
                        onPoint(if (offset.y < size.height / 2f) Side.US else Side.THEM)
                    },
                    onLongPress = { onUndo() },
                )
            },
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 10.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            SetsRow(score)

            Row(
                modifier = Modifier.padding(top = 2.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                PointsBlock(score, Side.US)
                Text(
                    text = "·",
                    style = MaterialTheme.typography.display2,
                    modifier = Modifier.padding(horizontal = 8.dp),
                )
                PointsBlock(score, Side.THEM)
            }

            // El botón vive en la franja central, la zona neutra entre las dos mitades
            // de toque: un dedo que acabe aquí ya era ambiguo como punto.
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.padding(top = 4.dp),
            ) {
                Text(
                    text = statusLine(score, shotCount),
                    style = MaterialTheme.typography.caption3,
                    textAlign = TextAlign.Center,
                    color = MaterialTheme.colors.onSurfaceVariant,
                )
                if (!score.isFinished) {
                    CompactChip(
                        onClick = { confirmStop = true },
                        label = { Text("Fin", style = MaterialTheme.typography.caption3) },
                        colors = ChipDefaults.secondaryChipColors(),
                        modifier = Modifier.padding(start = 6.dp),
                    )
                }
            }

            // El punto decisivo hay que saber que se está jugando: con star point llega
            // sin avisar tras dos ventajas.
            if (score.isGoldenPoint) {
                Text(
                    text = "PUNTO DE ORO",
                    style = MaterialTheme.typography.caption2,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colors.error,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            if (score.changeEndsPending) {
                Text(
                    text = "Cambio de pista",
                    style = MaterialTheme.typography.caption2,
                    color = MaterialTheme.colors.primary,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            if (score.isFinished) {
                Text(
                    text = if (score.winner == Side.US) "¡Partido ganado!" else "Partido perdido",
                    style = MaterialTheme.typography.caption1,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colors.primary,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth(),
                )
                // Con el partido cerrado ya no hay puntos que anotar: el botón de
                // finalizar puede ocupar el sitio sin robarle nada a nadie.
                Button(onClick = onStop, modifier = Modifier.padding(top = 4.dp)) {
                    Text("Finalizar", style = MaterialTheme.typography.caption1)
                }
            }
        }
    }
}

/**
 * Confirmación de finalizar, a pantalla completa: en un reloj redondo un diálogo
 * flotante deja zonas de toque ambiguas alrededor.
 */
@Composable
private fun ConfirmStop(onStop: () -> Unit, onDismiss: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            text = "¿Finalizar la sesión?",
            style = MaterialTheme.typography.caption1,
            textAlign = TextAlign.Center,
        )
        Chip(
            onClick = onStop,
            label = { Text("Finalizar", style = MaterialTheme.typography.caption1) },
            colors = ChipDefaults.primaryChipColors(),
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 8.dp),
        )
        Chip(
            onClick = onDismiss,
            label = { Text("Seguir jugando", style = MaterialTheme.typography.caption1) },
            colors = ChipDefaults.secondaryChipColors(),
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 6.dp),
        )
    }
}

@Composable
private fun SetsRow(score: MatchScore) {
    val sets = score.allSets
    Text(
        text = sets.joinToString("  ") { "${it.us}-${it.them}" },
        style = MaterialTheme.typography.caption1,
        color = MaterialTheme.colors.onSurfaceVariant,
    )
}

@Composable
private fun PointsBlock(score: MatchScore, side: Side) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(
            text = score.pointsLabel(side),
            fontSize = 40.sp,
            fontWeight = FontWeight.Bold,
            color = if (side == Side.US) MaterialTheme.colors.primary else MaterialTheme.colors.onSurface,
        )
        // Punto de saque: a quién le toca sacar es la pregunta que más veces surge en
        // mitad de un partido.
        Box(
            modifier = Modifier
                .padding(top = 3.dp)
                .size(6.dp)
                .background(
                    color = if (score.server == side) MaterialTheme.colors.primary else Color.Transparent,
                    shape = CircleShape,
                ),
        )
    }
}

private fun statusLine(score: MatchScore, shotCount: Int): String = buildString {
    append(if (score.server == Side.US) "Sacamos" else "Sacan")
    if (score.isTieBreak) append(" · tie-break")
    append(" · $shotCount golpeos")
}

@Preview(device = "id:wearos_small_round", showSystemUi = true)
@Composable
private fun ScorePreview() {
    MaterialTheme {
        val score = MatchScore.start(ScoreRules(deuceFormat = DeuceFormat.STAR_POINT))
            .pointTo(Side.US)
            .pointTo(Side.US)
            .pointTo(Side.THEM)
        ScoreScreen(score = score, shotCount = 128, onPoint = {}, onUndo = {}, onStop = {})
    }
}
