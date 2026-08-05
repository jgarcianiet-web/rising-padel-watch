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
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.risingpadel.core.liga.LigaMatch
import com.risingpadel.core.liga.LigaMetrics

/**
 * La ficha de un partido de la liga en Android: el espejo de la de iOS, con los mismos
 * bloques — partido, niveles, golpes, salud, objetivos y nota. Las gráficas de la curva
 * llegarán al conectar los charts de sesión; el resumen inicio → fin ya cuenta la
 * historia.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LigaMatchDetailScreen(match: LigaMatch, objetivos: List<String>, onBack: () -> Unit) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("${match.fecha} · ${resultadoLargo(match.resultado)}") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Volver")
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
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            bloque("El partido") {
                if (match.sets.isNotEmpty()) {
                    Text(
                        match.sets,
                        style = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.Black,
                        color = MaterialTheme.colorScheme.primary,
                    )
                }
                linea("Tipo", match.tipo)
                linea("Posición", if (match.posicion == "reves") "revés" else "derecha")
                if (match.club.isNotEmpty()) linea("Club", match.club)
                if (match.companero.isNotEmpty()) linea("Compañero", match.companero)
            }

            if (match.nivel != null || match.nivelBand != null || match.totalGolpes != null) {
                bloque("Niveles de la sesión") {
                    match.nivel?.let { linea("Playtomic tras el partido", "%.2f".format(it)) }
                    match.nivelBand?.let { linea("Nivel de la sesión (reloj)", "%.1f/7".format(it)) }
                    if (match.bandInicio != null || match.bandFin != null) {
                        val inicio = match.bandInicio?.let { "%.1f".format(it) } ?: "?"
                        val fin = match.bandFin?.let { "%.1f".format(it) } ?: "?"
                        val media = match.bandMediaJugador?.let { " (media %.1f)".format(it) } ?: ""
                        linea("Curva de la sesión", "$inicio → $fin$media")
                    }
                    match.totalGolpes?.let { linea("Total de golpeos", "$it") }
                }
            }

            if (!match.golpesSesion.isNullOrEmpty() || !match.golpesVolumen.isNullOrEmpty() ||
                match.mejorGolpe != null || match.peorGolpe != null
            ) {
                bloque("Golpes") {
                    match.mejorGolpe?.let {
                        linea("👍 Mejor", it + (match.mejorPunt?.let { p -> " · %.0f/7".format(p) } ?: ""))
                    }
                    match.peorGolpe?.let {
                        linea("👎 Peor", it + (match.peorPunt?.let { p -> " · %.0f/7".format(p) } ?: ""))
                    }
                    match.golpesSesion?.forEach { golpe ->
                        linea(golpe.nombre, "%.1f".format(golpe.nota))
                    }
                    match.golpesVolumen?.forEach { golpe ->
                        linea(golpe.nombre, "×${golpe.cantidad}")
                    }
                }
            }

            match.salud?.let { salud ->
                bloque("Salud (reloj)") {
                    linea("Duración", "${salud.duracionMin} min")
                    salud.pulsoMedio?.let { linea("Pulso medio", "$it ppm") }
                    salud.pulsoMax?.let { linea("Pulso máximo", "$it ppm") }
                    salud.calorias?.let { linea("Calorías", "$it kcal") }
                }
            }

            bloque("Objetivos · ${match.objetivos.count { it }}/${match.objetivos.size}") {
                match.objetivos.forEachIndexed { index, cumplido ->
                    linea(
                        objetivos.getOrElse(index) { "—" },
                        if (cumplido) "✓" else "✗",
                    )
                }
                if (match.nota.isNotEmpty()) {
                    Text(
                        "“${match.nota}”",
                        style = MaterialTheme.typography.bodyMedium,
                        modifier = Modifier.padding(top = 6.dp),
                    )
                }
            }

            LigaMetrics.nivelDeSesion(match)?.let {
                Text(
                    "Nivel de sesión %.1f — medido por el reloj".format(it),
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        }
    }
}

@Composable
private fun bloque(titulo: String, contenido: @Composable () -> Unit) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Text(titulo, style = MaterialTheme.typography.titleMedium)
            contenido()
        }
    }
}

@Composable
private fun linea(etiqueta: String, valor: String) {
    Row(
        Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(etiqueta, style = MaterialTheme.typography.bodyMedium)
        Text(valor, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Bold)
    }
}

private fun resultadoLargo(resultado: String) = when (resultado) {
    "victoria" -> "Victoria"
    "empate" -> "Empate"
    else -> "Derrota"
}
