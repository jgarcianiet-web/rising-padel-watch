package com.risingpadel.wear.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.Chip
import androidx.wear.compose.material.ChipDefaults
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import com.risingpadel.core.model.ShotType
import com.risingpadel.core.training.PasoDeRutina
import com.risingpadel.core.training.ProgresoDeRutina
import com.risingpadel.core.training.Rutina

/**
 * Elegir rutina.
 *
 * Es lo que separa la app de un contador de golpes: un contador te dice al acabar que
 * diste 312 golpes; una rutina te dice **qué hacer ahora** y lleva la cuenta ella sola,
 * que es lo que hace falta con la pala en la mano.
 */
@Composable
fun RutinaChooser(
    rutinas: List<Rutina> = Rutina.DE_FABRICA,
    onPick: (Rutina) -> Unit,
    onBack: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 10.dp, vertical = 20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            text = "Rutinas",
            style = MaterialTheme.typography.title3,
            textAlign = TextAlign.Center,
        )
        rutinas.forEach { rutina ->
            Chip(
                onClick = { onPick(rutina) },
                label = { Text(rutina.nombre, style = MaterialTheme.typography.caption1) },
                secondaryLabel = {
                    Text(
                        "${rutina.pasos.size} ejercicios · ${rutina.golpesTotales} golpes",
                        style = MaterialTheme.typography.caption3,
                    )
                },
                colors = ChipDefaults.secondaryChipColors(),
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 4.dp),
            )
        }
        Chip(
            onClick = onBack,
            label = { Text("Atrás", style = MaterialTheme.typography.caption2) },
            colors = ChipDefaults.childChipColors(),
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 4.dp),
        )
    }
}

/**
 * El ejercicio que toca, en grande.
 *
 * Lo que se lee de un vistazo es cuántos golpes faltan, no cuántos llevas: es lo que
 * decide si sigues o paras, y a metro y medio de la muñeca no caben las dos cosas.
 */
@Composable
fun RutinaEnCursoPanel(
    progreso: ProgresoDeRutina,
    onSaltar: () -> Unit,
) {
    Text(
        text = "${progreso.restantes}",
        style = MaterialTheme.typography.display1,
    )
    Text(
        text = progreso.paso.type.label(),
        style = MaterialTheme.typography.caption1,
        color = MaterialTheme.colors.primary,
        textAlign = TextAlign.Center,
    )
    Text(
        text = "Ejercicio ${progreso.indice + 1} de ${progreso.totalPasos}",
        style = MaterialTheme.typography.caption3,
        color = MaterialTheme.colors.onSurfaceVariant,
        modifier = Modifier.padding(top = 2.dp),
    )
    // Los golpes de otro tipo no cuentan, y callárselo haría parecer que el reloj no
    // detecta: mejor decir que sí los vio y que no eran los que tocaban.
    if (progreso.fueraDeTipo > 0) {
        Text(
            text = "${progreso.fueraDeTipo} de otro golpe (no cuentan)",
            style = MaterialTheme.typography.caption3,
            color = MaterialTheme.colors.onSurfaceVariant,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth(),
        )
    }
    Chip(
        onClick = onSaltar,
        label = { Text("Saltar ejercicio", style = MaterialTheme.typography.caption3) },
        colors = ChipDefaults.childChipColors(),
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 4.dp),
    )
}

/** La rutina terminada. Se queda hasta que el jugador cierra la sesión. */
@Composable
fun RutinaTerminadaPanel(onParar: () -> Unit) {
    Text(
        text = "Rutina completa",
        style = MaterialTheme.typography.title3,
        textAlign = TextAlign.Center,
    )
    Text(
        text = "Puedes seguir jugando o parar para guardar la sesión",
        style = MaterialTheme.typography.caption3,
        textAlign = TextAlign.Center,
        color = MaterialTheme.colors.onSurfaceVariant,
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 4.dp),
    )
    Button(onClick = onParar, modifier = Modifier.padding(top = 8.dp)) {
        Text("Parar")
    }
}

@Preview(device = "id:wearos_small_round", showSystemUi = true)
@Composable
private fun RutinaChooserPreview() {
    MaterialTheme {
        RutinaChooser(onPick = {}, onBack = {})
    }
}

@Preview(device = "id:wearos_small_round", showSystemUi = true)
@Composable
private fun RutinaEnCursoPreview() {
    MaterialTheme {
        Column(
            modifier = Modifier.fillMaxSize(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            RutinaEnCursoPanel(
                progreso = ProgresoDeRutina(
                    paso = PasoDeRutina(ShotType.BANDEJA, 25),
                    indice = 1,
                    totalPasos = 3,
                    hechos = 11,
                    fueraDeTipo = 3,
                ),
                onSaltar = {},
            )
        }
    }
}
