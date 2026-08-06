package com.risingpadel.mobile.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import com.risingpadel.core.level.SessionLevel
import com.risingpadel.core.model.HeartRateZones
import com.risingpadel.core.model.PadelSession
import com.risingpadel.core.score.MatchScore
import com.risingpadel.core.score.Side
import com.risingpadel.core.model.SyncState
import com.risingpadel.mobile.ui.FrequencyChartCard
import com.risingpadel.mobile.ui.ProgressChartCard
import com.risingpadel.mobile.ui.formatDuration
import com.risingpadel.mobile.ui.formatSessionDate
import com.risingpadel.mobile.ui.label
import com.risingpadel.mobile.ui.zoneLabel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SessionDetailScreen(
    session: PadelSession,
    /** Nivel medio del jugador en su historial, para la línea de referencia. */
    playerAverageLevel: Float?,
    /** Null cuando la pantalla es la portada "Última sesión": ahí no hay atrás. */
    onBack: (() -> Unit)?,
    onRetrySync: () -> Unit,
    onLinkMatch: (matchId: String, leagueId: String?) -> Unit,
    onDelete: () -> Unit,
    onOpenSettings: (() -> Unit)? = null,
    onApplyReview: ((Map<String, Int>) -> Unit)? = null,
) {
    // El guardado en la liga vive aquí y no en un ViewModel: es una acción puntual
    // sobre el fichero-estado de la liga, el mismo que la pestaña Liga.
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(formatSessionDate(session.startedAtEpochMs)) },
                navigationIcon = {
                    if (onBack != null) {
                        IconButton(onClick = onBack) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Volver")
                        }
                    }
                },
                actions = {
                    if (onOpenSettings != null) {
                        IconButton(onClick = onOpenSettings) {
                            Icon(Icons.Default.Settings, contentDescription = "Ajustes")
                        }
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            HeadlineStats(session)
            session.score?.let { ScoreCard(it) }
            session.level.takeIf { it.gradedShots > 0 }?.let { LevelCard(it) }
            FrequencyChartCard(session)
            ProgressChartCard(session, playerAverageLevel)
            ShotBreakdown(session)
            if (onApplyReview != null && session.shots.isNotEmpty()) {
                ReviewCard(session, onApplyReview)
            }
            if (!session.health.isEmpty) HealthCard(session)
            LigaSaveCard(session, playerAverageLevel)
            MatchLinkCard(session, onLinkMatch)
            SyncCard(session, onRetrySync)
            OutlinedButton(onClick = onDelete, modifier = Modifier.fillMaxWidth()) {
                Text("Borrar sesión del móvil")
            }
        }
    }
}

/**
 * "¿Acertó el reloj?": el jugador corrige los recuentos y sus números mandan en la
 * liga y en los objetivos. La comparación con lo que contó el reloj es la medida real
 * de la precisión del detector — la verdad-terreno que solo quien jugó puede dar.
 */
@Composable
private fun ReviewCard(session: PadelSession, onApplyReview: (Map<String, Int>) -> Unit) {
    var revisando by remember { mutableStateOf(false) }
    val precision = session.reviewAccuracy

    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("¿Acertó el reloj?", style = MaterialTheme.typography.titleMedium)
            if (precision != null) {
                Text(
                    "${(precision * 100).toInt()}% de precisión según tu revisión",
                    style = MaterialTheme.typography.titleLarge,
                    color = if (precision >= 0.85f) MaterialTheme.colorScheme.primary
                    else MaterialTheme.colorScheme.error,
                )
                Text(
                    "La liga y los objetivos usan tus recuentos.",
                    style = MaterialTheme.typography.bodySmall,
                )
                androidx.compose.material3.TextButton(onClick = { revisando = true }) {
                    Text("Volver a revisar")
                }
            } else {
                Text(
                    "Repasa los recuentos y corrige los que no cuadren. Tus " +
                        "correcciones mandan en la liga y en los objetivos.",
                    style = MaterialTheme.typography.bodyMedium,
                )
                Button(onClick = { revisando = true }, modifier = Modifier.fillMaxWidth()) {
                    Text("Revisar recuentos")
                }
            }
        }
    }

    if (revisando) {
        ReviewDialog(
            session = session,
            onSave = { corregidos ->
                onApplyReview(corregidos)
                revisando = false
            },
            onClose = { revisando = false },
        )
    }
}

@Composable
private fun ReviewDialog(
    session: PadelSession,
    onSave: (Map<String, Int>) -> Unit,
    onClose: () -> Unit,
) {
    // Los tipos que se revisan: lo detectado más los golpes altos, que son los que más
    // se confunden entre sí — "fueron 3 smashes aunque contara 0" es el caso útil.
    val altos = setOf(
        com.risingpadel.core.model.ShotType.BANDEJA,
        com.risingpadel.core.model.ShotType.VIBORA,
        com.risingpadel.core.model.ShotType.SMASH,
    )
    val tipos = com.risingpadel.core.model.ShotType.entries.filter {
        it != com.risingpadel.core.model.ShotType.UNKNOWN &&
            (it in session.shotsByType || it in altos)
    }
    val counts = remember {
        val base = session.effectiveShotsByType
        androidx.compose.runtime.mutableStateMapOf<String, Int>().apply {
            tipos.forEach { put(it.wireName, base[it] ?: 0) }
        }
    }

    androidx.compose.material3.AlertDialog(
        onDismissRequest = onClose,
        title = { Text("Revisar recuentos") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    "El reloj contó ${session.totalShots} golpeos. Deja cada recuento " +
                        "en lo que de verdad pasó.",
                    style = MaterialTheme.typography.bodySmall,
                )
                tipos.forEach { tipo ->
                    Row(
                        Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(tipo.label, style = MaterialTheme.typography.bodyMedium)
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            androidx.compose.material3.TextButton(onClick = {
                                counts[tipo.wireName] =
                                    ((counts[tipo.wireName] ?: 0) - 1).coerceAtLeast(0)
                            }) { Text("−") }
                            Text(
                                "${counts[tipo.wireName] ?: 0}",
                                style = MaterialTheme.typography.titleMedium,
                            )
                            androidx.compose.material3.TextButton(onClick = {
                                counts[tipo.wireName] = (counts[tipo.wireName] ?: 0) + 1
                            }) { Text("+") }
                        }
                    }
                }
            }
        },
        confirmButton = {
            androidx.compose.material3.TextButton(onClick = {
                // Solo viajan los tipos que difieren del reloj: la revisión es la
                // lista de correcciones, no una copia de todos los recuentos.
                val detectados = session.shotsByType.mapKeys { it.key.wireName }
                onSave(counts.filter { (wire, valor) -> valor != (detectados[wire] ?: 0) })
            }) { Text("Guardar") }
        },
        dismissButton = {
            androidx.compose.material3.TextButton(onClick = onClose) { Text("Cancelar") }
        },
    )
}

@Composable
private fun HeadlineStats(session: PadelSession) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text("${session.totalShots}", style = MaterialTheme.typography.displaySmall)
            Text("golpeos en ${formatDuration(session.durationSeconds)}",
                style = MaterialTheme.typography.bodyMedium)
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 12.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Stat("Ritmo", "%.1f/min".format(session.shotsPerMinute))
                Stat("Media pala", "%.0f km/h".format(session.intensity.meanRacketSpeedKmh))
                Stat("Máx pala", "%.0f km/h".format(session.intensity.maxRacketSpeedKmh))
            }
            if (!session.profile.watchOnRacketArm) {
                Text(
                    text = "El reloj no estaba en el brazo de la pala: el conteo es orientativo.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.padding(top = 12.dp),
                )
            }
        }
    }
}

@Composable
private fun LevelCard(level: SessionLevel) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text("Nivel técnico", style = MaterialTheme.typography.titleMedium)
            Text(
                text = "%.1f".format(level.rounded),
                style = MaterialTheme.typography.displaySmall,
                color = MaterialTheme.colorScheme.primary,
            )
            Text("de 7 · sobre ${level.gradedShots} golpeos", style = MaterialTheme.typography.bodySmall)

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 12.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Stat("Regularidad", "${(level.consistency * 100).toInt()}%")
                Stat("Repertorio", "${(level.repertoire * 100).toInt()}%")
            }

            // El desglose por golpe es lo accionable: el número global dice poco, saber
            // que el revés va dos puntos por debajo de la derecha dice qué entrenar.
            level.byShotType.entries.sortedByDescending { it.value }.forEach { (type, value) ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 6.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text(type.label(), style = MaterialTheme.typography.bodyMedium)
                    Text("%.1f".format(value), style = MaterialTheme.typography.bodyMedium)
                }
            }

            if (!level.reliable) {
                Text(
                    text = "Pocos golpeos para una estimación firme: juega una sesión más larga.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.padding(top = 12.dp),
                )
            }
            Text(
                text = "Estimado a partir de la velocidad y la forma del swing. No mide " +
                    "colocación ni táctica, y está sin calibrar contra jugadores de nivel conocido.",
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.padding(top = 12.dp),
            )
        }
    }
}

@Composable
private fun ScoreCard(score: MatchScore) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text("Resultado", style = MaterialTheme.typography.titleMedium)
            Text(
                text = score.allSets.joinToString("   ") { "${it.us}-${it.them}" },
                style = MaterialTheme.typography.headlineSmall,
                modifier = Modifier.padding(top = 4.dp),
            )
            Text(
                text = when {
                    !score.isFinished -> "Partido sin terminar"
                    score.winner == Side.US -> "Ganado"
                    else -> "Perdido"
                },
                style = MaterialTheme.typography.bodyMedium,
                color = if (score.winner == Side.US) MaterialTheme.colorScheme.primary
                else MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                text = buildString {
                    append(score.rules.deuceFormat.label)
                    append(" · al mejor de ${score.rules.setsToWin * 2 - 1} sets")
                },
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 4.dp),
            )
        }
    }
}

@Composable
private fun Stat(label: String, value: String) {
    Column {
        Text(value, style = MaterialTheme.typography.titleMedium)
        Text(
            label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun ShotBreakdown(session: PadelSession) {
    val byType = session.shotsByType.entries.sortedByDescending { it.value }
    if (byType.isEmpty()) return
    val max = byType.first().value

    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text("Golpeos por tipo", style = MaterialTheme.typography.titleMedium)
            byType.forEach { (type, count) ->
                BarRow(
                    label = type.label(),
                    value = "$count",
                    fraction = count.toFloat() / max,
                    color = MaterialTheme.colorScheme.primary,
                )
            }
        }
    }
}

@Composable
private fun HealthCard(session: PadelSession) {
    // Rejilla por filas de tres y no una fila única: con siete métricas posibles una
    // Row se sale de la pantalla justo cuando la sesión trae todos los datos.
    val stats = buildList {
        session.health.heartRate?.let {
            add("FC media" to "${it.meanBpm} ppm")
            add("FC máx" to "${it.maxBpm} ppm")
            it.restingBpm?.let { resting -> add("FC reposo" to "$resting ppm") }
        }
        session.health.activeEnergyKcal?.let { add("Activas" to "%.0f kcal".format(it)) }
        session.health.totalEnergyKcal?.let { add("Totales" to "%.0f kcal".format(it)) }
        session.health.steps?.let { add("Pasos" to "$it") }
        session.health.distanceMeters?.let { add("Distancia" to "%.1f km".format(it / 1000f)) }
    }

    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text("Salud", style = MaterialTheme.typography.titleMedium)
            stats.chunked(3).forEach { fila ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 8.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    fila.forEach { (label, value) -> Stat(label, value) }
                    // Relleno para que una fila corta no reparta sus huecos raro.
                    repeat(3 - fila.size) { Spacer(modifier = Modifier.width(1.dp)) }
                }
            }

            val zones = session.health.zones.secondsPerZone
            if (zones.isNotEmpty()) {
                val maxSeconds = zones.values.max()
                Text(
                    "Zonas de frecuencia cardiaca",
                    style = MaterialTheme.typography.labelLarge,
                    modifier = Modifier.padding(top = 16.dp),
                )
                HeartRateZones.ZONE_KEYS.forEach { key ->
                    val seconds = zones[key] ?: return@forEach
                    BarRow(
                        label = zoneLabel(key),
                        value = formatDuration(seconds.toLong()),
                        fraction = seconds.toFloat() / maxSeconds,
                        color = MaterialTheme.colorScheme.tertiary,
                    )
                }
            }
        }
    }
}

@Composable
private fun BarRow(label: String, value: String, fraction: Float, color: androidx.compose.ui.graphics.Color) {
    Column(modifier = Modifier.padding(top = 10.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text(label, style = MaterialTheme.typography.bodyMedium)
            Text(value, style = MaterialTheme.typography.bodyMedium)
        }
        Box(
            modifier = Modifier
                .padding(top = 4.dp)
                .fillMaxWidth()
                .height(8.dp)
                .clip(RoundedCornerShape(4.dp))
                .background(MaterialTheme.colorScheme.surfaceVariant),
        ) {
            Box(
                modifier = Modifier
                    .fillMaxHeight()
                    // Un mínimo visible: una barra de 0 px no comunica "casi nada", comunica "nada".
                    .fillMaxWidth(fraction.coerceIn(0.02f, 1f))
                    .background(color),
            )
        }
    }
}

@Composable
private fun MatchLinkCard(session: PadelSession, onLinkMatch: (String, String?) -> Unit) {
    var matchId by remember(session.sessionId) { mutableStateOf(session.matchRef?.matchId.orEmpty()) }
    var leagueId by remember(session.sessionId) { mutableStateOf(session.matchRef?.leagueId.orEmpty()) }

    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text("Vincular con un partido", style = MaterialTheme.typography.titleMedium)
            Text(
                "Al vincularla, la liga puede asociar estas estadísticas al partido.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            OutlinedTextField(
                value = matchId,
                onValueChange = { matchId = it },
                label = { Text("ID del partido") },
                singleLine = true,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 12.dp),
            )
            OutlinedTextField(
                value = leagueId,
                onValueChange = { leagueId = it },
                label = { Text("ID de la liga (opcional)") },
                singleLine = true,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 8.dp),
            )
            Button(
                onClick = { onLinkMatch(matchId, leagueId.ifBlank { null }) },
                modifier = Modifier
                    .align(Alignment.End)
                    .padding(top = 8.dp),
            ) {
                Text("Guardar y volver a subir")
            }
        }
    }
}

@Composable
private fun SyncCard(session: PadelSession, onRetrySync: () -> Unit) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text("Sincronización", style = MaterialTheme.typography.titleMedium)
            Text(
                session.sync.state.label(),
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.padding(top = 4.dp),
            )
            session.sync.lastError?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.padding(top = 4.dp),
                )
            }
            if (session.sync.state != SyncState.SYNCED) {
                Button(onClick = onRetrySync, modifier = Modifier.padding(top = 12.dp)) {
                    Text("Reintentar ahora")
                }
            }
        }
    }
}

/**
 * Guarda la sesión como partido de la liga, con el mismo mapeo que iOS (LigaMapper en
 * el core, con tests): voleas unificadas, curva del reloj y objetivos medibles ya
 * marcados. El id es la fecha de inicio: repetir actualiza, no duplica.
 */
@Composable
private fun LigaSaveCard(session: PadelSession, playerAverageLevel: Float?) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val store = androidx.compose.runtime.remember {
        com.risingpadel.mobile.data.LigaStore(context)
    }
    var guardado by androidx.compose.runtime.remember {
        androidx.compose.runtime.mutableStateOf(
            store.load().matches.any { it.id == session.startedAtEpochMs }
        )
    }
    Button(
        onClick = {
            val state = store.load()
            val match = com.risingpadel.core.liga.LigaMapper.matchFrom(
                session, playerAverageLevel, state.objetivos
            )
            store.save(
                state.copy(matches = state.matches.filter { it.id != match.id } + match)
            )
            guardado = true
        },
        modifier = Modifier.fillMaxWidth(),
    ) {
        Text(if (guardado) "Partido guardado en la liga ✓" else "Guardar como partido de liga")
    }
}
