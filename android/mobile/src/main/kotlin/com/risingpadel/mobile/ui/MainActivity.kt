package com.risingpadel.mobile.ui

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.SportsTennis
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
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
    const val LAST = "last"
    const val SESSIONS = "sessions"
    const val LIGA = "liga"
    const val LIGA_DETAIL = "liga/{matchId}"
    const val COMUNIDAD = "comunidad"
    const val SETTINGS = "settings"
    const val DETAIL = "sessions/{sessionId}"

    fun detail(sessionId: String) = "sessions/$sessionId"
    fun ligaDetail(matchId: Long) = "liga/$matchId"
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

/** Cambio de pestaña sin apilar: volver atrás desde una pestaña sale de la app. */
private fun NavHostController.navigateTab(route: String) {
    navigate(route) {
        popUpTo(graph.startDestinationId) { saveState = true }
        launchSingleTop = true
        restoreState = true
    }
}

@Composable
private fun PadelApp(viewModel: PadelViewModel = viewModel()) {
    val navController = rememberNavController()
    val context = androidx.compose.ui.platform.LocalContext.current
    val sessions by viewModel.sessions.collectAsStateWithLifecycle()

    // El onboarding solo existe para quien de verdad empieza de cero: con sesiones o
    // cuenta de comunidad previas se da por hecho sin enseñarlo.
    val onboardingPrefs = remember {
        context.getSharedPreferences("onboarding", android.content.Context.MODE_PRIVATE)
    }
    val onboardingDone = remember {
        androidx.compose.runtime.mutableStateOf(
            onboardingPrefs.getBoolean("done", false) ||
                com.risingpadel.mobile.data.ComunidadApi(context) {
                    com.risingpadel.mobile.data.ComunidadApi.SERVIDOR_OFICIAL
                }.tieneCuenta
        )
    }
    LaunchedEffect(sessions) {
        if (sessions.isNotEmpty() && !onboardingDone.value) {
            onboardingPrefs.edit().putBoolean("done", true).apply()
            onboardingDone.value = true
        }
    }
    if (!onboardingDone.value) {
        com.risingpadel.mobile.ui.screens.OnboardingScreen(onDone = {
            onboardingPrefs.edit().putBoolean("done", true).apply()
            onboardingDone.value = true
        })
        return
    }
    val preferences by viewModel.preferences.collectAsStateWithLifecycle()
    val message by viewModel.message.collectAsStateWithLifecycle()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(message) {
        message?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.consumeMessage()
        }
    }

    // La media del historial alimenta la línea de referencia de las gráficas.
    val playerAverageLevel = sessions
        .map { it.level }
        .filter { it.gradedShots > 0 }
        .map { it.overall }
        .takeIf { it.isNotEmpty() }
        ?.average()?.toFloat()

    val currentRoute = navController.currentBackStackEntryAsState().value?.destination?.route

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        containerColor = MaterialTheme.colorScheme.background,
        bottomBar = {
            // Las pestañas solo se ven en las dos raíces: dentro de un detalle o de
            // ajustes la navegación es volver, no cambiar de pestaña.
            if (currentRoute in setOf(Routes.LAST, Routes.SESSIONS, Routes.LIGA, Routes.COMUNIDAD)) {
                NavigationBar {
                    NavigationBarItem(
                        selected = currentRoute == Routes.LAST,
                        onClick = { navController.navigateTab(Routes.LAST) },
                        icon = { Icon(Icons.Default.SportsTennis, contentDescription = null) },
                        label = { Text("Última sesión") },
                    )
                    NavigationBarItem(
                        selected = currentRoute == Routes.SESSIONS,
                        onClick = { navController.navigateTab(Routes.SESSIONS) },
                        icon = { Icon(Icons.Default.History, contentDescription = null) },
                        label = { Text("Histórico") },
                    )
                    NavigationBarItem(
                        selected = currentRoute == Routes.LIGA,
                        onClick = { navController.navigateTab(Routes.LIGA) },
                        icon = { Icon(Icons.Default.EmojiEvents, contentDescription = null) },
                        label = { Text("Liga") },
                    )
                    NavigationBarItem(
                        selected = currentRoute == Routes.COMUNIDAD,
                        onClick = { navController.navigateTab(Routes.COMUNIDAD) },
                        icon = { Icon(Icons.Default.Groups, contentDescription = null) },
                        label = { Text("Comunidad") },
                    )
                }
            }
        },
    ) { padding ->
        NavHost(
            navController = navController,
            startDestination = Routes.LAST,
            modifier = Modifier.padding(padding),
        ) {
            // La portada de tres segundos: nivel, racha, meta y objetivo. La última
            // sesión completa queda a un toque — el mismo diseño que iOS.
            composable(Routes.LAST) {
                val last = sessions.firstOrNull()
                if (last == null) {
                    SessionListScreen(
                        sessions = emptyList(),
                        onOpenSession = {},
                        onOpenSettings = { navController.navigate(Routes.SETTINGS) },
                        onSyncNow = viewModel::syncNow,
                    )
                } else {
                    com.risingpadel.mobile.ui.screens.InicioScreen(
                        session = last,
                        playerAverageLevel = playerAverageLevel,
                        onOpenSession = { navController.navigate(Routes.detail(last.sessionId)) },
                        onOpenSettings = { navController.navigate(Routes.SETTINGS) },
                    )
                }
            }

            composable(Routes.SESSIONS) {
                SessionListScreen(
                    sessions = sessions,
                    onOpenSession = { navController.navigate(Routes.detail(it)) },
                    onOpenSettings = { navController.navigate(Routes.SETTINGS) },
                    onSyncNow = viewModel::syncNow,
                )
            }

            composable(Routes.LIGA) {
                com.risingpadel.mobile.ui.screens.LigaScreen(
                    onOpenMatch = { navController.navigate(Routes.ligaDetail(it)) },
                )
            }

            composable(Routes.COMUNIDAD) {
                com.risingpadel.mobile.ui.screens.ComunidadScreen()
            }

            composable(Routes.LIGA_DETAIL) { entry ->
                val matchId = entry.arguments?.getString("matchId")?.toLongOrNull()
                val estado = com.risingpadel.mobile.data.LigaStore(context).load()
                val match = estado.matches.firstOrNull { it.id == matchId }
                if (match != null) {
                    com.risingpadel.mobile.ui.screens.LigaMatchDetailScreen(
                        match = match,
                        objetivos = estado.objetivos,
                        onBack = { navController.popBackStack() },
                    )
                }
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
                    playerAverageLevel = playerAverageLevel,
                    onBack = { navController.popBackStack() },
                    onRetrySync = { viewModel.retrySession(session.sessionId) },
                    onLinkMatch = { matchId, leagueId ->
                        viewModel.linkToMatch(session.sessionId, matchId, leagueId)
                    },
                    onDelete = {
                        viewModel.deleteSession(session.sessionId)
                        navController.popBackStack()
                    },
                    onApplyReview = { viewModel.applyReview(session.sessionId, it) },
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
                    onPlayerLevelChange = viewModel::setPlayerLevel,
                    onVersionTapped = viewModel::onVersionTapped,
                    onExportTrainingData = { shareTrainingData(context, viewModel) },
                    onDeleteTrainingData = viewModel::deleteTrainingData,
                )
            }
        }
    }
}
