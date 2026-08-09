package com.risingpadel.wear.ui

import android.Manifest
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.lifecycleScope
import androidx.wear.compose.material.MaterialTheme
import com.risingpadel.wear.PadelWearApp
import com.risingpadel.wear.data.WearPreferences
import com.risingpadel.wear.service.PadelExerciseService
import com.risingpadel.wear.service.SessionStatus
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {

    private var bodySensorsDenied by mutableStateOf(false)

    /**
     * La rutina elegida, a la espera de que el usuario conteste a los permisos.
     *
     * El servicio lee esto al arrancar y no puede arrancarse antes de saber qué ha
     * contestado el usuario: desde Android 14 un servicio en primer plano de tipo
     * `health` sin ningún permiso de salud concedido lanza SecurityException.
     */
    private var rutinaPendiente: String? = null

    /** Venimos del aviso que dejó el móvil: hay que abrir la tanda y arrancarla. */
    private var arrancarTandaAlAbrir = false

    private val requestPermissions =
        registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { result ->
            // La FC y los pasos son opcionales: sin ellos la app sigue contando golpeos,
            // así que un permiso denegado no bloquea la pantalla, solo se avisa.
            bodySensorsDenied = result[Manifest.permission.BODY_SENSORS] == false
            // El servicio se arranca aquí y no junto al diálogo: es un servicio en
            // primer plano de tipo `health`, y desde Android 14 arrancar uno de ese tipo
            // sin ningún permiso de salud concedido lanza SecurityException. Hay que
            // esperar a saber qué ha contestado el usuario.
            PadelExerciseService.start(this, rutinaPendiente)
            rutinaPendiente = null
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val container = (application as PadelWearApp).container
        arrancarTandaAlAbrir = intent?.action == ACTION_ARRANCAR_TANDA

        setContent {
            val state by PadelExerciseService.state.collectAsStateWithLifecycle()
            val score by container.scoreSession.state.collectAsStateWithLifecycle()
            val preferences by container.settings.preferences
                .collectAsStateWithLifecycle(initialValue = WearPreferences())
            val training by container.trainingSession.state.collectAsStateWithLifecycle()
            var showTraining by remember { mutableStateOf(arrancarTandaAlAbrir) }
            var showRutinas by remember { mutableStateOf(false) }

            // El móvil pidió una tanda con la app cerrada y Android no dejó arrancarla
            // sola; el jugador ha tocado el aviso, que es el toque que la desbloquea.
            LaunchedEffect(Unit) {
                if (!arrancarTandaAlAbrir) return@LaunchedEffect
                arrancarTandaAlAbrir = false
                if (!training.recording) PadelExerciseService.startTraining(this@MainActivity)
            }

            MaterialTheme {
                val liveScore = score
                // El modo de datos es una pantalla aparte: no tiene nada que ver con
                // jugar un partido y mezclarlas solo confundiría.
                if (showTraining || training.recording) {
                    TrainingScreen(
                        state = training,
                        onLabelChange = container.trainingSession::setLabel,
                        onStart = { PadelExerciseService.startTraining(this) },
                        onStop = { PadelExerciseService.stop(this) },
                        onSendToPhone = {
                            lifecycleScope.launch {
                                container.trainingDataSender.send(container.trainingSession.store.file)
                            }
                        },
                        onExit = { showTraining = false },
                    )
                    return@MaterialTheme
                }

                if (showRutinas && state.status == SessionStatus.IDLE) {
                    RutinaChooser(
                        onPick = { rutina ->
                            showRutinas = false
                            // Igual que en el arranque normal: los ajustes se escriben
                            // ANTES de pedir permisos, porque el servicio los lee al
                            // arrancar y una escritura en paralelo podría llegar tarde.
                            lifecycleScope.launch {
                                container.settings.update(preferences.copy(trackScore = false))
                                rutinaPendiente = rutina.id
                                requestPermissions.launch(requiredPermissions())
                            }
                        },
                        onBack = { showRutinas = false },
                    )
                    return@MaterialTheme
                }

                // Con marcador activo, el marcador **es** la pantalla del partido: es lo
                // que el jugador mira y toca entre puntos. El conteo de golpeos sigue
                // corriendo por debajo y aparece en la línea de estado.
                if (state.status == SessionStatus.RECORDING && liveScore != null) {
                    ScoreScreen(
                        score = liveScore,
                        shotCount = state.shotCount,
                        onPoint = { side ->
                            container.haptics.play(container.scoreSession.point(side))
                        },
                        onUndo = {
                            container.scoreSession.undo()?.let { container.haptics.play(it) }
                        },
                        onStop = { PadelExerciseService.stop(this) },
                    )
                } else {
                    PadelWearScreen(
                        state = state,
                        healthPermissionDenied = bodySensorsDenied,
                        deuceFormat = preferences.deuceFormat,
                        collectTrainingData = preferences.collectTrainingData,
                        onOpenTraining = { showTraining = true },
                        onOpenRutinas = { showRutinas = true },
                        // Los ajustes se escriben ANTES de pedir permisos: el servicio
                        // lee las preferencias al arrancar, y si la escritura fuera en
                        // paralelo podría ver todavía el modo anterior.
                        onStartMatch = { format ->
                            lifecycleScope.launch {
                                container.settings.update(
                                    preferences.copy(trackScore = true, deuceFormat = format)
                                )
                                requestPermissions.launch(requiredPermissions())
                            }
                        },
                        onStartFree = {
                            lifecycleScope.launch {
                                container.settings.update(preferences.copy(trackScore = false))
                                requestPermissions.launch(requiredPermissions())
                            }
                        },
                        onStop = { PadelExerciseService.stop(this) },
                        onSkipStep = { PadelExerciseService.skipStep(this) },
                        onDone = { PadelExerciseService.acknowledge() },
                    )
                }
            }
        }
    }

    private fun requiredPermissions(): Array<String> = buildList {
        add(Manifest.permission.BODY_SENSORS)
        add(Manifest.permission.ACTIVITY_RECOGNITION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            add(Manifest.permission.POST_NOTIFICATIONS)
        }
    }.toTypedArray()

    companion object {
        /** El aviso del reloj que arranca una tanda pedida desde el móvil. */
        const val ACTION_ARRANCAR_TANDA = "com.risingpadel.wear.ARRANCAR_TANDA"
    }
}
