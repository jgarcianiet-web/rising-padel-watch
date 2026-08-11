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
import androidx.compose.material3.LinearProgressIndicator
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
import com.risingpadel.core.analytics.CalendarioDeActividad
import com.risingpadel.core.liga.LigaMatch
import com.risingpadel.core.liga.LigaMetrics
import com.risingpadel.core.liga.LigaTemporada
import com.risingpadel.core.liga.RitmoDeTemporada
import com.risingpadel.mobile.data.LigaStore
import com.risingpadel.mobile.ui.ResultadoDePartido

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
    var editandoFechas by remember { mutableStateOf(false) }
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

    if (editandoFechas && actual != null) {
        // Texto y no un selector de calendario: son dos campos que se tocan una vez por
        // temporada, y `yyyy-mm-dd` es el formato que ya guarda la liga.
        var inicio by remember { mutableStateOf(actual.fechaInicio) }
        var fin by remember { mutableStateOf(actual.fechaFinPrevista) }
        AlertDialog(
            onDismissRequest = { editandoFechas = false },
            title = { Text("Fechas de ${actual.nombre}") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = inicio,
                        onValueChange = { inicio = it },
                        label = { Text("Empieza (aaaa-mm-dd)") },
                        singleLine = true,
                    )
                    OutlinedTextField(
                        value = fin,
                        onValueChange = { fin = it },
                        label = { Text("Acaba (aaaa-mm-dd, opcional)") },
                        singleLine = true,
                    )
                    Text(
                        "La fecha de fin es la que piensas cerrarla: sirve para la cuenta " +
                            "atrás y para saber si vas en hora, y no cierra la temporada " +
                            "por su cuenta. Los partidos posteriores siguen contando hasta " +
                            "que empieces la siguiente.",
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    state = store.setFechasDeTemporada(inicio.trim(), fin.trim())
                    editandoFechas = false
                    aviso = "Fechas guardadas"
                }) { Text("Guardar") }
            },
            dismissButton = {
                TextButton(onClick = { editandoFechas = false }) { Text("Cancelar") }
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
                    // Las fechas, que estaban guardadas y no se veían en ningún sitio.
                    // Un rango que no se enseña es un rango que nadie recuerda haber puesto.
                    actual?.let { temporada ->
                        Text(
                            rangoLargo(temporada),
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.SemiBold,
                        )
                        val ritmo = RitmoDeTemporada.de(
                            temporada, delPeriodo.size, CalendarioDeActividad.hoyISO()
                        )
                        if (ritmo != null) {
                            Text(cuentaAtras(ritmo), style = MaterialTheme.typography.bodySmall)
                            LinearProgressIndicator(
                                progress = { ritmo.fraccionDelTiempo },
                                modifier = Modifier.fillMaxWidth(),
                                color = MaterialTheme.colorScheme.outline,
                            )
                            Text(
                                veredicto(ritmo),
                                style = MaterialTheme.typography.bodySmall,
                                fontWeight = FontWeight.SemiBold,
                                color = when {
                                    ritmo.cumplida -> MaterialTheme.colorScheme.primary
                                    ritmo.terminada -> MaterialTheme.colorScheme.onSurfaceVariant
                                    ritmo.diferencia < 0 -> MaterialTheme.colorScheme.error
                                    else -> MaterialTheme.colorScheme.primary
                                },
                            )
                        } else if (temporada.fechaDeCierre.isEmpty()) {
                            Text(
                                "Sin fecha de fin: la temporada sigue abierta",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
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
                        if (actual != null) {
                            TextButton(onClick = { editandoFechas = true }) { Text("Fechas") }
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
                        if (previos.isNotEmpty()) filaTemporada("Antes", null, previos)
                        state.temporadas.forEach { temporada ->
                            filaTemporada(
                                temporada.nombre,
                                rangoCorto(temporada),
                                matches.filter { temporada.contiene(it) },
                            )
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
                ResultadoDePartido.letra(match.resultado),
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Black,
                color = when (ResultadoDePartido.letra(match.resultado)) {
                    "V" -> MaterialTheme.colorScheme.primary
                    "E", "—" -> MaterialTheme.colorScheme.outline
                    else -> MaterialTheme.colorScheme.error
                },
            )
        }
    }
}

@Composable
private fun filaTemporada(nombre: String, rango: String?, ms: List<LigaMatch>) {
    val bien = if (ms.isEmpty()) null else ms.count { it.bienJugado } * 100 / ms.size
    val nivel = ms.mapNotNull(LigaMetrics::nivelDeSesion).takeIf { it.isNotEmpty() }?.average()
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        // El nombre suele ser "Temporada 2" y no dice qué días abarca. Con varias
        // encima, la fecha es lo que de verdad las distingue.
        Column {
            Text(nombre, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Bold)
            rango?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
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

// MARK: Fechas de la temporada

private val MESES_CORTOS = listOf(
    "ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic",
)

/** "12 mar 2026", o la cadena tal cual si no es una fecha. */
private fun fechaConAnno(iso: String): String {
    val trozos = iso.split("-")
    if (trozos.size != 3) return iso
    val mes = trozos[1].toIntOrNull() ?: return iso
    val dia = trozos[2].toIntOrNull() ?: return iso
    if (mes !in 1..12) return iso
    return "$dia ${MESES_CORTOS[mes - 1]} ${trozos[0]}"
}

private fun fechaCorta(iso: String): String {
    val trozos = iso.split("-")
    if (trozos.size != 3) return iso
    val mes = trozos[1].toIntOrNull() ?: return iso
    val dia = trozos[2].toIntOrNull() ?: return iso
    if (mes !in 1..12) return iso
    return "$dia ${MESES_CORTOS[mes - 1]}"
}

private fun rangoLargo(temporada: LigaTemporada): String {
    val desde = fechaConAnno(temporada.fechaInicio)
    val cierre = temporada.fechaDeCierre
    if (cierre.isEmpty()) return "Desde el $desde"
    val hasta = fechaConAnno(cierre)
    // Se dice si la fecha es un plan o un hecho: "hasta el 30 de junio" y "acabó el 30
    // de junio" son cosas distintas y el rango solo no las distingue.
    return if (temporada.fechaFin.isEmpty()) "Del $desde al $hasta (previsto)"
    else "Del $desde al $hasta"
}

private fun rangoCorto(temporada: LigaTemporada): String {
    val desde = fechaCorta(temporada.fechaInicio)
    val cierre = temporada.fechaDeCierre
    return if (cierre.isEmpty()) "desde $desde" else "$desde – ${fechaCorta(cierre)}"
}

private fun cuentaAtras(ritmo: RitmoDeTemporada): String = when {
    ritmo.terminada -> "Temporada terminada"
    ritmo.diasTranscurridos == 0 -> "Todavía no ha empezado"
    ritmo.diasRestantes / 7 >= 3 ->
        "Quedan ${ritmo.diasRestantes} días (${ritmo.diasRestantes / 7} semanas)"
    else -> "Quedan ${ritmo.diasRestantes} días"
}

/** El número accionable: no "vas al 40%", sino "uno cada quince días". */
private fun veredicto(ritmo: RitmoDeTemporada): String {
    if (ritmo.cumplida) return "Meta cumplida 🎉"
    if (ritmo.terminada) return "Se acabó con ${ritmo.partidosQueFaltan} partido(s) por jugar"
    val cada = ritmo.cadaCuantosDias ?: return ""
    val texto = if (cada >= 1) "toca uno cada ${cada.toInt()} días" else "toca más de uno al día"
    return when {
        ritmo.diferencia > 0 -> "Vas ${ritmo.diferencia} por delante del calendario · $texto"
        ritmo.diferencia < 0 -> "Vas ${-ritmo.diferencia} por detrás del calendario · $texto"
        else -> "Vas justo en hora · $texto"
    }
}
