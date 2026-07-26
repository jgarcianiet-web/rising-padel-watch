package com.risingpadel.mobile.ui

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.risingpadel.mobile.ui.screens.SessionDetailScreen
import com.risingpadel.mobile.ui.screens.SessionListScreen
import com.risingpadel.mobile.ui.screens.SettingsScreen
import com.risingpadel.mobile.ui.theme.RisingPadelTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        setContent {
            RisingPadelTheme {
                PadelApp()
            }
        }
    }
}

private object Routes {
    const val SESSIONS = "sessions"
    const val SETTINGS = "settings"
    const val DETAIL = "sessions/{sessionId}"

    fun detail(sessionId: String) = "sessions/$sessionId"
}

/**
 * Comparte el JSONL con otra app. Es la única vía por la que los datos de entrenamiento
 * salen del móvil: no se suben a ningún sitio automáticamente.
 */
private fun shareTrainingData(context: android.content.Context, viewModel: PadelViewModel) {
    val file = viewModel.trainingDataFile() ?: return
    val uri = androidx.core.content.FileProvider.getUriForFile(
        context,
        "${context.packageName}.fileprovider",
        file,
    )
    val intent = android.content.Intent(android.content.Intent.ACTION_SEND).apply {
        type = "application/json"
        putExtra(android.content.Intent.EXTRA_STREAM, uri)
        addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    context.startActivity(android.content.Intent.createChooser(intent, "Exportar datos"))
}

@Composable
private fun PadelApp(viewModel: PadelViewModel = viewModel()) {
    val navController = rememberNavController()
    val context = androidx.compose.ui.platform.LocalContext.current
    val sessions by viewModel.sessions.collectAsStateWithLifecycle()
    val preferences by viewModel.preferences.collectAsStateWithLifecycle()
    val message by viewModel.message.collectAsStateWithLifecycle()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(message) {
        message?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.consumeMessage()
        }
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        containerColor = MaterialTheme.colorScheme.background,
    ) { padding ->
        NavHost(
            navController = navController,
            startDestination = Routes.SESSIONS,
            modifier = Modifier.padding(padding),
        ) {
            composable(Routes.SESSIONS) {
                SessionListScreen(
                    sessions = sessions,
                    onOpenSession = { navController.navigate(Routes.detail(it)) },
                    onOpenSettings = { navController.navigate(Routes.SETTINGS) },
                    onSyncNow = viewModel::syncNow,
                )
            }

            composable(Routes.DETAIL) { entry ->
                val sessionId = entry.arguments?.getString("sessionId")
                val session = sessions.firstOrNull { it.sessionId == sessionId }
                if (session == null) {
                    // La sesión se borró mientras estaba abierta.
                    LaunchedEffect(sessionId) { navController.popBackStack() }
                    return@composable
                }
                SessionDetailScreen(
                    session = session,
                    onBack = { navController.popBackStack() },
                    onRetrySync = { viewModel.retrySession(session.sessionId) },
                    onLinkMatch = { matchId, leagueId ->
                        viewModel.linkToMatch(session.sessionId, matchId, leagueId)
                    },
                    onDelete = {
                        viewModel.deleteSession(session.sessionId)
                        navController.popBackStack()
                    },
                )
            }

            composable(Routes.SETTINGS) {
                SettingsScreen(
                    preferences = preferences,
                    onBack = { navController.popBackStack() },
                    onBaseUrlChange = viewModel::setLeagueBaseUrl,
                    onTokenChange = viewModel::setToken,
                    onShareHealthChange = viewModel::setShareHealth,
                    onShareEventsChange = viewModel::setShareShotEvents,
                    onHandChange = viewModel::setHand,
                    onWristChange = viewModel::setWatchWrist,
                    onSensitivityChange = viewModel::setSensitivity,
                    onCollectTrainingDataChange = viewModel::setCollectTrainingData,
                    onPlayerAliasChange = viewModel::setPlayerAlias,
                    onExportTrainingData = { shareTrainingData(context, viewModel) },
                    onDeleteTrainingData = viewModel::deleteTrainingData,
                )
            }
        }
    }
}
