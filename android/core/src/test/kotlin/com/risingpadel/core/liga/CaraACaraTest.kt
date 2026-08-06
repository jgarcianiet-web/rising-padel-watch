package com.risingpadel.core.liga

import kotlin.test.Test
import kotlin.test.assertEquals

class CaraACaraTest {

    private fun partido(
        id: Long,
        fecha: String,
        resultado: String,
        rivales: String? = null,
        companero: String = "",
    ) = LigaMatch(
        id = id, fecha = fecha, tipo = "competitivo", resultado = resultado,
        rivales = rivales, companero = companero,
    )

    @Test
    fun `agrupa por rival aunque cambie la grafia y ordena por partidos`() {
        val stats = LigaMetrics.caraACara(
            listOf(
                partido(1, "2026-01-01", "victoria", rivales = "Juan y Pedro"),
                partido(2, "2026-01-08", "derrota", rivales = "juan, Marta"),
                partido(3, "2026-01-15", "victoria", rivales = "JUAN"),
            )
        )
        assertEquals("Juan", stats.first().nombre) // la grafía de la primera vez
        assertEquals(3, stats.first().partidos)
        assertEquals(2, stats.first().victorias)
        assertEquals(66, stats.first().pctVictorias)
        // Los últimos en orden cronológico: V, D, V.
        assertEquals(listOf(true, false, true), stats.first().ultimos)
        // Pedro y Marta, un partido cada uno, en orden alfabético.
        assertEquals(listOf("Marta", "Pedro"), stats.drop(1).map { it.nombre })
    }

    @Test
    fun `la pareja sale de companero y los partidos sin rivales no cuentan`() {
        val stats = LigaMetrics.conPareja(
            listOf(
                partido(1, "2026-01-01", "victoria", companero = "Marta"),
                partido(2, "2026-01-08", "victoria", companero = "Marta"),
                partido(3, "2026-01-15", "derrota"), // sin pareja: no aparece
            )
        )
        assertEquals(1, stats.size)
        assertEquals(100, stats.first().pctVictorias)
        // Y sin ningún rival apuntado, el cara a cara queda vacío, no inventa filas.
        assertEquals(
            emptyList(),
            LigaMetrics.caraACara(listOf(partido(3, "2026-01-15", "derrota"))),
        )
    }
}
