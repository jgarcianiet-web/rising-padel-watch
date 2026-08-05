package com.risingpadel.mobile.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
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
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonPrimitive

/** El servidor oficial, de serie: el mismo que lleva iOS. */
private const val SERVIDOR_OFICIAL = "https://rising-padel-live.rising-padel-2d82dd5fe2.workers.dev"

/**
 * La comunidad en Android: registro por alias, muro con reacciones, quién está jugando
 * (consultado al abrir; el push llegará con FCM), buscar gente y el ranking semanal.
 * El mismo servidor y las mismas rutas que iOS.
 */
@Composable
fun ComunidadScreen() {
    val context = LocalContext.current
    val api = remember { ComunidadApi(context) { SERVIDOR_OFICIAL } }
    val scope = rememberCoroutineScope()

    var alias by remember { mutableStateOf(api.alias) }
    var posts by remember { mutableStateOf(listOf<ComunidadApi.Post>()) }
    var jugando by remember { mutableStateOf(listOf<ComunidadApi.EnVivo>()) }
    var ranking by remember { mutableStateOf(listOf<ComunidadApi.RankingFila>()) }
    var texto by remember { mutableStateOf("") }
    var aliasNuevo by remember { mutableStateOf("") }
    var aviso by remember { mutableStateOf<String?>(null) }
    var buscando by remember { mutableStateOf(false) }
    var viendo by remember { mutableStateOf<ComunidadApi.EnVivo?>(null) }

    suspend fun refrescar() {
        posts = api.muro()
        jugando = api.jugando()
        ranking = api.ranking()
    }

    LaunchedEffect(alias) { if (alias != null) refrescar() }

    if (alias == null) {
        Column(
            Modifier.fillMaxSize().padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text("Únete a la comunidad", style = MaterialTheme.typography.headlineSmall)
            Text(
                "Sigue a tus amigos, mira sus partidos en vivo y comparte los tuyos. " +
                    "Solo hace falta un alias.",
                style = MaterialTheme.typography.bodyMedium,
            )
            OutlinedTextField(
                value = aliasNuevo,
                onValueChange = { aliasNuevo = it },
                label = { Text("Tu alias (ej: jesus-g)") },
                modifier = Modifier.fillMaxWidth(),
            )
            Button(
                onClick = {
                    scope.launch {
                        val error = api.registrar(aliasNuevo)
                        if (error == null) alias = api.alias else aviso = error
                    }
                },
                enabled = aliasNuevo.length >= 2,
                modifier = Modifier.fillMaxWidth(),
            ) { Text("Crear mi cuenta") }
            aviso?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        }
        return
    }

    if (buscando) {
        BuscarDialog(api, onClose = { buscando = false; scope.launch { refrescar() } })
    }
    viendo?.let { vivo ->
        EnVivoDialog(api, vivo, onClose = { viendo = null })
    }

    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        items(jugando, key = { it.sessionId }) { vivo ->
            Card(Modifier.clickable { viendo = vivo }) {
                Row(Modifier.fillMaxWidth().padding(14.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text("🔴 ${vivo.alias} está jugando ahora", fontWeight = FontWeight.Bold)
                    Text("VER", color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.Black)
                }
            }
        }

        if (ranking.size >= 2) {
            item {
                Card {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text("La semana", style = MaterialTheme.typography.titleMedium)
                        ranking.forEachIndexed { i, fila ->
                            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                Text(
                                    "${listOf("🥇", "🥈", "🥉").getOrElse(i) { " " }} @${fila.alias}",
                                    fontWeight = if (fila.alias == alias) FontWeight.Bold else FontWeight.Normal,
                                )
                                Text("${fila.partidos} PJ · ${fila.victorias} V · ${fila.golpeos} golpeos",
                                    style = MaterialTheme.typography.bodySmall)
                            }
                        }
                    }
                }
            }
        }

        item {
            Card {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = texto,
                        onValueChange = { texto = it },
                        label = { Text("Cuenta algo… (@alias para etiquetar)") },
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Row {
                        TextButton(onClick = { buscando = true }) { Text("Buscar gente") }
                        TextButton(
                            onClick = {
                                val contenido = texto
                                texto = ""
                                scope.launch { api.publicar(contenido); refrescar() }
                            },
                            enabled = texto.isNotBlank(),
                        ) { Text("Publicar") }
                    }
                }
            }
        }

        items(posts, key = { it.id }) { post ->
            Card {
                Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text("@${post.alias}", fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.primary)
                        Text(post.creado, style = MaterialTheme.typography.labelSmall)
                    }
                    Text(post.texto)
                    Row {
                        TextButton(onClick = { scope.launch { api.reaccionar(post.id); refrescar() } }) {
                            Text("🎾 ${if (post.reacciones > 0) post.reacciones else ""}".trim())
                        }
                        if (post.comentarios > 0) {
                            Text(
                                "💬 ${post.comentarios}",
                                style = MaterialTheme.typography.bodySmall,
                                modifier = Modifier.padding(top = 14.dp),
                            )
                        }
                    }
                }
            }
        }

        if (posts.isEmpty()) {
            item {
                Text(
                    "El muro está vacío: busca gente y síguela, o publica tú el primero.",
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
        }
    }
}

@Composable
private fun BuscarDialog(api: ComunidadApi, onClose: () -> Unit) {
    val scope = rememberCoroutineScope()
    var q by remember { mutableStateOf("") }
    var usuarios by remember { mutableStateOf(listOf<ComunidadApi.Usuario>()) }
    LaunchedEffect(q) { usuarios = api.buscar(q) }

    AlertDialog(
        onDismissRequest = onClose,
        title = { Text("Gente") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(value = q, onValueChange = { q = it }, label = { Text("Buscar por alias") })
                usuarios.take(8).forEach { usuario ->
                    Row(
                        Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text("@${usuario.alias}")
                        TextButton(onClick = {
                            scope.launch { api.seguir(usuario); usuarios = api.buscar(q) }
                        }) { Text(if (usuario.siguiendo) "Siguiendo" else "Seguir") }
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = onClose) { Text("Hecho") } },
    )
}

/** El visor del partido de otro: el mismo bucle de 5 s que la página del espectador. */
@Composable
private fun EnVivoDialog(api: ComunidadApi, vivo: ComunidadApi.EnVivo, onClose: () -> Unit) {
    var marcador by remember { mutableStateOf("Buscando el partido…") }
    LaunchedEffect(vivo.sessionId) {
        while (true) {
            val estado = api.estadoEnVivo(vivo.sessionId)
            if (estado != null) {
                val score = estado["score"] as? kotlinx.serialization.json.JsonObject
                val sets = (score?.get("sets") as? kotlinx.serialization.json.JsonArray)
                    ?.joinToString("  ") { set ->
                        val o = set as kotlinx.serialization.json.JsonObject
                        "${o["us"]?.jsonPrimitive?.int}-${o["them"]?.jsonPrimitive?.int}"
                    } ?: ""
                val puntos = estado["pointsUs"]?.jsonPrimitive?.content?.let { us ->
                    "$us – ${estado["pointsThem"]?.jsonPrimitive?.content ?: ""}"
                } ?: ""
                val golpeos = estado["shotCount"]?.jsonPrimitive?.int ?: 0
                val fin = estado["completed"]?.jsonPrimitive?.content == "true"
                marcador = listOf(sets, puntos, "$golpeos golpeos", if (fin) "FINAL" else "")
                    .filter { it.isNotBlank() }.joinToString("\n")
                if (fin) break
            }
            delay(5000)
        }
    }
    AlertDialog(
        onDismissRequest = onClose,
        title = { Text("@${vivo.alias} · EN VIVO") },
        text = { Text(marcador, style = MaterialTheme.typography.headlineSmall) },
        confirmButton = { TextButton(onClick = onClose) { Text("Cerrar") } },
    )
}
