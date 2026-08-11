package com.risingpadel.core.session

import com.risingpadel.core.MotionFixtures
import com.risingpadel.core.model.Platform
import com.risingpadel.core.model.SourceInfo
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * Los descartes del detector viajan también en la sesión normal, no solo en las tandas.
 *
 * Nace de una frase de pista: "ha habido un momento que no ha contado el reloj". Sin este
 * dato, la app no tiene nada que contestar a eso — y peor, el jugador tampoco sabe si el
 * problema es suyo, del reloj o de un umbral.
 */
class DescartesDeLaSesionTest {

    private fun recorder() = SessionRecorder(
        source = SourceInfo(Platform.WATCHOS, "test", "1.0"),
        sessionIdProvider = { "s1" },
    )

    @Test
    fun `una sesion limpia no se deja nada`() {
        val recorder = recorder()
        recorder.start(0, 0)
        val muestras = MotionFixtures.rest(0, 400) + MotionFixtures.forehand(400)
        muestras.forEach { recorder.onMotion(it) }
        val sesion = recorder.finish(10_000, 3_000, shareHealth = false)

        assertEquals(1, sesion.totalShots)
        val descartes = sesion.descartes
        assertNotNull(descartes)
        // Cero es un dato: dice "no se dejó nada". Un nulo diría "esto es de antes".
        assertEquals(0, descartes.total)
    }

    @Test
    fun `un amago se apunta y no cuenta como golpe`() {
        val recorder = recorder()
        recorder.start(0, 0)
        // Un swing que arranca y se apaga sin impacto: la preparación que no llega.
        val amago = MotionFixtures.swing(
            startMs = 400,
            peakGyroRadS = 9f,
            swingDurationMs = 200,
            impactG = 0f,
            axialFraction = 0.3f,
            elevationDeg = -20f,
        )
        (MotionFixtures.rest(0, 400) + amago + MotionFixtures.rest(700, 1_500))
            .forEach { recorder.onMotion(it) }
        val sesion = recorder.finish(10_000, 3_000, shareHealth = false)

        assertEquals(0, sesion.totalShots, "un amago no es un golpe")
        val descartes = assertNotNull(sesion.descartes)
        assertTrue(descartes.total > 0, "pero tiene que dejar rastro: $descartes")
    }

    @Test
    fun `los descartes se pueden mirar antes de que la sesion acabe`() {
        // La ficha de la sesión en curso los enseña; esperar al final sería enseñarlos
        // cuando ya no se puede hacer nada.
        val recorder = recorder()
        recorder.start(0, 0)
        assertEquals(0, recorder.descartes.total)
    }
}
