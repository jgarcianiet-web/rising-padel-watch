package com.risingpadel.wear

import android.app.Application
import android.content.Context
import com.risingpadel.wear.data.WearSettings
import com.risingpadel.wear.health.ExerciseTracker
import com.risingpadel.wear.score.ScoreHaptics
import com.risingpadel.wear.score.ScoreSession
import com.risingpadel.wear.sensors.MotionCollector
import com.risingpadel.wear.training.TrainingSession
import com.risingpadel.wear.transport.LiveStateSender
import com.risingpadel.wear.transport.PhoneSessionSender
import com.risingpadel.wear.transport.TrainingDataSender

/**
 * Contenedor de dependencias hecho a mano. Son unos pocos objetos sin ciclos: meter un
 * framework de inyección aquí costaría más de lo que ahorra.
 */
class WearContainer(context: Context) {
    val settings by lazy { WearSettings(context) }
    val motionCollector by lazy { MotionCollector(context) }
    val exerciseTracker by lazy { ExerciseTracker(context) }
    val phoneSender by lazy { PhoneSessionSender(context) }
    val liveStateSender by lazy { LiveStateSender(context) }
    val haptics by lazy { ScoreHaptics(context) }
    val trainingDataSender by lazy { TrainingDataSender(context) }

    // El marcador vive aquí y no en el servicio ni en la Activity: tiene que sobrevivir
    // a que se apague la pantalla y a que Android recree la Activity.
    val scoreSession = ScoreSession()

    /** Modo de recogida de datos. Los datos se quedan aquí hasta que el usuario los envía. */
    val trainingSession by lazy { TrainingSession(context) }
    val appVersion: String = BuildConfig.VERSION_NAME
}

class PadelWearApp : Application() {
    lateinit var container: WearContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = WearContainer(this)
    }
}
