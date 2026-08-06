package com.risingpadel.mobile.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.risingpadel.core.model.PadelSession
import com.risingpadel.mobile.data.LigaStore
import com.risingpadel.mobile.ui.formatDuration
import com.risingpadel.mobile.ui.formatSessionDate

/**
 * La portada de tres segundos: nivel actual y tendencia, racha de la liga, meta de la
 * temporada y el objetivo del momento. La última sesión completa queda a un toque —
 * el mismo diseño que iOS.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InicioScreen(
    session: PadelSession,
    playerAverageLevel: Float?,
    onOpenSession: () -> Unit,
    onOpenSettings: () -> Unit,
) {
    val context = LocalContext.current
    // La liga se relee al entrar: la portada mezcla sesiones y partidos.
    val liga = remember { LigaStore(context).load() }
    val temporada = liga.temporadas.lastOrNull { it.enCurso }
    val delPeriodo = if (temporada != null) {
        liga.matches.filter { temporada.contiene(it) }
    } else {
        liga.matches
    }
    val ultimos = liga.matches.sortedByDescending { it.id }.take(5)
    val nivel = session.level.takeIf { it.gradedShots > 0 }?.overall ?: playerAverageLevel

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Inicio") },
                actions = {
                    IconButton(onClick = onOpenSettings) {
                        Icon(Icons.Default.Settings, contentDescription = "Ajustes")
                    }
                },
            )
        },
    ) { padding ->
        Column(
            Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Row(verticalAlignment = Alignment.Top) {
                        Column {
                            Text(
                                nivel?.let { "%.1f".format(it) } ?: "—",
                                style = MaterialTheme.typography.displayMedium,
                                fontWeight = FontWeight.Black,
                                color = MaterialTheme.colorScheme.secondary,
                            )
                            Text("nivel actual", style = MaterialTheme.typography.bodySmall)
                        }
                        Spacer(Modifier.weight(1f))
                        if (nivel != null && playerAverageLevel != null &&
                            kotlin.math.abs(nivel - playerAverageLevel) >= 0.05f
                        ) {
                            val diff = nivel - playerAverageLevel
                            Text(
                                (if (diff >= 0) "▲ +%.1f" else "▼ %.1f").format(diff),
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.Black,
                                color = if (diff >= 0) MaterialTheme.colorScheme.primary
                                else MaterialTheme.colorScheme.error,
                            )
                        }
                    }

                    if (ultimos.isNotEmpty()) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                        ) {
                            Text("RACHA", style = MaterialTheme.typography.labelSmall)
                            ultimos.forEach { match ->
                                val victoria = match.resultado == "victoria"
                                Text(
                                    if (victoria) "V" else "D",
                                    modifier = Modifier
                                        .size(22.dp)
                                        .background(
                                            if (victoria) MaterialTheme.colorScheme.primary
                                            else MaterialTheme.colorScheme.error,
                                            CircleShape,
                                        ),
                                    color = MaterialTheme.colorScheme.onPrimary,
                                    style = MaterialTheme.typography.labelMedium,
                                    fontWeight = FontWeight.Black,
                                    textAlign = TextAlign.Center,
                                )
                            }
                        }
                    }

                    temporada?.objetivoPartidos?.takeIf { it > 0 }?.let { meta ->
                        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                Text("Partidos de la temporada",
                                    style = MaterialTheme.typography.bodySmall)
                                Text("${delPeriodo.size}/$meta",
                                    style = MaterialTheme.typography.bodySmall,
                                    fontWeight = FontWeight.Bold)
                            }
                            LinearProgressIndicator(
                                progress = {
                                    (delPeriodo.size.toFloat() / meta).coerceIn(0f, 1f)
                                },
                                modifier = Modifier.fillMaxWidth(),
                                color = MaterialTheme.colorScheme.secondary,
                            )
                        }
                    }

                    liga.objetivos.firstOrNull()?.let { objetivo ->
                        Text(
                            "🎯 $objetivo",
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.SemiBold,
                        )
                    }
                }
            }

            Card(Modifier.fillMaxWidth(), onClick = onOpenSession) {
                Row(
                    Modifier.fillMaxWidth().padding(16.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column {
                        Text("Última sesión", style = MaterialTheme.typography.labelMedium)
                        Text(
                            formatSessionDate(session.startedAtEpochMs),
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.Bold,
                        )
                        Text(
                            "${session.totalShots} golpeos · ${formatDuration(session.durationSeconds)}",
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                    val score = session.score
                    if (score?.isFinished == true) {
                        Text(
                            if (score.winner == com.risingpadel.core.score.Side.US) "GANADO" else "PERDIDO",
                            style = MaterialTheme.typography.labelMedium,
                            fontWeight = FontWeight.Black,
                            color = if (score.winner == com.risingpadel.core.score.Side.US) {
                                MaterialTheme.colorScheme.primary
                            } else {
                                MaterialTheme.colorScheme.error
                            },
                        )
                    } else {
                        Text("VER →", style = MaterialTheme.typography.labelMedium,
                            fontWeight = FontWeight.Black,
                            color = MaterialTheme.colorScheme.primary)
                    }
                }
            }
        }
    }
}
