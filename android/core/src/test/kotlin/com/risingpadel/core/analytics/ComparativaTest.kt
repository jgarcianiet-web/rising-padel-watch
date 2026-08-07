package com.risingpadel.core.analytics

import com.risingpadel.core.model.PadelSession
import com.risingpadel.core.model.Platform
import com.risingpadel.core.model.PlayerProfile
import com.risingpadel.core.model.Shot
import com.risingpadel.core.model.ShotFeatures
import com.risingpadel.core.model.ShotType
import com.risingpadel.core.model.SourceInfo
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ComparativaTest {

    private fun sesion(id: String, golpeos: Int, velocidad: Float = 50f) = PadelSession(
        sessionId = id,
        source = SourceInfo(Platform.WATCHOS, "Watch", "1.0"),
        startedAtEpochMs = 0,
        endedAtEpochMs = 60 * 60_000,
        profile = PlayerProfile(),
        shots = List(golpeos) {
            Shot(
                offsetMs = it * 1000L,
                type = ShotType.FOREHAND,
                racketSpeedKmh = velocidad,
                impactG = 5f,
                confidence = 0.9f,
                features = ShotFeatures(
                    sweptAngleDeg = 200f,
                    peakGyroRadS = 20f,
                    elevationDeg = 20f,
                    axialRotationRadS = 3f,
                    swingDurationMs = 300,
                ),
            )
        },
    )

    // --- la comparación ---

    @Test
    fun `sin media no hay nada que comparar`() {
        assertNull(Comparativa.de(45f, null))
    }

    @Test
    fun `una diferencia despreciable no se enseña`() {
        // Un 1% arriba no es "mejor que tu media", es el mismo día contado dos veces.
        assertNull(Comparativa.de(50.5f, 50f))
    }

    @Test
    fun `por encima de tu media es mejor, y dice cuanto`() {
        val c = Comparativa.de(53f, 50f)
        assertNotNull(c)
        assertEquals(3f, c.delta, 0.01f)
        assertEquals(0.06f, c.fraccion, 0.01f)
        assertTrue(c.mejor)
    }

    @Test
    fun `por debajo de tu media es peor`() {
        val c = Comparativa.de(40f, 50f)
        assertNotNull(c)
        assertEquals(-10f, c.delta, 0.01f)
        assertTrue(!c.mejor)
    }

    @Test
    fun `en las metricas donde subir es peor, el signo se invierte`() {
        val c = Comparativa.de(40f, 50f, masEsMejor = false)
        assertNotNull(c)
        assertTrue(c.mejor, "bajar es mejorar cuando menos es mejor")
    }

    @Test
    fun `una media de cero no divide`() {
        assertNull(Comparativa.de(10f, 0f))
    }

    // --- las medias ---

    @Test
    fun `con menos de tres sesiones no se habla de tu media`() {
        val medias = MediasDelJugador.de(
            listOf(sesion("a", 100), sesion("b", 200))
        )
        assertNull(medias.golpeos, "dos días sueltos no son una tendencia")
    }

    @Test
    fun `la media excluye la sesion que se esta comparando`() {
        // Tres sesiones de 100 y la de hoy de 400. Si la de hoy entrara en su propia
        // media (175), el "+225" saldría como "+225 sobre 175" en vez de sobre 100.
        val sesiones = listOf(
            sesion("hoy", 400), sesion("a", 100), sesion("b", 100), sesion("c", 100)
        )
        val medias = MediasDelJugador.de(sesiones, excluyendo = "hoy")

        assertEquals(100f, medias.golpeos!!, 0.1f)
        assertEquals(300f, Comparativa.de(400f, medias.golpeos)!!.delta, 0.1f)
    }

    @Test
    fun `sin excluir nada la media es la de todo el historial`() {
        val medias = MediasDelJugador.de(
            listOf(sesion("a", 100), sesion("b", 200), sesion("c", 300))
        )
        assertEquals(200f, medias.golpeos!!, 0.1f)
    }

    @Test
    fun `las sesiones sin golpeos no cuentan para la media`() {
        val medias = MediasDelJugador.de(
            listOf(sesion("a", 100), sesion("b", 100), sesion("c", 100), sesion("vacia", 0))
        )
        assertEquals(100f, medias.golpeos!!, 0.1f)
    }

    @Test
    fun `la velocidad media del historial sale de las velocidades, no de los golpeos`() {
        val medias = MediasDelJugador.de(
            listOf(
                sesion("a", 10, velocidad = 40f),
                sesion("b", 100, velocidad = 50f),
                sesion("c", 10, velocidad = 60f),
            )
        )
        // Media de las medias de sesión: cada sesión pesa lo mismo, aunque una tenga
        // diez veces más golpeos. Es lo que quiere decir "tu media por partido".
        assertEquals(50f, medias.velocidadMedia!!, 0.1f)
    }
}
