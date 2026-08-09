package com.risingpadel.mobile.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.risingpadel.core.analytics.GastoDeBateria
import com.risingpadel.core.analytics.InformeDePrecision
import com.risingpadel.core.analytics.PrecisionDeGolpe
import com.risingpadel.mobile.ui.label
import kotlin.math.roundToInt

/**
 * Cuánto acierta el reloj, golpe por golpe.
 *
 * Es la pregunta de la que depende todo lo demás: el nivel, la liga, las gráficas y la
 * comunidad se apoyan en que el reloj acierte al decir qué golpe fue. El número existía
 * ya, pero repartido —dentro de cada sesión revisada y dentro de cada tanda— y suelto no
 * cambia ninguna decisión. Junto dice qué golpe está roto y qué tanda toca grabar.
 *
 * Vive detrás del modo desarrollador: a un cliente normal, un "tu reloj acierta el 58%"
 * no le sirve para nada y le quita la confianza en lo que sí funciona.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PrecisionScreen(
    informe: InformeDePrecision,
    bateria: GastoDeBateria?,
    onBack: () -> Unit,
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Precisión del reloj") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Atrás")
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
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            if (!informe.hayDatos) {
                Card(modifier = Modifier.fillMaxWidth()) {
                    Text(
                        text = "Todavía no hay con qué medir. Graba tandas etiquetadas desde " +
                            "Ajustes → Datos de entrenamiento, o revisa una sesión al acabarla.",
                        style = MaterialTheme.typography.bodyMedium,
                        modifier = Modifier.padding(16.dp),
                    )
                }
                return@Column
            }

            TitularCard(informe)
            informe.golpes.forEach { GolpeCard(it) }
            bateria?.let { BateriaCard(it) }
            MetodoCard(informe)
        }
    }
}

@Composable
private fun TitularCard(informe: InformeDePrecision) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            val acierto = informe.aciertoGlobal
            Text(
                text = acierto?.let { "${InformeDePrecision.porcentaje(it)}%" } ?: "—",
                style = MaterialTheme.typography.displayMedium,
                color = MaterialTheme.colorScheme.primary,
            )
            Text(
                text = "de acierto sobre ${informe.golpesEnTandas} golpes etiquetados",
                style = MaterialTheme.typography.bodyMedium,
            )
            informe.sinClasificar?.takeIf { it > 0 }?.let {
                // Rendirse no es lo mismo que equivocarse: un "sin clasificar" no ensucia
                // las estadísticas del jugador, solo le quita un golpe.
                Text(
                    text = "${InformeDePrecision.porcentaje(it)}% se quedaron sin clasificar",
                    style = MaterialTheme.typography.bodySmall,
                )
            }
            informe.peorGolpe?.let { peor ->
                Text(
                    text = "El que peor va: ${peor.type.label()}" +
                        (peor.seConfundeCon?.let { " (se confunde con ${it.label().lowercase()})" } ?: ""),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                )
            }
            if (informe.sesionesRevisadas > 0) {
                Text(
                    text = "${informe.sesionesRevisadas} sesión(es) revisadas por ti",
                    style = MaterialTheme.typography.bodySmall,
                )
            }
            val pendientes = informe.golpesSinTandas
            if (pendientes.isNotEmpty()) {
                Text(
                    text = "Faltan tandas de: " +
                        pendientes.joinToString { it.label().lowercase() },
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        }
    }
}

@Composable
private fun GolpeCard(golpe: PrecisionDeGolpe) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = golpe.type.label(),
                    style = MaterialTheme.typography.titleSmall,
                    modifier = Modifier.weight(1f),
                )
                Text(
                    text = golpe.aciertoEnTandas
                        ?.let { "${InformeDePrecision.porcentaje(it)}%" }
                        ?: "sin tandas",
                    style = MaterialTheme.typography.titleSmall,
                    color = when {
                        golpe.aciertoEnTandas == null -> MaterialTheme.colorScheme.onSurfaceVariant
                        golpe.aciertoEnTandas!! >= 0.8f -> MaterialTheme.colorScheme.primary
                        else -> MaterialTheme.colorScheme.error
                    },
                )
            }
            golpe.aciertoEnTandas?.let {
                LinearProgressIndicator(
                    progress = { it },
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            Text(
                text = "${golpe.acertadosEnTandas} de ${golpe.enTandas} golpes etiquetados",
                style = MaterialTheme.typography.bodySmall,
            )
            if (golpe.faltanTandas) {
                Text(
                    text = "Con menos de ${PrecisionDeGolpe.MIN_TANDAS_PARA_JUZGAR} golpes el " +
                        "porcentaje es una anécdota: graba una tanda de este golpe.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            golpe.seConfundeCon?.let {
                Text(
                    text = "Lo confunde ${golpe.vecesConfundido} veces con ${it.label().lowercase()}",
                    style = MaterialTheme.typography.bodySmall,
                )
            }
            golpe.desvioEnPartidos?.let { desvio ->
                val signo = if (desvio >= 0) "de más" else "de menos"
                Text(
                    text = "En partido cuenta un ${InformeDePrecision.porcentaje(desvio)}% $signo " +
                        "(${golpe.contadosEnPartidos} contra ${golpe.realesEnPartidos} reales)",
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        }
    }
}

/**
 * Lo que cuesta medir, en batería.
 *
 * Es la primera pregunta que hace cualquiera antes de fiarse de un reloj deportivo, y no
 * se puede contestar leyendo código: depende del modelo, del frío y de si el pulso estaba
 * encendido. Se mide en el reloj de quien pregunta.
 */
@Composable
private fun BateriaCard(bateria: GastoDeBateria) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text("Batería", style = MaterialTheme.typography.titleSmall)
            Text(
                text = "${bateria.porHora.roundToInt()}% por hora",
                style = MaterialTheme.typography.headlineSmall,
                color = MaterialTheme.colorScheme.primary,
            )
            Text(
                text = "Unas ${bateria.horasDeAutonomia.roundToInt()} horas de reloj lleno",
                style = MaterialTheme.typography.bodyMedium,
            )
            Text(
                text = "Medido en tu reloj sobre ${bateria.sesiones} sesiones " +
                    "(${bateria.horas.roundToInt()} h de juego)",
                style = MaterialTheme.typography.bodySmall,
            )
        }
    }
}

@Composable
private fun MetodoCard(informe: InformeDePrecision) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Text("De dónde sale", style = MaterialTheme.typography.titleSmall)
            Text(
                text = "Las tandas son verdad-terreno: alguien dijo «esto van a ser treinta " +
                    "bandejas» antes de pegar, así que se sabe golpe a golpe si acertó. Las " +
                    "revisiones de partido son recuentos: dicen cuántos de más o de menos " +
                    "contó el reloj, no cuál falló. No se mezclan en un solo número porque " +
                    "saldría más gordo y más falso.",
                style = MaterialTheme.typography.bodySmall,
            )
            if (informe.sesionesRevisadas == 0) {
                Text(
                    text = "Todavía no has revisado ninguna sesión: esa mitad está vacía.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}
