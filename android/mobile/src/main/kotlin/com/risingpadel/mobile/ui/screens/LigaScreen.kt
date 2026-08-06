package com.risingpadel.mobile.ui.screens

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.risingpadel.core.liga.LigaMatch
import com.risingpadel.core.liga.LigaMetrics
import com.risingpadel.mobile.data.LigaStore

/**
 * La Liga Personal en Android: primer tramo de paridad con iOS.
 *
 * Resumen de temporada, historial de partidos e importar/exportar la copia de
 * seguridad — el puente que hace que el historial del iPhone o de la app Expo viva
 * aquí sin transformación. El alta manual y la ficha completa vienen después; el
 * dominio y las métricas ya son los del core, con tests.
 */
@Composable
fun LigaScreen(onOpenMatch: (Long) -> Unit = {}) {
    val context = LocalContext.current
    val store = remember { LigaStore(context) }
    var state by remember { mutableStateOf(store.load()) }
    var aviso by remember { mutableStateOf<String?>(null) }
    var pidiendoTemporada by remember { mutableStateOf(false) }
    var metaPartidos by remember { mutableStateOf("") }

    val importar = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri: Uri? ->
        uri ?: return@rememberLauncherForActivityResult
        val texto = context.contentResolver.openInputStream(uri)
            ?.bufferedReader()?.use { it.readText() }
        val importado = texto?.let(store::import)
        aviso = if (importado != null) {
            state = importado
            "Liga importada: ${importado.matches.size} partidos"
        } else {
            "Ese fichero no es una copia de la liga"
        }
    }

    val exportar = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("application/json")
    ) { uri: Uri? ->
        uri ?: return@rememberLauncherForActivityResult
        context.contentResolver.openOutputStream(uri)
            ?.bufferedWriter()?.use { it.write(store.export()) }
        aviso = "Copia exportada"
    }

    // Con temporada en curso, el resumen es de la temporada; la lista de abajo sigue
    // enseñando todo el historial — la misma semántica que iOS.
    val actual = state.temporadas.lastOrNull { it.enCurso }
    val matches = state.matches.sortedByDescending { it.fecha }
    val delPeriodo = if (actual != null) matches.filter { actual.contiene(it) } else matches

    if (pidiendoTemporada) {
        // La misma semántica que iOS: la actual se cierra en la víspera y la nueva
        // empieza hoy, con su meta de partidos opcional.
        AlertDialog(
            onDismissRequest = { pidiendoTemporada = false },
            title = { Text(if (actual == null) "Empezar la primera temporada" else "Empezar la siguiente") },
            text = {
                OutlinedTextField(
                    value = metaPartidos,
                    onValueChange = { metaPartidos = it.filter(Char::isDigit) },
                    label = { Text("Meta de partidos (opcional)") },
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    state = store.startTemporada(metaPartidos.toIntOrNull())
                    pidiendoTemporada = false
                    aviso = "${state.temporadas.last().nombre} en marcha"
                }) { Text("Empezar") }
            },
            dismissButton = {
                TextButton(onClick = { pidiendoTemporada = false }) { Text("Cancelar") }
            },
        )
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Card {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(actual?.nombre ?: "Temporada", style = MaterialTheme.typography.titleMedium)
                    Row(horizontalArrangement = Arrangement.SpaceBetween, modifier = Modifier.fillMaxWidth()) {
                        stat(
                            "Partidos",
                            actual?.objetivoPartidos?.let { "${delPeriodo.size}/$it" }
                                ?: "${delPeriodo.size}",
                        )
                        stat("Victorias", if (delPeriodo.isEmpty()) "–" else "${LigaMetrics.pctVictorias(delPeriodo)}%")
                        stat("Racha", "${LigaMetrics.racha(delPeriodo)}")
                        stat(
                            "Nivel",
                            delPeriodo.mapNotNull(LigaMetrics::nivelDeSesion)
                                .takeIf { it.isNotEmpty() }
                                ?.let { String.format("%.1f", it.average()) } ?: "–",
                        )
                    }
                    Row {
                        TextButton(onClick = { importar.launch(arrayOf("application/json", "text/plain")) }) {
                            Text("Importar copia")
                        }
                        TextButton(onClick = { exportar.launch("liga-padel-backup.json") }) {
                            Text("Exportar copia")
                        }
                        TextButton(onClick = { pidiendoTemporada = true }) {
                            Text(if (actual == null) "Empezar temporada" else "Nueva temporada")
                        }
                    }
                }
            }
        }

        // El cara a cara: contra quién juegas y cómo te va, y con qué pareja. Los
        // rivales llegan del backup o de la ficha editada en iOS; sin ellos, sin filas.
        val rivales = LigaMetrics.caraACara(delPeriodo)
        val parejas = LigaMetrics.conPareja(delPeriodo)
        if (rivales.isNotEmpty() || parejas.isNotEmpty()) {
            item {
                Card {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        if (rivales.isNotEmpty()) {
                            Text("Contra quién", style = MaterialTheme.typography.titleMedium)
                            rivales.take(6).forEach { fila -> filaCaraACara(fila) }
                        }
                        if (parejas.isNotEmpty()) {
                            Text(
                                "Con quién",
                                style = MaterialTheme.typography.titleMedium,
                                modifier = Modifier.padding(top = if (rivales.isEmpty()) 0.dp else 8.dp),
                            )
                            parejas.take(4).forEach { fila -> filaCaraACara(fila) }
                        }
                    }
                }
            }
        }

        // Todas las temporadas frente a frente, más el historial previo a la primera.
        if (state.temporadas.isNotEmpty()) {
            item {
                Card {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text("Temporada a temporada", style = MaterialTheme.typography.titleMedium)
                        val previos = matches.filter { m -> state.temporadas.none { it.contiene(m) } }
                        if (previos.isNotEmpty()) filaTemporada("Antes", previos)
                        state.temporadas.forEach { temporada ->
                            filaTemporada(temporada.nombre, matches.filter { temporada.contiene(it) })
                        }
                    }
                }
            }
        }
        aviso?.let { texto ->
            item {
                Text(texto, style = MaterialTheme.typography.bodySmall)
            }
        }
        items(matches, key = { it.id }) { match ->
            MatchRow(match, onClick = { onOpenMatch(match.id) })
        }
        if (matches.isEmpty()) {
            item {
                Text(
                    "La liga, todavía vacía: importa la copia de seguridad de tu " +
                        "iPhone o de la app Liga Pádel con el botón de arriba.",
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
        }
    }
}

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
private fun MatchRow(match: LigaMatch, onClick: () -> Unit) {
    Card(onClick = onClick) {
        Row(
            Modifier.fillMaxWidth().padding(14.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(match.fecha, style = MaterialTheme.typography.labelSmall)
                Text(
                    match.sets.ifEmpty { match.tipo },
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                )
                val detalle = buildList {
                    LigaMetrics.nivelDeSesion(match)?.let { add("nivel %.1f".format(it)) }
                    match.totalGolpes?.let { add("$it golpeos") }
                    if (match.club.isNotEmpty()) add(match.club)
                }.joinToString(" · ")
                if (detalle.isNotEmpty()) {
                    Text(detalle, style = MaterialTheme.typography.bodySmall)
                }
            }
            Text(
                when (match.resultado) {
                    "victoria" -> "V"
                    "empate" -> "E"
                    else -> "D"
                },
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Black,
                color = when (match.resultado) {
                    "victoria" -> MaterialTheme.colorScheme.primary
                    "empate" -> MaterialTheme.colorScheme.outline
                    else -> MaterialTheme.colorScheme.error
                },
            )
        }
    }
}

@Composable
private fun filaTemporada(nombre: String, ms: List<LigaMatch>) {
    val bien = if (ms.isEmpty()) null else ms.count { it.bienJugado } * 100 / ms.size
    val nivel = ms.mapNotNull(LigaMetrics::nivelDeSesion).takeIf { it.isNotEmpty() }?.average()
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(nombre, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Bold)
        Text(
            "${ms.size} PJ · " +
                (if (ms.isEmpty()) "–" else "${LigaMetrics.pctVictorias(ms)}% V") +
                (bien?.let { " · $it% bien" } ?: "") +
                (nivel?.let { " · %.1f".format(it) } ?: ""),
            style = MaterialTheme.typography.bodySmall,
        )
    }
}

/** Una fila del cara a cara: nombre, balance G-P y porcentaje de victorias. */
@Composable
private fun filaCaraACara(fila: com.risingpadel.core.liga.LigaCaraACara) {
    Row(
        Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(fila.nombre, style = MaterialTheme.typography.bodyMedium)
        Text(
            "${fila.victorias}-${fila.partidos - fila.victorias} · ${fila.pctVictorias}%",
            style = MaterialTheme.typography.bodyMedium,
            color = if (fila.pctVictorias >= 50) MaterialTheme.colorScheme.primary
            else MaterialTheme.colorScheme.error,
        )
    }
}

@Composable
private fun stat(label: String, value: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
        Text(label, style = MaterialTheme.typography.labelSmall)
    }
}
