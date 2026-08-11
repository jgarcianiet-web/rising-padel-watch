package com.risingpadel.mobile.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.risingpadel.core.analytics.CalendarioDeActividad
import com.risingpadel.core.analytics.DiaDeActividad
import com.risingpadel.core.model.PadelSession

/**
 * Las últimas doce semanas de juego, un cuadro por día.
 *
 * El histórico es una lista, y una lista contesta "¿qué hice el martes?" pero no "¿estoy
 * jugando menos que el mes pasado?". Esa segunda es la que hace que alguien vuelva a abrir
 * la app, y se contesta de un vistazo o no se contesta: un hueco de dos semanas se ve, no
 * se lee.
 */
@Composable
fun CalendarioCard(sesiones: List<PadelSession>) {
    val calendario = remember(sesiones) {
        CalendarioDeActividad.de(
            CalendarioDeActividad.porDia(sesiones),
            hastaISO = CalendarioDeActividad.hoyISO(),
        )
    }
    if (calendario == null || !calendario.hayDatos) return

    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text("Cuándo juegas", style = MaterialTheme.typography.titleMedium)

            // Las semanas son columnas y los días filas, como el calendario de
            // contribuciones que todo el mundo ya sabe leer: el tiempo corre de
            // izquierda a derecha.
            Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    // Tres iniciales y no siete: al tamaño que caben, las siete no se
                    // leen y solo ensucian.
                    listOf("L", "", "X", "", "V", "", "D").forEach { inicial ->
                        Text(
                            inicial,
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.size(width = 10.dp, height = 13.dp),
                        )
                    }
                }
                calendario.semanas.forEach { semana ->
                    Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        semana.forEach { dia ->
                            Spacer(
                                modifier = Modifier
                                    .size(13.dp)
                                    .background(
                                        colorDelDia(dia, calendario.maxGolpes),
                                        RoundedCornerShape(3.dp),
                                    )
                            )
                        }
                    }
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                dato("Días jugados", "${calendario.diasJugados}")
                dato("Por semana", "%.1f".format(calendario.diasPorSemana))
                dato("Racha", "${calendario.rachaActual}")
                dato("Mejor racha", "${calendario.mejorRacha}")
            }

            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Text(
                    "Menos",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                listOf(0f, 0.35f, 0.6f, 0.8f, 1f).forEach { nivel ->
                    Spacer(
                        modifier = Modifier
                            .size(9.dp)
                            .background(
                                if (nivel == 0f) sinJugar()
                                else MaterialTheme.colorScheme.primary.copy(alpha = nivel),
                                RoundedCornerShape(2.dp),
                            )
                    )
                }
                Text(
                    "Más · 12 semanas",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

/**
 * El color va por golpes y no por "jugó / no jugó": media hora de peloteo y un partido de
 * dos horas no son lo mismo, y un cuadro plano lo diría.
 */
@Composable
private fun colorDelDia(dia: DiaDeActividad, maximo: Int): Color {
    if (!dia.jugado) return sinJugar()
    if (maximo <= 0) return MaterialTheme.colorScheme.primary
    val intensidad = (dia.golpes.toFloat() / maximo).coerceIn(0f, 1f)
    return MaterialTheme.colorScheme.primary.copy(alpha = 0.35f + 0.65f * intensidad)
}

@Composable
private fun sinJugar(): Color = MaterialTheme.colorScheme.surfaceVariant

@Composable
private fun dato(etiqueta: String, valor: String) {
    Column {
        Text(
            etiqueta.uppercase(),
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(valor, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
    }
}
