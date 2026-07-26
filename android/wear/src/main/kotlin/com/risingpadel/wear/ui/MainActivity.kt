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
import androidx.wear.compose.material.MaterialTheme
import com.risingpadel.wear.service.PadelExerciseService

class MainActivity : ComponentActivity() {

    private var bodySensorsDenied by mutableStateOf(false)

    private val requestPermissions =
        registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { result ->
            // La FC y los pasos son opcionales: sin ellos la app sigue contando golpeos,
            // así que un permiso denegado no bloquea la pantalla, solo se avisa.
            bodySensorsDenied = result[Manifest.permission.BODY_SENSORS] == false
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        setContent {
            val state by PadelExerciseService.state.collectAsStateWithLifecycle()
            MaterialTheme {
                PadelWearScreen(
                    state = state,
                    healthPermissionDenied = bodySensorsDenied,
                    onStart = {
                        requestPermissions.launch(requiredPermissions())
                        PadelExerciseService.start(this)
                    },
                    onStop = { PadelExerciseService.stop(this) },
                    onDone = { PadelExerciseService.acknowledge() },
                )
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
