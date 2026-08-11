package com.risingpadel.core.liga

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class RitmoDeTemporadaTest {

    private fun temporada(
        inicio: String = "2025-09-01",
        fin: String = "2026-06-30",
        objetivo: Int? = 20,
    ) = LigaTemporada(
        id = 1,
        nombre = "2025/26",
        fechaInicio = inicio,
        fechaFin = fin,
        objetivoPartidos = objetivo,
    )

    @Test
    fun `a mitad de temporada con la mitad jugada vas en hora`() {
        // 302 días de temporada; el 2026-01-30 han pasado 151, justo la mitad.
        val ritmo = RitmoDeTemporada.de(temporada(), jugados = 10, hoyISO = "2026-01-30")
        assertNotNull(ritmo)
        assertEquals(302, ritmo.diasTotales)
        assertEquals(151, ritmo.diasTranscurridos)
        assertEquals(151, ritmo.diasRestantes)
        assertEquals(10, ritmo.esperados)
        assertEquals(0, ritmo.diferencia)
    }

    @Test
    fun `ocho de veinte en octubre va sobrado y en mayo va tarde`() {
        // El mismo 8/20 dice cosas contrarias según cuánta temporada quede: es justo el
        // motivo de que la barra de la meta sola no valiera.
        val octubre = RitmoDeTemporada.de(temporada(), jugados = 8, hoyISO = "2025-10-15")!!
        val mayo = RitmoDeTemporada.de(temporada(), jugados = 8, hoyISO = "2026-05-15")!!
        assertTrue(octubre.diferencia > 0, "en octubre 8 partidos es ir por delante")
        assertTrue(mayo.diferencia < 0, "en mayo 8 partidos es ir por detrás")
    }

    @Test
    fun `cada cuantos dias toca jugar`() {
        // Quedan 151 días y faltan 10 partidos: uno cada 15,1 días.
        val ritmo = RitmoDeTemporada.de(temporada(), jugados = 10, hoyISO = "2026-01-30")!!
        assertEquals(15.1f, ritmo.cadaCuantosDias!!, 0.05f)
    }

    @Test
    fun `con la meta cumplida no se recomienda nada`() {
        val ritmo = RitmoDeTemporada.de(temporada(), jugados = 20, hoyISO = "2026-01-30")!!
        assertTrue(ritmo.cumplida)
        assertEquals(0, ritmo.partidosQueFaltan)
        // Recomendar un ritmo a quien ya llegó sería ruido.
        assertNull(ritmo.cadaCuantosDias)
    }

    @Test
    fun `acabada la temporada no se inventa un ritmo imposible`() {
        val ritmo = RitmoDeTemporada.de(temporada(), jugados = 12, hoyISO = "2026-08-01")!!
        assertTrue(ritmo.terminada)
        assertEquals(0, ritmo.diasRestantes)
        assertEquals(302, ritmo.diasTranscurridos)
        assertNull(ritmo.cadaCuantosDias)
    }

    @Test
    fun `antes de empezar todo esta por delante`() {
        val ritmo = RitmoDeTemporada.de(temporada(), jugados = 0, hoyISO = "2025-08-01")!!
        assertEquals(0, ritmo.diasTranscurridos)
        assertEquals(302, ritmo.diasRestantes)
        assertEquals(0f, ritmo.fraccionDelTiempo)
    }

    @Test
    fun `una temporada abierta con fin previsto ya tiene ritmo`() {
        // Es el caso normal: la temporada está en curso (fechaFin vacía) pero sabes
        // cuándo la piensas cerrar. Sin esto no habría cuenta atrás hasta el último día.
        val abierta = LigaTemporada(
            id = 1,
            nombre = "2025/26",
            fechaInicio = "2025-09-01",
            fechaFin = "",
            fechaFinPrevista = "2026-06-30",
            objetivoPartidos = 20,
        )
        val ritmo = RitmoDeTemporada.de(abierta, jugados = 10, hoyISO = "2026-01-30")
        assertNotNull(ritmo)
        assertEquals(302, ritmo.diasTotales)
        assertEquals(151, ritmo.diasRestantes)
        // Y sigue estando en curso: un fin previsto no la cierra.
        assertTrue(abierta.enCurso)
    }

    @Test
    fun `el fin previsto no decide qué partidos caen dentro`() {
        // Si el previsto filtrara, un partido jugado después de la fecha prevista pero
        // antes de cerrar la temporada desaparecería de sus estadísticas.
        val abierta = LigaTemporada(
            id = 1,
            fechaInicio = "2025-09-01",
            fechaFinPrevista = "2026-06-30",
        )
        assertTrue(abierta.contiene(LigaMatch(id = 1, fecha = "2026-07-15")))
    }

    @Test
    fun `sin fecha de fin o sin meta no hay ritmo que medir`() {
        assertNull(RitmoDeTemporada.de(temporada(fin = ""), 5, "2026-01-30"))
        assertNull(RitmoDeTemporada.de(temporada(objetivo = null), 5, "2026-01-30"))
        assertNull(RitmoDeTemporada.de(temporada(objetivo = 0), 5, "2026-01-30"))
    }

    @Test
    fun `una temporada con las fechas al reves no cuenta`() {
        assertNull(RitmoDeTemporada.de(temporada(inicio = "2026-06-30", fin = "2025-09-01"), 5, "2026-01-30"))
    }
}
