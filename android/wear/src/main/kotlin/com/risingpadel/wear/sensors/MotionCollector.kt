package com.risingpadel.wear.sensors

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import com.risingpadel.core.model.MotionSample
import com.risingpadel.core.model.Vector3
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.buffer
import kotlinx.coroutines.flow.callbackFlow

/**
 * Entrega [MotionSample] normalizadas a partir de los sensores de la muñeca.
 *
 * Android publica acelerómetro lineal, giróscopo y gravedad como tres streams
 * independientes. Aquí se fusionan tomando el acelerómetro como reloj maestro (es el
 * que marca el impacto) y usando el último valor conocido de los otros dos. A 50 Hz el
 * desfase entre streams es de una muestra como mucho, muy por debajo de la duración de
 * un swing.
 */
class MotionCollector(context: Context) {

    private val sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager

    val isSupported: Boolean
        get() = sensorManager.getDefaultSensor(Sensor.TYPE_GYROSCOPE) != null &&
            sensorManager.getDefaultSensor(Sensor.TYPE_LINEAR_ACCELERATION) != null

    fun samples(sampleRateHz: Int = 50): Flow<MotionSample> = callbackFlow {
        val linearAcceleration = sensorManager.getDefaultSensor(Sensor.TYPE_LINEAR_ACCELERATION)
        val gyroscope = sensorManager.getDefaultSensor(Sensor.TYPE_GYROSCOPE)
        val gravitySensor = sensorManager.getDefaultSensor(Sensor.TYPE_GRAVITY)

        if (linearAcceleration == null || gyroscope == null) {
            close(IllegalStateException("Este reloj no tiene giróscopo o acelerómetro lineal"))
            return@callbackFlow
        }

        var lastGyro = Vector3.ZERO
        // Por defecto, gravedad "hacia abajo" en -X: si el sensor de gravedad no existe,
        // la elevación sale plana y todos los golpeos se clasifican como bajos, que es
        // un fallo conservador (nunca inventa smashes).
        var lastGravity = Vector3(-1f, 0f, 0f)

        val listener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                when (event.sensor.type) {
                    Sensor.TYPE_GYROSCOPE ->
                        lastGyro = Vector3(event.values[0], event.values[1], event.values[2])

                    Sensor.TYPE_GRAVITY ->
                        lastGravity = Vector3(
                            event.values[0] / STANDARD_GRAVITY,
                            event.values[1] / STANDARD_GRAVITY,
                            event.values[2] / STANDARD_GRAVITY,
                        )

                    Sensor.TYPE_LINEAR_ACCELERATION -> {
                        val sample = MotionSample(
                            timestampMs = event.timestamp / 1_000_000L,
                            accel = Vector3(
                                event.values[0] / STANDARD_GRAVITY,
                                event.values[1] / STANDARD_GRAVITY,
                                event.values[2] / STANDARD_GRAVITY,
                            ),
                            gyro = lastGyro,
                            gravity = lastGravity,
                        )
                        trySend(sample)
                    }
                }
            }

            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
        }

        val periodUs = 1_000_000 / sampleRateHz
        sensorManager.registerListener(listener, linearAcceleration, periodUs)
        sensorManager.registerListener(listener, gyroscope, periodUs)
        gravitySensor?.let { sensorManager.registerListener(listener, it, periodUs) }

        awaitClose { sensorManager.unregisterListener(listener) }
    }
        // Si el consumidor se retrasa preferimos perder la muestra más vieja antes que
        // bloquear el hilo de sensores.
        .buffer(capacity = 256, onBufferOverflow = BufferOverflow.DROP_OLDEST)

    private companion object {
        const val STANDARD_GRAVITY = 9.80665f
    }
}
