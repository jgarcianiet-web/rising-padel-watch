package com.risingpadel.core.detection

import com.risingpadel.core.model.MotionSample
import com.risingpadel.core.model.Vector3
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Los golpes que el detector tira tienen que dejar rastro.
 *
 * Sin esto no había forma de saber por qué se escapaban: las tandas de entrenamiento
 * solo guardan lo que sí se detecta, así que un golpe perdido no existía en ningún
 * sitio y solo quedaba adivinar qué umbral bajar.
 */
class DescartesTest {

    private val config = DetectorConfig.DEFAULT

    private fun muestra(
        tMs: Long,
        gyro: Float,
        accelG: Float = 1f,
    ) = MotionSample(
        timestampMs = tMs,
        accel = Vector3(0f, 0f, accelG),
        gyro = Vector3(0f, 0f, gyro),
        gravity = Vector3(0f, 0f, -1f),
    )

    /** Un swing de [durMs] con [pico] de giro, y un impacto de [impactoG] al final. */
    private fun swing(
        detector: ShotDetector,
        durMs: Long,
        pico: Float,
        impactoG: Float,
        desde: Long = 0,
    ) {
        var t = desde
        while (t < desde + durMs) {
            detector.process(muestra(t, pico))
            t += 20
        }
        detector.process(muestra(t, pico, accelG = impactoG))
        detector.process(muestra(t + 20, 0.2f))
        detector.process(muestra(t + 40, 0.1f))
    }

    @Test
    fun `un detector recien reseteado no ha tirado nada`() {
        val detector = ShotDetector(config)
        detector.reset()
        assertEquals(0, detector.descartes.total)
    }

    @Test
    fun `un swing suave que nunca impacta se apunta como swing sin impacto`() {
        // Es el caso de la bandeja y la volea: golpes de toque, con poca G de impacto.
        val detector = ShotDetector(config)
        detector.reset()
        var t = 0L
        while (t < config.maxSwingMs + 200) {
            detector.process(muestra(t, 8f))
            t += 20
        }
        assertTrue(
            detector.descartes.swingSinImpacto > 0,
            "un swing largo sin impacto tiene que apuntar al umbral de impacto",
        )
    }

    @Test
    fun `un impacto con swing minusculo se apunta aparte`() {
        // Botar la pelota: golpe seco sin recorrido. Va a otro contador porque apunta a
        // otro umbral (minSwingMs / minPeakGyroRadS), no al de impacto.
        val detector = ShotDetector(config)
        detector.reset()
        detector.process(muestra(0, 8f))
        detector.process(muestra(20, 8f))
        detector.process(muestra(40, 8f))
        detector.process(muestra(60, 8f, accelG = 6f))
        detector.process(muestra(80, 0.1f))
        assertEquals(
            0, detector.descartes.swingSinImpacto,
            "esto no es un problema del umbral de impacto",
        )
        assertTrue(detector.descartes.impactoConSwingCorto > 0)
    }

    @Test
    fun `resetear borra la cuenta`() {
        val detector = ShotDetector(config)
        detector.reset()
        var t = 0L
        while (t < config.maxSwingMs + 200) {
            detector.process(muestra(t, 8f))
            t += 20
        }
        assertTrue(detector.descartes.total > 0)
        detector.reset()
        assertEquals(0, detector.descartes.total)
    }

    @Test
    fun `el silencio entre golpes no cuenta como descarte`() {
        val detector = ShotDetector(config)
        detector.reset()
        // Quieto un buen rato: no se está perdiendo ningún golpe, no hay nada que contar.
        var t = 0L
        while (t < 3000) {
            detector.process(muestra(t, 0.05f))
            t += 20
        }
        assertEquals(0, detector.descartes.total)
    }
}
