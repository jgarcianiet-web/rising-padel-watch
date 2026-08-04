package com.risingpadel.mobile.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.dp
import com.risingpadel.core.analytics.SessionAnalytics
import com.risingpadel.core.model.PadelSession
import com.risingpadel.core.model.ShotType

/**
 * Las tres gráficas de análisis, dibujadas a mano con Compose (sin dependencias de
 * gráficas). Los datos salen de `SessionAnalytics` en el core; aquí solo se pinta,
 * para que iPhone enseñe exactamente las mismas curvas.
 */

// MARK: Frecuencia de golpeo

@Composable
fun FrequencyChartCard(session: PadelSession) {
    if (session.shots.isEmpty()) return
    var intervalMinutes by remember { mutableStateOf(10) }
    val buckets = remember(session.sessionId, intervalMinutes) {
        SessionAnalytics().shotFrequency(
            shots = session.shots,
            durationMs = session.durationSeconds * 1000,
            intervalMs = intervalMinutes * 60_000L,
        )
    }
    if (buckets.isEmpty()) return
    val maxCount = buckets.maxOf { it.count }.coerceAtLeast(1)

    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text("Frecuencia de golpeo", style = MaterialTheme.typography.titleMedium)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf(5, 10).forEach { minutes ->
                    FilterChip(
                        selected = intervalMinutes == minutes,
                        onClick = { intervalMinutes = minutes },
                        label = { Text("$minutes min") },
                    )
                }
            }

            // Barras por layout y no por Canvas: los pesos hacen el reparto solos y el
            // texto de la etiqueta queda alineado con su barra sin medir nada.
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 8.dp)
                    .height(140.dp),
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                verticalAlignment = Alignment.Bottom,
            ) {
                buckets.forEach { bucket ->
                    Column(
                        modifier = Modifier.weight(1f),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        val fraction = bucket.count.toFloat() / maxCount
                        Spacer(modifier = Modifier.weight((1f - fraction).coerceAtLeast(0.001f)))
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                // Un mínimo visible: la barra de un intervalo vacío se ve
                                // como poso, no desaparece.
                                .weight(fraction.coerceAtLeast(0.02f))
                                .clip(RoundedCornerShape(topStart = 4.dp, topEnd = 4.dp))
                                .background(
                                    if (bucket.count > 0) MaterialTheme.colorScheme.primary
                                    else MaterialTheme.colorScheme.surfaceVariant
                                ),
                        )
                    }
                }
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(
                    offsetLabel(buckets.first().endMs),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    "máx $maxCount golpeos",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    offsetLabel(buckets.last().endMs),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

// MARK: Progreso de la sesión

@Composable
fun ProgressChartCard(session: PadelSession, playerAverage: Float?) {
    val points = remember(session.sessionId) {
        SessionAnalytics().levelProgression(
            shots = session.shots,
            durationMs = session.durationSeconds * 1000,
        )
    }
    if (points.size < 2) return

    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text("Progreso de la sesión", style = MaterialTheme.typography.titleMedium)
            LevelLineChart(
                points = points.map { it.offsetMs.toFloat() to it.level },
                average = playerAverage,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 12.dp)
                    .height(150.dp),
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(
                    "inicio",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                playerAverage?.let {
                    Text(
                        "tu media %.2f".format(it),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.tertiary,
                    )
                }
                Text(
                    offsetLabel(points.last().offsetMs),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

// MARK: Nivel de los últimos partidos

@Composable
fun LevelHistoryCard(sessions: List<PadelSession>) {
    var filter by remember { mutableStateOf<ShotType?>(null) }
    val points = remember(sessions, filter) {
        val analytics = SessionAnalytics()
        val selected = filter
        // Se ordena antes de recortar para no depender del orden en que llegue la
        // lista: siempre son las N sesiones más recientes, de vieja a nueva.
        sessions
            .sortedBy { it.startedAtEpochMs }
            .takeLast(MAX_HISTORY_SESSIONS)
            .mapNotNull { session ->
                val level = if (selected != null) {
                    analytics.typeGrade(session.shots, selected)
                } else {
                    session.level.takeIf { it.gradedShots > 0 }?.overall
                }
                level?.let { session.startedAtEpochMs to it }
            }
    }

    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text("Nivel últimos partidos", style = MaterialTheme.typography.titleMedium)
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                FilterChip(
                    selected = filter == null,
                    onClick = { filter = null },
                    label = { Text("Todos") },
                )
                filterableTypes.forEach { type ->
                    FilterChip(
                        selected = filter == type,
                        onClick = { filter = type },
                        label = { Text(type.label()) },
                    )
                }
            }
            if (points.size < 2) {
                Text(
                    "Con dos o más sesiones aparecerá aquí la evolución de tu nivel.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 8.dp),
                )
            } else {
                LevelLineChart(
                    // El eje X es el índice y no la época: la época en ms no cabe en la
                    // precisión de un Float, y dos sesiones del mismo día acabarían en
                    // el mismo píxel. El reparto uniforme además se lee mejor.
                    points = points.mapIndexed { index, (_, level) -> index.toFloat() to level },
                    average = null,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 12.dp)
                        .height(150.dp),
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text(
                        formatSessionDate(points.first().first),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        formatSessionDate(points.last().first),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

/** Sin `unknown` (no se puntúa): si un golpe no aparece, la gráfica avisa sola. */
private val filterableTypes = ShotType.entries.filter { it != ShotType.UNKNOWN }

/** Más allá de esto la gráfica en un móvil es una raya apretada sin lectura. */
private const val MAX_HISTORY_SESSIONS = 15

// MARK: La curva

/**
 * Curva de nivel: eje X en la unidad que traigan los puntos (ms de sesión o época),
 * eje Y ceñido a la zona con datos — en la escala 1-7 entera la variación de una
 * sesión sería una raya plana que no cuenta nada.
 */
@Composable
private fun LevelLineChart(
    points: List<Pair<Float, Float>>,
    average: Float?,
    modifier: Modifier = Modifier,
) {
    val lineColor = MaterialTheme.colorScheme.primary
    val fillColor = lineColor.copy(alpha = 0.15f)
    val averageColor = MaterialTheme.colorScheme.tertiary

    val levels = points.map { it.second }
    var yMin = (levels.min() - 0.2f).coerceAtLeast(1f)
    var yMax = (levels.max() + 0.2f).coerceAtMost(7f)
    if (average != null) {
        yMin = minOf(yMin, average - 0.1f).coerceAtLeast(1f)
        yMax = maxOf(yMax, average + 0.1f).coerceAtMost(7f)
    }
    val ySpan = (yMax - yMin).coerceAtLeast(0.1f)
    val xMin = points.first().first
    val xSpan = (points.last().first - xMin).coerceAtLeast(1f)

    Canvas(modifier = modifier) {
        fun x(value: Float) = (value - xMin) / xSpan * size.width
        fun y(value: Float) = size.height - (value - yMin) / ySpan * size.height

        val line = Path()
        points.forEachIndexed { index, (px, py) ->
            if (index == 0) line.moveTo(x(px), y(py)) else line.lineTo(x(px), y(py))
        }

        val fill = Path().apply {
            addPath(line)
            lineTo(x(points.last().first), size.height)
            lineTo(x(points.first().first), size.height)
            close()
        }
        drawPath(
            path = fill,
            brush = Brush.verticalGradient(listOf(fillColor, Color.Transparent)),
        )

        average?.let {
            drawLine(
                color = averageColor,
                start = Offset(0f, y(it)),
                end = Offset(size.width, y(it)),
                strokeWidth = 2.dp.toPx(),
                pathEffect = PathEffect.dashPathEffect(floatArrayOf(12f, 8f)),
            )
        }

        drawPath(
            path = line,
            color = lineColor,
            style = Stroke(
                width = 3.dp.toPx(),
                cap = StrokeCap.Round,
                join = StrokeJoin.Round,
            ),
        )

        points.forEach { (px, py) ->
            drawCircle(color = lineColor, radius = 4.dp.toPx(), center = Offset(x(px), y(py)))
        }
    }
}

private fun offsetLabel(offsetMs: Long): String {
    val totalMinutes = offsetMs / 60_000
    return "%d:%02d".format(totalMinutes / 60, totalMinutes % 60)
}
