package com.risingpadel.core.liga

import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * De dónde salió cada número, y por qué importa tanto.
 *
 * El reloj y una pulsera ajena pueden decir las dos "3,5" sobre el mismo partido sin que
 * signifiquen lo mismo: son escalas distintas medidas con sensores distintos. Pintarlas
 * en la misma curva de evolución produce un salto que el jugador no ha dado — y como la
 * curva es precisamente lo que la app promete ("¿voy mejorando?"), ese salto no es un
 * detalle estético, es la app mintiendo.
 */
class FuenteDeDatosTest {

    private fun partido(fecha: String, nivel: Double?, fuente: String? = null) =
        LigaMatch(id = fecha.hashCode().toLong(), fecha = fecha, nivelBand = nivel, fuente = fuente)

    @Test
    fun `un backup anterior al campo se lee y la fuente queda en null`() {
        // No se supone "reloj": la mayoría de esos partidos se apuntaron a mano, y
        // suponerlo pondría una etiqueta falsa en todo el historial.
        val json = """{"id": 1, "fecha": "2026-03-01", "nivelBand": 3.4}"""
        val match = Json { ignoreUnknownKeys = true }
            .decodeFromString(LigaMatch.serializer(), json)

        assertEquals(3.4, match.nivelBand)
        assertNull(match.fuente)
    }

    @Test
    fun `la curva del reloj no se lleva los partidos de la pulsera`() {
        val matches = listOf(
            partido("2026-03-01", 3.0, FuenteDeDatos.RELOJ),
            partido("2026-03-08", 6.2, FuenteDeDatos.BAND),
            partido("2026-03-15", 3.1, FuenteDeDatos.RELOJ),
        )
        val delReloj = LigaMetrics.deFuente(matches, FuenteDeDatos.RELOJ)

        assertEquals(2, delReloj.size)
        assertTrue(delReloj.none { it.fuente == FuenteDeDatos.BAND })
        // Y al contrario: la curva de la pulsera tampoco se lleva los del reloj.
        assertEquals(1, LigaMetrics.deFuente(matches, FuenteDeDatos.BAND).size)
    }

    @Test
    fun `los de fuente desconocida van con los del reloj`() {
        // Decisión discutible y escrita a propósito: el historial anterior al campo se
        // midió con el reloj o se apuntó sobre esa misma escala, así que sacarlo de la
        // curva del reloj dejaría a casi todo el mundo con una evolución vacía.
        val matches = listOf(
            partido("2026-01-01", 2.8),
            partido("2026-03-01", 3.0, FuenteDeDatos.RELOJ),
            partido("2026-03-08", 6.2, FuenteDeDatos.BAND),
        )
        assertEquals(2, LigaMetrics.deFuente(matches, FuenteDeDatos.RELOJ).size)
    }

    @Test
    fun `la fuente dominante ignora los partidos sin nivel`() {
        // La fuente de un partido sin nivel no cambia nada de lo que se dibuja, así que
        // no puede decidir qué curva se enseña.
        val matches = listOf(
            partido("2026-03-01", null, FuenteDeDatos.BAND),
            partido("2026-03-02", null, FuenteDeDatos.BAND),
            partido("2026-03-03", 3.0, FuenteDeDatos.RELOJ),
        )
        assertEquals(FuenteDeDatos.RELOJ, LigaMetrics.fuenteDominante(matches))
    }

    @Test
    fun `sin niveles no hay fuente dominante`() {
        val matches = listOf(partido("2026-03-01", null), partido("2026-03-02", null))
        assertNull(LigaMetrics.fuenteDominante(matches))
    }

    @Test
    fun `la fuente viaja en el backup`() {
        val match = partido("2026-03-01", 3.4, FuenteDeDatos.BAND)
        val json = Json.encodeToString(LigaMatch.serializer(), match)
        val vuelta = Json.decodeFromString(LigaMatch.serializer(), json)

        assertTrue(json.contains("\"fuente\":\"band\""), json)
        assertEquals(FuenteDeDatos.BAND, vuelta.fuente)
    }
}
