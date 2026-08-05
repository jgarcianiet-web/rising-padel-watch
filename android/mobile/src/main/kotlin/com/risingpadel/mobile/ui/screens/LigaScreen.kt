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
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
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
fun LigaScreen() {
    val context = LocalContext.current
    val store = remember { LigaStore(context) }
    var state by remember { mutableStateOf(store.load()) }
    var aviso by remember { mutableStateOf<String?>(null) }

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

    val matches = state.matches.sortedByDescending { it.fecha }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Card {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Temporada", style = MaterialTheme.typography.titleMedium)
                    Row(horizontalArrangement = Arrangement.SpaceBetween, modifier = Modifier.fillMaxWidth()) {
                        stat("Partidos", "${matches.size}")
                        stat("Victorias", if (matches.isEmpty()) "–" else "${LigaMetrics.pctVictorias(matches)}%")
                        stat("Racha", "${LigaMetrics.racha(matches)}")
                        stat(
                            "Nivel",
                            matches.mapNotNull(LigaMetrics::nivelDeSesion)
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
            MatchRow(match)
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

@Composable
private fun MatchRow(match: LigaMatch) {
    Card {
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
private fun stat(label: String, value: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
        Text(label, style = MaterialTheme.typography.labelSmall)
    }
}
