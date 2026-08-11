package com.risingpadel.core.liga

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class FechasTest {

    @Test
    fun `el dia cero es el uno de enero del setenta`() {
        assertEquals(0, Fechas.diasDesdeEpoca("1970-01-01"))
        assertEquals("1970-01-01", Fechas.isoDesdeDias(0))
    }

    @Test
    fun `ida y vuelta por unas cuantas fechas`() {
        val fechas = listOf(
            "1969-12-31", "1999-12-31", "2000-01-01", "2000-02-29",
            "2026-08-11", "2100-03-01", "2400-02-29",
        )
        for (iso in fechas) {
            val dias = Fechas.diasDesdeEpoca(iso)!!
            assertEquals(iso, Fechas.isoDesdeDias(dias), "no vuelve igual: $iso")
        }
    }

    @Test
    fun `mil novecientos es bisiesto en el calendario juliano pero no en el nuestro`() {
        // 1900 no fue bisiesto (divisible por 100 y no por 400): del 28 de febrero se
        // pasa al 1 de marzo. Es el caso que se le escapa a cualquier atajo de bisiestos.
        assertEquals(1, Fechas.diasEntre("1900-02-28", "1900-03-01"))
        // 2000 sí lo fue (divisible por 400).
        assertEquals(2, Fechas.diasEntre("2000-02-28", "2000-03-01"))
    }

    @Test
    fun `una temporada de septiembre a junio dura lo que dura`() {
        assertEquals(302, Fechas.diasEntre("2025-09-01", "2026-06-30"))
    }

    @Test
    fun `restar al reves da negativo`() {
        assertEquals(-10, Fechas.diasEntre("2026-01-11", "2026-01-01"))
    }

    @Test
    fun `el lunes es el dia cero de la semana`() {
        // 2026-08-10 fue lunes.
        assertEquals(0, Fechas.diaDeLaSemana("2026-08-10"))
        assertEquals(1, Fechas.diaDeLaSemana("2026-08-11"))
        assertEquals(6, Fechas.diaDeLaSemana("2026-08-16"))
        // Y antes de la época, donde el módulo de un negativo muerde.
        assertEquals(3, Fechas.diaDeLaSemana("1970-01-01"))
        assertEquals(2, Fechas.diaDeLaSemana("1969-12-31"))
    }

    @Test
    fun `una cadena que no es fecha no revienta`() {
        assertNull(Fechas.diasDesdeEpoca(""))
        assertNull(Fechas.diasDesdeEpoca("ayer"))
        assertNull(Fechas.diasDesdeEpoca("2026-13-01"))
        assertNull(Fechas.diasEntre("2026-01-01", "nunca"))
    }
}
