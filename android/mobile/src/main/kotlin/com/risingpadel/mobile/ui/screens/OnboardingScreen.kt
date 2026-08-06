package com.risingpadel.mobile.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.risingpadel.mobile.data.ComunidadApi
import com.risingpadel.mobile.data.LigaStore
import kotlinx.coroutines.launch

/**
 * El primer arranque, en tres pasos: qué hace la app, la cuenta de la comunidad y el
 * primer objetivo. El mismo flujo que iOS. Solo aparece una vez; quien ya tiene
 * sesiones o cuenta no lo ve nunca.
 */
@Composable
fun OnboardingScreen(onDone: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var paso by remember { mutableStateOf(0) }
    var alias by remember { mutableStateOf("") }
    var creando by remember { mutableStateOf(false) }
    var aviso by remember { mutableStateOf<String?>(null) }
    var objetivo by remember { mutableStateOf("") }

    // Objetivos de arranque que el reloj puede medir solo — la promesa diferencial.
    val sugerencias = listOf("Hacer 15 bandejas", "Mínimo 10 víboras", "Hacer 5 smashes")

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.height(24.dp))
        when (paso) {
            0 -> {
                Text("Tu reloj cuenta el partido",
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.Black)
                punto("Golpes por tipo",
                    "Bandejas, víboras, smashes, voleas… el reloj los detecta y los " +
                        "cuenta mientras juegas.")
                punto("Marcador desde la muñeca",
                    "Lleva el partido tocando la pantalla. Con punto de oro si quieres.")
                punto("Tu nivel, medido",
                    "Cada sesión sale con un nivel del 1 al 7 y sus gráficas.")
                punto("Tu salud, tuya",
                    "El pulso solo se comparte si tú lo activas en Ajustes. Sin " +
                        "permiso, no sale del reloj.")
                Button(onClick = { paso = 1 }, modifier = Modifier.fillMaxWidth()) {
                    Text("Seguir")
                }
            }

            1 -> {
                Text("Únete a la comunidad",
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.Black)
                Text(
                    "Con un alias tienes cuenta: tus amigos te siguen y pueden ver tu " +
                        "partido en vivo. También enciende el ranking, los retos y el muro.",
                    style = MaterialTheme.typography.bodyMedium,
                )
                OutlinedTextField(
                    value = alias,
                    onValueChange = { alias = it },
                    label = { Text("Tu alias (ej: jesus-g)") },
                    modifier = Modifier.fillMaxWidth(),
                )
                aviso?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                Button(
                    onClick = {
                        creando = true
                        scope.launch {
                            val api = ComunidadApi(context) { ComunidadApi.SERVIDOR_OFICIAL }
                            val error = api.registrar(alias)
                            creando = false
                            if (error == null) paso = 2 else aviso = error
                        }
                    },
                    enabled = alias.trim().length >= 2 && !creando,
                    modifier = Modifier.fillMaxWidth(),
                ) { Text(if (creando) "Creando…" else "Crear mi cuenta") }
                TextButton(onClick = { paso = 2 }) { Text("Ahora no") }
            }

            else -> {
                Text("Tu primer objetivo",
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.Black)
                Text(
                    "Elige uno que el reloj pueda medir: al acabar cada partido se " +
                        "marca solo si lo cumpliste.",
                    style = MaterialTheme.typography.bodyMedium,
                )
                sugerencias.forEach { texto ->
                    Card(Modifier.fillMaxWidth()) {
                        Row(
                            Modifier.fillMaxWidth().padding(horizontal = 8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            RadioButton(
                                selected = objetivo == texto,
                                onClick = { objetivo = texto },
                            )
                            Text(texto, style = MaterialTheme.typography.bodyMedium)
                        }
                    }
                }
                OutlinedTextField(
                    value = objetivo,
                    onValueChange = { objetivo = it },
                    label = { Text("O escribe el tuyo…") },
                    modifier = Modifier.fillMaxWidth(),
                )
                Button(
                    onClick = {
                        val elegido = objetivo.trim()
                        if (elegido.isNotEmpty()) {
                            // El objetivo elegido entra el primero; el resto de la
                            // terna clásica se queda.
                            val store = LigaStore(context)
                            val state = store.load()
                            val base = state.objetivos.ifEmpty {
                                listOf(
                                    elegido,
                                    "Menos de 5 errores no forzados",
                                    "Actitud: no protestar ningún punto",
                                )
                            }
                            store.save(state.copy(
                                objetivos = listOf(elegido) + base.drop(1)
                            ))
                        }
                        onDone()
                    },
                    modifier = Modifier.fillMaxWidth(),
                ) { Text("Empezar a jugar") }
            }
        }
    }
}

@Composable
private fun punto(titulo: String, detalle: String) {
    Column(Modifier.fillMaxWidth()) {
        Text(titulo, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
        Text(detalle, style = MaterialTheme.typography.bodySmall)
    }
}
