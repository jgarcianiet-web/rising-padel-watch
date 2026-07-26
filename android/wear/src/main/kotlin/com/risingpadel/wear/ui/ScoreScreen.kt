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
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
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
 * **Mantener pulsado deshace.** No se usa deslizar, que sería más natural, porque el
 * deslizamiento horizontal está tomado por el gesto de volver atrás del sistema en Wear
 * OS y por la navegación entre vistas en watchOS. Mantener pulsado está libre en las dos
 * plataformas y no se dispara por accidente.
 */
@Composable
fun ScoreScreen(
    score: MatchScore,
    shotCount: Int,
    onPoint: (Side) -> Unit,
    onUndo: () -> Unit,
) {
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

            Text(
                text = statusLine(score, shotCount),
                style = MaterialTheme.typography.caption3,
                textAlign = TextAlign.Center,
                color = MaterialTheme.colors.onSurfaceVariant,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 4.dp),
            )

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
            }
        }
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
        val score = MatchScore.start(ScoreRules(goldenPoint = true))
            .pointTo(Side.US)
            .pointTo(Side.US)
            .pointTo(Side.THEM)
        ScoreScreen(score = score, shotCount = 128, onPoint = {}, onUndo = {})
    }
}
