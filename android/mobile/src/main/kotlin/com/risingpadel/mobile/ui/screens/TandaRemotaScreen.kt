package com.risingpadel.mobile.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.risingpadel.core.detection.DescartesDelDetector
import com.risingpadel.core.model.ShotType
import com.risingpadel.core.sync.AccionDeTanda
import com.risingpadel.core.sync.EstadoDeTanda
import com.risingpadel.mobile.sync.ConexionDelMando
import com.risingpadel.mobile.ui.label
import kotlinx.coroutines.delay

/**
 * El mando de tandas: se lleva el reloj otra persona y tú diriges desde el móvil.
 *
 * Nace de cómo se graban las tandas de verdad. El que apunta los datos casi nunca es el
 * que pega: le pones el reloj a alguien, te quedas fuera de la pista y le vas cantando
 * "treinta derechas", "ahora bandejas". Con los botones solo en la muñeca hay que parar el
 * ejercicio, acercarse, quitarle el reloj y cambiar el tipo entre tanda y tanda — y eso se
 * traduce en menos tandas grabadas, que es justo lo que peor le viene al detector.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TandaRemotaScreen(
    estado: EstadoDeTanda?,
    conexion: ConexionDelMando,
    aviso: String?,
    esperando: Boolean,
    alias: String,
    nivel: Int?,
    onAlias: (String) -> Unit,
    onNivel: (Int?) -> Unit,
    onOrden: (AccionDeTanda, ShotType?) -> Unit,
    onBack: () -> Unit,
) {
    // Los tipos que tiene sentido pedirle a alguien. UNKNOWN no se graba a propósito: no
    // es un golpe, es la ausencia de clasificación.
    val grabables = remember { ShotType.entries.filter { it != ShotType.UNKNOWN } }
    var etiqueta by remember { mutableStateOf(ShotType.FOREHAND) }

    // Un latido corto mientras la pantalla está delante: el contador de golpes es la única
    // forma de saber desde fuera que la tanda va bien. Se para al salir para no estar
    // despertando el reloj en balde.
    LaunchedEffect(Unit) {
        while (true) {
            onOrden(AccionDeTanda.ESTADO, null)
            delay(2_000)
        }
    }

    // Si alguien toca la pantalla del reloj y cambia el tipo, el móvil le sigue: manda lo
    // que hay en la muñeca, no lo que el móvil creía.
    LaunchedEffect(estado?.etiqueta, estado?.grabando) {
        val actual = estado ?: return@LaunchedEffect
        if (!actual.grabando) etiqueta = actual.etiqueta
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Mando de tandas") },
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
            ConexionBanner(conexion, esperando, estado != null)

            // Los controles están siempre, conteste el reloj o no: mirar el móvil apaga la
            // pantalla del reloj, así que "sin respuesta" es el caso normal y no puede
            // dejar al mando sin botones.
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    // Una orden que no hizo nada tiene que decir por qué: si no, el botón
                    // parece roto y lo siguiente es dejar de usar el mando.
                    aviso?.let {
                        Text(
                            text = it,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.error,
                        )
                    }

                    if (estado?.grabando == true) {
                        GrabandoContent(estado, onOrden)
                    } else {
                        Text(
                            text = "Qué le pides",
                            style = MaterialTheme.typography.labelLarge,
                        )
                        // Rejilla y no un desplegable: pulsar el golpe que quieres es un
                        // toque, y desde fuera de la pista no se anda uno abriendo menús.
                        RejillaDeGolpes(
                            golpes = grabables,
                            elegido = etiqueta,
                            onElegir = { etiqueta = it },
                        )
                        Button(
                            onClick = { onOrden(AccionDeTanda.INICIAR, etiqueta) },
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Text("Grabar ${etiqueta.label().lowercase()}")
                        }
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(
                                text = estado?.let {
                                    "${it.guardadosEnTotal} golpes guardados en el reloj · ${it.kilobytes} KB"
                                } ?: "El reloj todavía no ha dicho qué tiene guardado",
                                style = MaterialTheme.typography.bodySmall,
                                modifier = Modifier.weight(1f),
                            )
                            if ((estado?.guardadosEnTotal ?: 0) > 0) {
                                TextButton(onClick = { onOrden(AccionDeTanda.ENVIAR, null) }) {
                                    Text("Traer al móvil")
                                }
                            }
                        }
                    }
                }
            }

            QuienLlevaElReloj(alias = alias, nivel = nivel, onAlias = onAlias, onNivel = onNivel)
            AyudaDelMando()
        }
    }
}

@Composable
private fun GrabandoContent(
    estado: EstadoDeTanda,
    onOrden: (AccionDeTanda, ShotType?) -> Unit,
) {
    Column(
        modifier = Modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(
            text = "${estado.capturadosEnTanda}",
            style = MaterialTheme.typography.displayLarge,
            color = MaterialTheme.colorScheme.primary,
        )
        Text(
            text = "golpes de ${estado.etiqueta.label().lowercase()} en esta tanda",
            style = MaterialTheme.typography.bodyMedium,
        )
        // Sin permiso de sensores el servicio se corta al apagarse la pantalla y la tanda
        // se queda a medias. Mejor decirlo que devolver 10 golpes de 50 como si fueran
        // todos.
        if (estado.sensoresPuedenPararse) {
            Text(
                text = "Sin permiso de sensores en el reloj: la tanda puede cortarse al apagarse la pantalla",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error,
            )
        }
        estado.descartes?.takeIf { it.total > 0 }?.let {
            DescartesCard(it, capturados = estado.capturadosEnTanda)
        }
        Button(
            onClick = { onOrden(AccionDeTanda.PARAR, null) },
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 6.dp),
            colors = ButtonDefaults.buttonColors(
                containerColor = MaterialTheme.colorScheme.error,
            ),
        ) {
            Text("Parar tanda")
        }
    }
}

/**
 * Los swings que el detector vio y tiró, con el motivo.
 *
 * Es la mitad que faltaba para poder arreglar el detector. Las tandas solo guardan lo que
 * sí se detecta, así que un golpe perdido no dejaba rastro en ningún sitio y solo quedaba
 * adivinar qué umbral bajar. Cada línea apunta a un umbral concreto.
 */
@Composable
private fun DescartesCard(descartes: DescartesDelDetector, capturados: Int) {
    val vistos = capturados + descartes.total
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(
                MaterialTheme.colorScheme.surfaceVariant,
                RoundedCornerShape(10.dp),
            )
            .padding(10.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(
            text = "Ha cogido $capturados de $vistos movimientos",
            style = MaterialTheme.typography.labelLarge,
            fontWeight = FontWeight.Bold,
            color = if (capturados * 2 >= vistos) {
                MaterialTheme.colorScheme.onSurface
            } else {
                MaterialTheme.colorScheme.error
            },
        )
        if (descartes.swingSinImpacto > 0) {
            LineaDescarte(
                "${descartes.swingSinImpacto} swings sin impacto claro",
                "el golpe fue demasiado suave para el umbral de impacto",
            )
        }
        if (descartes.impactoConSwingCorto > 0) {
            LineaDescarte(
                "${descartes.impactoConSwingCorto} impactos con swing corto",
                "poco recorrido o poca velocidad de pala",
            )
        }
        if (descartes.amago > 0) {
            LineaDescarte("${descartes.amago} amagos", "el brazo se paró sin llegar a golpear")
        }
        if (descartes.enRefractario > 0) {
            LineaDescarte(
                "${descartes.enRefractario} demasiado seguidos",
                "llegaron dentro del tiempo muerto del golpe anterior",
            )
        }
    }
}

@Composable
private fun LineaDescarte(que: String, porque: String) {
    Column {
        Text(que, style = MaterialTheme.typography.labelMedium)
        Text(porque, style = MaterialTheme.typography.bodySmall)
    }
}

@Composable
private fun RejillaDeGolpes(
    golpes: List<ShotType>,
    elegido: ShotType,
    onElegir: (ShotType) -> Unit,
) {
    // Filas de dos a mano en vez de una rejilla perezosa: la lista tiene ocho elementos
    // fijos y meterla en un LazyVerticalGrid dentro de una columna con scroll obliga a
    // fijarle una altura, que es peor que contar de dos en dos.
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        golpes.chunked(2).forEach { fila ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                fila.forEach { tipo ->
                    val elegida = tipo == elegido
                    Text(
                        text = tipo.label(),
                        style = MaterialTheme.typography.labelLarge,
                        color = if (elegida) {
                            MaterialTheme.colorScheme.onPrimaryContainer
                        } else {
                            MaterialTheme.colorScheme.onSurface
                        },
                        modifier = Modifier
                            .weight(1f)
                            .background(
                                if (elegida) {
                                    MaterialTheme.colorScheme.primaryContainer
                                } else {
                                    MaterialTheme.colorScheme.surfaceVariant
                                },
                                RoundedCornerShape(10.dp),
                            )
                            .clickable { onElegir(tipo) }
                            .padding(vertical = 12.dp, horizontal = 10.dp),
                    )
                }
                // Con un número impar, la última fila lleva un hueco para que la que sí
                // tiene pareja no salga del doble de ancha.
                if (fila.size == 1) Column(modifier = Modifier.weight(1f)) {}
            }
        }
    }
}

/**
 * Sin esto el mando sería medio inútil: las muestras se guardan con el alias y el nivel
 * técnico de quien las pegó, y son exactamente los dos datos que hay que cambiar al
 * pasarle el reloj a otra persona. Enterrados en Ajustes se olvidan, y una tanda con el
 * nivel de otro contamina la escala en vez de anclarla.
 */
@Composable
private fun QuienLlevaElReloj(
    alias: String,
    nivel: Int?,
    onAlias: (String) -> Unit,
    onNivel: (Int?) -> Unit,
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text("Quién lleva el reloj", style = MaterialTheme.typography.titleSmall)
            OutlinedTextField(
                value = alias,
                onValueChange = onAlias,
                label = { Text("Nombre") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            Text("Nivel técnico", style = MaterialTheme.typography.labelLarge)
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                (0..7).forEach { valor ->
                    val elegido = (nivel ?: 0) == valor
                    Text(
                        text = if (valor == 0) "–" else "$valor",
                        style = MaterialTheme.typography.labelLarge,
                        modifier = Modifier
                            .weight(1f)
                            .background(
                                if (elegido) {
                                    MaterialTheme.colorScheme.primaryContainer
                                } else {
                                    MaterialTheme.colorScheme.surfaceVariant
                                },
                                RoundedCornerShape(8.dp),
                            )
                            .clickable { onNivel(valor.takeIf { it > 0 }) }
                            .padding(vertical = 10.dp),
                    )
                }
            }
            Text(
                text = if (nivel == null) {
                    "Sin nivel declarado esta tanda mide golpes, pero no ancla la escala de nivel."
                } else {
                    "Estas tandas se guardarán como nivel $nivel, que es lo que ancla la escala."
                },
                style = MaterialTheme.typography.bodySmall,
            )
        }
    }
}

@Composable
private fun AyudaDelMando() {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Text("Cómo sacarle partido", style = MaterialTheme.typography.titleSmall)
            listOf(
                "1. Pon el reloj en la muñeca de quien va a pegar y pon aquí su nombre y su nivel técnico.",
                "2. Elige el golpe, dale a grabar y que pegue 30-40 seguidos solo de ese tipo.",
                "3. Para la tanda, cambia de golpe y repite. Cada tipo con al menos una tanda.",
                "4. Al terminar, en Ajustes → Datos de entrenamiento pulsa «Calibrar con las tandas».",
            ).forEach {
                Text(it, style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}

/**
 * Un aviso, no una pared. El reloj dormido no impide mandar la orden — solo hace que tarde
 * en confirmarse, porque Play Services despierta la app del reloj al entregar el mensaje.
 */
@Composable
private fun ConexionBanner(
    conexion: ConexionDelMando,
    esperando: Boolean,
    haContestado: Boolean,
) {
    val texto = when {
        conexion == ConexionDelMando.SIN_RELOJ ->
            "No hay ningún reloj emparejado con la app instalada."
        esperando ->
            "Orden enviada. El reloj la atiende en cuanto la recibe, aunque tenga la pantalla apagada."
        !haContestado ->
            "Esperando la primera respuesta del reloj. Las órdenes le llegan igual con la pantalla apagada."
        else -> return
    }
    Text(
        text = texto,
        style = MaterialTheme.typography.bodySmall,
        color = if (conexion == ConexionDelMando.SIN_RELOJ) {
            MaterialTheme.colorScheme.error
        } else {
            MaterialTheme.colorScheme.onSurfaceVariant
        },
        modifier = Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(12.dp))
            .padding(12.dp),
    )
}
