package com.risingpadel.core.model

import com.risingpadel.core.score.MatchScore
import com.risingpadel.core.score.Side
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * "Sin marcador" y "sin partido" no son lo mismo.
 *
 * Hasta que existió `esPartido`, la única señal de que una sesión era un partido era
 * tener `score`. Quien jugaba un partido de verdad sin ganas de ir anotando punto por
 * punto acababa con un entreno suelto que no contaba para su liga, y no había forma de
 * decirle a la app que se equivocaba. Estos tests fijan las tres piezas: que el campo
 * distingue los tres casos, que la liga usa el criterio combinado, y que el historial
 * grabado antes de que el campo existiera no se rompe ni se queda fuera.
 */
class PartidoSinMarcadorTest {

    private fun sesion(
        score: MatchScore? = null,
        esPartido: Boolean? = null,
    ) = PadelSession(
        sessionId = "s1",
        source = SourceInfo(Platform.WATCHOS, "Apple Watch", "1.0"),
        startedAtEpochMs = 1_754_000_000_000,
        endedAtEpochMs = 1_754_000_000_000 + 60 * 60_000L,
        profile = PlayerProfile(),
        shots = emptyList(),
        score = score,
        esPartido = esPartido,
    )

    @Test
    fun `un partido sin marcador cuenta como partido`() {
        // Es el caso entero de esta funcionalidad: sin marcador, pero es un partido.
        assertTrue(sesion(esPartido = true).cuentaComoPartido)
    }

    @Test
    fun `un entreno no cuenta como partido`() {
        assertFalse(sesion(esPartido = false).cuentaComoPartido)
    }

    @Test
    fun `una sesion con marcador cuenta aunque no traiga el campo nuevo`() {
        // El historial anterior: no tiene `esPartido` y se reconoce por el marcador.
        // Preguntar solo por el campo nuevo habría dejado toda la liga vieja fuera.
        val conMarcador = sesion(score = MatchScore.start().pointTo(Side.US))
        assertNull(conMarcador.esPartido)
        assertTrue(conMarcador.cuentaComoPartido)
    }

    @Test
    fun `una sesion antigua sin marcador sigue sin contar`() {
        val vieja = sesion()
        assertNull(vieja.esPartido)
        assertFalse(vieja.cuentaComoPartido)
    }

    @Test
    fun `un JSON grabado antes de que existiera el campo se lee sin fallar`() {
        // Lo que de verdad se comprueba aquí es que el campo es OPCIONAL. Si fuera un
        // booleano obligatorio, cada sesión guardada antes de hoy reventaría al leerse
        // y el jugador perdería el historial entero por un campo nuevo.
        val json = Json { ignoreUnknownKeys = true }
        val guardado = """
            {
              "sessionId": "vieja",
              "source": {"platform": "WATCHOS", "device": "Apple Watch", "appVersion": "0.9"},
              "startedAtEpochMs": 1750000000000,
              "endedAtEpochMs": 1750003600000,
              "profile": {},
              "shots": []
            }
        """.trimIndent()

        val sesion = json.decodeFromString(PadelSession.serializer(), guardado)
        assertEquals("vieja", sesion.sessionId)
        assertNull(sesion.esPartido)
        assertFalse(sesion.cuentaComoPartido)
    }

    @Test
    fun `false y null se guardan distintos`() {
        // La diferencia importa: null es "esta sesión es de antes y no se sabe", false
        // es "el jugador dijo que esto era un entreno". Si al serializar se confundieran,
        // se perdería la única forma de distinguir un dato ausente de una respuesta.
        val json = Json { encodeDefaults = true }
        val entreno = json.encodeToString(PadelSession.serializer(), sesion(esPartido = false))
        val antigua = json.encodeToString(PadelSession.serializer(), sesion())

        assertTrue(entreno.contains("\"esPartido\":false"), entreno)
        assertFalse(antigua.contains("\"esPartido\":true"), antigua)
        assertEquals(false, json.decodeFromString(PadelSession.serializer(), entreno).esPartido)
        assertNull(json.decodeFromString(PadelSession.serializer(), antigua).esPartido)
    }
}
