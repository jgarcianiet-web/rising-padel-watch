package com.risingpadel.core.analytics

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class CalendarioDeActividadTest {

    private fun dia(fecha: String, golpes: Int = 200, minutos: Int = 75) =
        DiaDeActividad(fecha, sesiones = 1, golpes = golpes, minutos = minutos)

    @Test
    fun `la cuadricula siempre tiene semanas enteras`() {
        // 2026-08-11 es martes: la última columna se completa hasta el domingo 16.
        val calendario = CalendarioDeActividad.de(emptyList(), hastaISO = "2026-08-11", semanas = 4)
        assertNotNull(calendario)
        assertEquals(4, calendario.semanas.size)
        assertTrue(calendario.semanas.all { it.size == 7 })
        assertEquals("2026-08-16", calendario.semanas.last().last().fechaISO)
        assertEquals("2026-07-20", calendario.semanas.first().first().fechaISO)
    }

    @Test
    fun `las semanas empiezan en lunes`() {
        val calendario = CalendarioDeActividad.de(emptyList(), hastaISO = "2026-08-11", semanas = 2)!!
        for (semana in calendario.semanas) {
            assertEquals(
                0,
                com.risingpadel.core.liga.Fechas.diaDeLaSemana(semana.first().fechaISO),
                "la semana no empieza en lunes: ${semana.first().fechaISO}",
            )
        }
    }

    @Test
    fun `un dia sin jugar es un cero, no un hueco`() {
        val calendario = CalendarioDeActividad.de(
            listOf(dia("2026-08-10")), hastaISO = "2026-08-11", semanas = 2,
        )!!
        val todos = calendario.semanas.flatten()
        assertEquals(14, todos.size)
        assertEquals(1, todos.count { it.jugado })
        assertFalse(todos.first { it.fechaISO == "2026-08-11" }.jugado)
    }

    @Test
    fun `la racha en curso perdona el dia de hoy`() {
        // Jugó lunes y domingo pero hoy (martes) todavía no: a las nueve de la mañana
        // nadie ha jugado, y cortarle la racha por eso sería castigarle por madrugar.
        val calendario = CalendarioDeActividad.de(
            listOf(dia("2026-08-09"), dia("2026-08-10")),
            hastaISO = "2026-08-11",
            semanas = 3,
        )!!
        assertEquals(2, calendario.rachaActual)
    }

    @Test
    fun `dos dias sin jugar rompen la racha`() {
        val calendario = CalendarioDeActividad.de(
            listOf(dia("2026-08-08"), dia("2026-08-09")),
            hastaISO = "2026-08-11",
            semanas = 3,
        )!!
        assertEquals(0, calendario.rachaActual)
        assertEquals(2, calendario.mejorRacha)
    }

    @Test
    fun `la mejor racha mira todo el periodo`() {
        val calendario = CalendarioDeActividad.de(
            listOf(
                dia("2026-07-21"), dia("2026-07-22"), dia("2026-07-23"), dia("2026-07-24"),
                dia("2026-08-10"),
            ),
            hastaISO = "2026-08-11",
            semanas = 4,
        )!!
        assertEquals(4, calendario.mejorRacha)
        assertEquals(1, calendario.rachaActual)
        assertEquals(5, calendario.diasJugados)
    }

    @Test
    fun `los dias del futuro no cuentan como no jugados`() {
        // El resto de la semana en curso está en la cuadrícula para no cambiarle la
        // forma cada día, pero no puede contar contra las medias ni contra la racha.
        val calendario = CalendarioDeActividad.de(
            listOf(dia("2026-08-11")), hastaISO = "2026-08-11", semanas = 1,
        )!!
        assertEquals(1, calendario.rachaActual)
        assertEquals(1, calendario.diasJugados)
    }

    @Test
    fun `el maximo de golpes escala el color`() {
        val calendario = CalendarioDeActividad.de(
            listOf(dia("2026-08-10", golpes = 120), dia("2026-08-11", golpes = 480)),
            hastaISO = "2026-08-11",
            semanas = 2,
        )!!
        assertEquals(480, calendario.maxGolpes)
    }

    @Test
    fun `sin nada jugado no hay datos`() {
        val calendario = CalendarioDeActividad.de(emptyList(), hastaISO = "2026-08-11")!!
        assertFalse(calendario.hayDatos)
        assertEquals(0, calendario.rachaActual)
        assertEquals(0f, calendario.diasPorSemana)
    }
}
