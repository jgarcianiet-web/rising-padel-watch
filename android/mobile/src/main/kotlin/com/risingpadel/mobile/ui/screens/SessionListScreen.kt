package com.risingpadel.mobile.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.risingpadel.core.model.PadelSession
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.TextButton
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import com.risingpadel.core.model.SyncState
import com.risingpadel.mobile.ui.LevelHistoryCard
import com.risingpadel.mobile.ui.formatDuration
import com.risingpadel.mobile.ui.formatSessionDate
import com.risingpadel.mobile.ui.label

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SessionListScreen(
    sessions: List<PadelSession>,
    onOpenSession: (String) -> Unit,
    onOpenSettings: () -> Unit,
    onSyncNow: () -> Unit,
    onDeleteSessions: (Set<String>) -> Unit = {},
) {
    // Borrar una sesión de prueba era el camino más largo de la app: entrar en la
    // ficha y bajar hasta el final. Mantener pulsada una tarjeta la borra, y
    // "Seleccionar" abre el modo múltiple para llevarse varias de una vez.
    var seleccionando by remember { mutableStateOf(false) }
    var seleccionadas by remember { mutableStateOf(emptySet<String>()) }
    var confirmando by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(if (seleccionando) "${seleccionadas.size} seleccionadas" else "Mis sesiones") },
                actions = {
                    if (sessions.isNotEmpty()) {
                        TextButton(onClick = {
                            seleccionando = !seleccionando
                            seleccionadas = emptySet()
                        }) {
                            Text(if (seleccionando) "Hecho" else "Seleccionar")
                        }
                    }
                    if (seleccionando) {
                        IconButton(
                            onClick = { confirmando = true },
                            enabled = seleccionadas.isNotEmpty(),
                        ) {
                            Icon(
                                Icons.Default.Delete,
                                contentDescription = "Borrar seleccionadas",
                                tint = MaterialTheme.colorScheme.error,
                            )
                        }
                    } else {
                        IconButton(onClick = onOpenSettings) {
                            Icon(Icons.Default.Settings, contentDescription = "Ajustes")
                        }
                    }
                },
            )
        },
        floatingActionButton = {
            if (sessions.any { it.sync.state != SyncState.SYNCED }) {
                ExtendedFloatingActionButton(
                    onClick = onSyncNow,
                    icon = { Icon(Icons.Default.Sync, contentDescription = null) },
                    text = { Text("Sincronizar") },
                )
            }
        },
    ) { padding ->
        if (sessions.isEmpty()) {
            EmptyState(Modifier.padding(padding))
            return@Scaffold
        }
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // La evolución vive encima de la lista: es la respuesta a "¿estoy
            // mejorando?", que es lo primero que se viene a mirar.
            item(key = "nivel-historico") {
                LevelHistoryCard(sessions)
            }
            items(sessions, key = { it.sessionId }) { session ->
                SessionCard(
                    session = session,
                    seleccionando = seleccionando,
                    marcada = session.sessionId in seleccionadas,
                    onClick = {
                        if (seleccionando) {
                            seleccionadas = if (session.sessionId in seleccionadas) {
                                seleccionadas - session.sessionId
                            } else {
                                seleccionadas + session.sessionId
                            }
                        } else {
                            onOpenSession(session.sessionId)
                        }
                    },
                    onLongClick = {
                        seleccionadas = setOf(session.sessionId)
                        confirmando = true
                    },
                )
            }
        }
    }

    // Confirmación y no borrado directo: una sesión no se recupera y en una lista de
    // tarjetas el dedo resbala. El resumen dice cuántas van, así que confirmar una vez
    // sirve para diez.
    if (confirmando) {
        AlertDialog(
            onDismissRequest = { confirmando = false },
            title = {
                Text(
                    if (seleccionadas.size == 1) "¿Borrar esta sesión?"
                    else "¿Borrar ${seleccionadas.size} sesiones?"
                )
            },
            text = { Text("No se pueden recuperar.") },
            confirmButton = {
                TextButton(onClick = {
                    onDeleteSessions(seleccionadas)
                    seleccionadas = emptySet()
                    seleccionando = false
                    confirmando = false
                }) { Text("Borrar") }
            },
            dismissButton = {
                TextButton(onClick = { confirmando = false }) { Text("Cancelar") }
            },
        )
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun SessionCard(
    session: PadelSession,
    seleccionando: Boolean,
    marcada: Boolean,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
) {
    Card(modifier = Modifier
        .fillMaxWidth()
        .combinedClickable(onClick = onClick, onLongClick = onLongClick)) {
        Column(modifier = Modifier.padding(16.dp)) {
            if (seleccionando) {
                Icon(
                    if (marcada) Icons.Default.CheckCircle else Icons.Default.RadioButtonUnchecked,
                    contentDescription = null,
                    tint = if (marcada) MaterialTheme.colorScheme.error
                    else MaterialTheme.colorScheme.outline,
                    modifier = Modifier.padding(bottom = 6.dp),
                )
            }
            Text(
                text = formatSessionDate(session.startedAtEpochMs),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 6.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Bottom,
            ) {
                Text(
                    text = "${session.totalShots} golpeos",
                    style = MaterialTheme.typography.headlineSmall,
                )
                Text(
                    text = formatDuration(session.durationSeconds),
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
            session.score?.let { score ->
                Text(
                    text = score.allSets.joinToString("  ") { "${it.us}-${it.them}" },
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.padding(top = 2.dp),
                )
            }
            Text(
                text = buildString {
                    append("%.1f golpeos/min".format(session.shotsPerMinute))
                    session.health.heartRate?.let { append(" · ${it.meanBpm} ppm medias") }
                },
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 4.dp),
            )
            SyncBadge(session, modifier = Modifier.padding(top = 8.dp))
        }
    }
}

@Composable
private fun SyncBadge(session: PadelSession, modifier: Modifier = Modifier) {
    val color = when (session.sync.state) {
        SyncState.SYNCED -> MaterialTheme.colorScheme.primary
        SyncState.PENDING -> MaterialTheme.colorScheme.onSurfaceVariant
        SyncState.FAILED, SyncState.NEEDS_AUTH -> MaterialTheme.colorScheme.error
    }
    Text(
        text = session.sync.state.label(),
        style = MaterialTheme.typography.labelMedium,
        color = color,
        modifier = modifier,
    )
}

@Composable
private fun EmptyState(modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            text = "Todavía no hay sesiones",
            style = MaterialTheme.typography.titleMedium,
            textAlign = TextAlign.Center,
        )
        Text(
            text = "Abre Rising Padel en el reloj y elige Partido o Entreno. " +
                "Al terminar, la sesión aparecerá aquí sola.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(top = 8.dp),
        )
    }
}
