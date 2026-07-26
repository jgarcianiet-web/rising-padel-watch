package com.risingpadel.wear

import android.app.Application
import android.content.Context
import com.risingpadel.wear.data.WearSettings
import com.risingpadel.wear.health.ExerciseTracker
import com.risingpadel.wear.sensors.MotionCollector
import com.risingpadel.wear.transport.PhoneSessionSender

/**
 * Contenedor de dependencias hecho a mano. Son cinco objetos sin ciclos: meter un
 * framework de inyección aquí costaría más de lo que ahorra.
 */
class WearContainer(context: Context) {
    val settings by lazy { WearSettings(context) }
    val motionCollector by lazy { MotionCollector(context) }
    val exerciseTracker by lazy { ExerciseTracker(context) }
    val phoneSender by lazy { PhoneSessionSender(context) }
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
