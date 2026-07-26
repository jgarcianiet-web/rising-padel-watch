package com.risingpadel.mobile.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
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
import com.risingpadel.core.model.SyncState
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
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Mis sesiones") },
                actions = {
                    IconButton(onClick = onOpenSettings) {
                        Icon(Icons.Default.Settings, contentDescription = "Ajustes")
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
            items(sessions, key = { it.sessionId }) { session ->
                SessionCard(session = session, onClick = { onOpenSession(session.sessionId) })
            }
        }
    }
}

@Composable
private fun SessionCard(session: PadelSession, onClick: () -> Unit) {
    Card(modifier = Modifier
        .fillMaxWidth()
        .clickable(onClick = onClick)) {
        Column(modifier = Modifier.padding(16.dp)) {
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
            text = "Abre Rising Padel en el reloj y pulsa Empezar antes del partido. " +
                "Al terminar, la sesión aparecerá aquí sola.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(top = 8.dp),
        )
    }
}
