package com.risingpadel.core.liga

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ObjetivoDeGolpeTest {

    private fun partido(fecha: String, vararg golpes: Pair<String, Double>) = LigaMatch(
        id = fecha.replace("-", "").toLong(),
        fecha = fecha,
        golpesSesion = golpes.map { LigaGolpeSesion(it.first, it.second) },
    )

    private val bandeja = ObjetivoDeGolpe("Bandeja", notaInicial = 2.6, notaObjetivo = 3.5)

    @Test
    fun `la nota actual es la media de los ultimos cinco, no la del ultimo`() {
        // Seis partidos: el primero no debe contar, y un mal día al final no puede
        // hundir el objetivo él solo.
        val partidos = listOf(
            partido("2026-09-01", "Bandeja" to 2.0),
            partido("2026-09-02", "Bandeja" to 3.0),
            partido("2026-09-03", "Bandeja" to 3.0),
            partido("2026-09-04", "Bandeja" to 3.0),
            partido("2026-09-05", "Bandeja" to 3.0),
            partido("2026-09-06", "Bandeja" to 3.0),
        )
        val p = ProgresoDeGolpes.progreso(bandeja, partidos)
        assertEquals(3.0, p.notaActual!!, 0.001)
        assertEquals(5, p.ultimas.size)
    }

    @Test
    fun `el porcentaje mide el camino recorrido entre inicio y objetivo`() {
        // De 2,6 a 3,5 hay 0,9. Estar en 3,05 es justo la mitad.
        val partidos = List(5) { partido("2026-09-0${it + 1}", "Bandeja" to 3.05) }
        val p = ProgresoDeGolpes.progreso(bandeja, partidos)
        assertEquals(50, p.porcentaje)
        assertEquals(0.45, p.avance, 0.001)
        assertTrue(!p.cumplido)
    }

    @Test
    fun `llegar al objetivo lo da por cumplido`() {
        val partidos = List(5) { partido("2026-09-0${it + 1}", "Bandeja" to 3.6) }
        val p = ProgresoDeGolpes.progreso(bandeja, partidos)
        assertTrue(p.cumplido)
        assertEquals(100, p.porcentaje)
    }

    @Test
    fun `retroceder no da porcentaje negativo`() {
        val partidos = List(5) { partido("2026-09-0${it + 1}", "Bandeja" to 2.0) }
        val p = ProgresoDeGolpes.progreso(bandeja, partidos)
        assertEquals(0, p.porcentaje)
        // El avance sí es negativo: la barra no baja de cero pero el número no miente.
        assertTrue(p.avance < 0)
    }

    @Test
    fun `un partido sin ese golpe no cuenta como cero`() {
        // Tres partidos sin dar una bandeja no significan que la bandeja haya
        // empeorado: significan que no hay dato. Rellenarlo con cero se inventaría una
        // regresión que no ha pasado.
        val partidos = listOf(
            partido("2026-09-01", "Bandeja" to 3.2),
            partido("2026-09-02", "Derecha" to 4.0),
            partido("2026-09-03", "Derecha" to 4.0),
        )
        val p = ProgresoDeGolpes.progreso(bandeja, partidos)
        assertEquals(3.2, p.notaActual!!, 0.001)
        assertEquals(1, p.ultimas.size)
    }

    @Test
    fun `sin ningun dato del golpe el objetivo no tiene nota actual`() {
        val p = ProgresoDeGolpes.progreso(bandeja, listOf(partido("2026-09-01", "Derecha" to 4.0)))
        assertNull(p.notaActual)
        assertEquals(0, p.porcentaje)
        assertTrue(!p.cumplido)
    }

    @Test
    fun `la temporada solo mira sus propios partidos`() {
        val temporada = LigaTemporada(
            id = 1,
            nombre = "Reto hacia nivel 4",
            fechaInicio = "2026-10-01",
            fechaFinPrevista = "2026-12-31",
            objetivosDeGolpe = listOf(bandeja),
        )
        val partidos = listOf(
            // De antes de la temporada: no cuenta aunque sea el mejor.
            partido("2026-09-20", "Bandeja" to 6.0),
            partido("2026-10-05", "Bandeja" to 3.0),
            partido("2026-10-12", "Bandeja" to 3.0),
        )
        val progresos = ProgresoDeGolpes.deTemporada(temporada, partidos)
        assertEquals(1, progresos.size)
        assertEquals(3.0, progresos[0].notaActual!!, 0.001)
    }

    @Test
    fun `el area de mejora es donde menos se avanza, no donde peor se puntua`() {
        // El revés puntúa más bajo en términos absolutos, pero ya lleva medio camino;
        // la volea está atascada. Lo que bloquea al jugador es la volea.
        val reves = ObjetivoDeGolpe("Revés", notaInicial = 2.0, notaObjetivo = 3.0)
        val volea = ObjetivoDeGolpe("Volea de derecha", notaInicial = 3.0, notaObjetivo = 4.0)
        val partidos = List(5) {
            partido("2026-09-0${it + 1}", "Revés" to 2.5, "Volea de derecha" to 3.05)
        }
        val progresos = listOf(reves, volea).map { ProgresoDeGolpes.progreso(it, partidos) }

        val area = ProgresoDeGolpes.principalAreaDeMejora(progresos)
        assertEquals("Volea de derecha", area!!.objetivo.golpe)
    }

    @Test
    fun `un objetivo cumplido no puede ser el area de mejora`() {
        val hecho = ObjetivoDeGolpe("Remate", notaInicial = 2.0, notaObjetivo = 3.0)
        val partidos = List(5) { partido("2026-09-0${it + 1}", "Remate" to 5.0) }
        val progresos = listOf(ProgresoDeGolpes.progreso(hecho, partidos))
        assertNull(ProgresoDeGolpes.principalAreaDeMejora(progresos))
    }

    @Test
    fun `las ventanas de 5 y de 20 dan la tendencia corta y la de fondo`() {
        // Un jugador que ha mejorado: sus últimos cinco son mejores que sus últimos
        // veinte, y esa diferencia es justo la comparativa que pide el producto.
        val partidos = (1..20).map { i ->
            partido("2026-09-%02d".format(i), "Bandeja" to 2.0 + i * 0.1)
        }
        val corta = ProgresoDeGolpes.media("Bandeja", partidos, ProgresoDeGolpes.VENTANA)!!
        val larga = ProgresoDeGolpes.media("Bandeja", partidos, ProgresoDeGolpes.VENTANA_LARGA)!!
        assertTrue(corta > larga, "corta $corta, larga $larga")
    }

    @Test
    fun `el nombre del golpe no distingue mayusculas`() {
        // Los partidos importados de la app Expo traen los nombres como los escribió
        // quien los metió a mano.
        val partidos = List(5) { partido("2026-09-0${it + 1}", "bandeja" to 3.5) }
        assertTrue(ProgresoDeGolpes.progreso(bandeja, partidos).cumplido)
    }

    @Test
    fun `un objetivo que no pide subir nada ya esta cumplido y no divide por cero`() {
        val plano = ObjetivoDeGolpe("Saque", notaInicial = 3.0, notaObjetivo = 3.0)
        val partidos = List(5) { partido("2026-09-0${it + 1}", "Saque" to 3.0) }
        val p = ProgresoDeGolpes.progreso(plano, partidos)
        assertEquals(100, p.porcentaje)
        assertTrue(p.cumplido)
    }
}
