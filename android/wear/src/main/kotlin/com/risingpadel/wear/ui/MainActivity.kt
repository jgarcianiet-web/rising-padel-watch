package com.risingpadel.wear.ui

import android.Manifest
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
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

    private val requestPermissions =
        registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { result ->
            // La FC y los pasos son opcionales: sin ellos la app sigue contando golpeos,
            // así que un permiso denegado no bloquea la pantalla, solo se avisa.
            bodySensorsDenied = result[Manifest.permission.BODY_SENSORS] == false
            // El servicio se arranca aquí y no junto al diálogo: es un servicio en
            // primer plano de tipo `health`, y desde Android 14 arrancar uno de ese tipo
            // sin ningún permiso de salud concedido lanza SecurityException. Hay que
            // esperar a saber qué ha contestado el usuario.
            PadelExerciseService.start(this)
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val container = (application as PadelWearApp).container

        setContent {
            val state by PadelExerciseService.state.collectAsStateWithLifecycle()
            val score by container.scoreSession.state.collectAsStateWithLifecycle()
            val preferences by container.settings.preferences
                .collectAsStateWithLifecycle(initialValue = WearPreferences())

            MaterialTheme {
                val liveScore = score
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
                    )
                } else {
                    PadelWearScreen(
                        state = state,
                        healthPermissionDenied = bodySensorsDenied,
                        trackScore = preferences.trackScore,
                        deuceFormat = preferences.deuceFormat,
                        onTrackScoreChange = { enabled ->
                            lifecycleScope.launch {
                                container.settings.update(preferences.copy(trackScore = enabled))
                            }
                        },
                        onDeuceFormatChange = { format ->
                            lifecycleScope.launch {
                                container.settings.update(preferences.copy(deuceFormat = format))
                            }
                        },
                        onStart = { requestPermissions.launch(requiredPermissions()) },
                        onStop = { PadelExerciseService.stop(this) },
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
}
