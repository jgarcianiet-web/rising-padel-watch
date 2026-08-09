package com.risingpadel.core.sync

import com.risingpadel.core.detection.DescartesDelDetector
import com.risingpadel.core.model.ShotType
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class MandoDeTandaTest {

    @Test
    fun `la orden va y vuelve entera`() {
        val orden = OrdenDeTanda(
            accion = AccionDeTanda.INICIAR,
            etiqueta = ShotType.BANDEJA,
            creadoEpochMs = 1_700_000_000_000,
        )
        assertEquals(orden, OrdenDeTanda.decode(orden.encode()))
    }

    @Test
    fun `una orden basura no revienta el reloj`() {
        assertNull(OrdenDeTanda.decode("{esto no es json"))
        assertNull(EstadoDeTanda.decode(""))
    }

    @Test
    fun `un campo nuevo del móvil no rompe a un reloj viejo`() {
        val conCampoDeMas = """{"accion":"iniciar","etiqueta":"SMASH","inventado":42}"""
        val orden = OrdenDeTanda.decode(conCampoDeMas)
        assertEquals(AccionDeTanda.INICIAR, orden?.accion)
        assertEquals(ShotType.SMASH, orden?.etiqueta)
    }

    @Test
    fun `una orden de arrancar caduca a los tres minutos`() {
        val orden = OrdenDeTanda(AccionDeTanda.INICIAR, ShotType.FOREHAND, creadoEpochMs = 1_000_000)
        assertTrue(orden.vigente(1_000_000 + 2 * 60_000))
        assertFalse(orden.vigente(1_000_000 + 4 * 60_000))
    }

    @Test
    fun `preguntar por el estado nunca caduca`() {
        // No cambia nada en el reloj, así que obedecerla tarde no puede sorprender a nadie.
        val orden = OrdenDeTanda(AccionDeTanda.ESTADO, creadoEpochMs = 1_000_000)
        assertTrue(orden.vigente(1_000_000 + 60 * 60_000))
    }

    @Test
    fun `una orden sin fecha se obedece, que viene de una versión vieja`() {
        val orden = OrdenDeTanda(AccionDeTanda.PARAR)
        assertTrue(orden.vigente(9_999_999_999))
    }

    @Test
    fun `el estado lleva los descartes hasta el móvil`() {
        val estado = EstadoDeTanda(
            grabando = true,
            etiqueta = ShotType.VIBORA,
            capturadosEnTanda = 12,
            guardadosEnTotal = 340,
            kilobytes = 2_400,
            alias = "javi",
            nivel = 4,
            sensoresPuedenPararse = false,
            motivo = null,
            descartes = DescartesDelDetector(swingSinImpacto = 7, amago = 2),
        )
        val vuelta = EstadoDeTanda.decode(estado.encode())
        assertEquals(estado, vuelta)
        assertEquals(9, vuelta?.descartes?.total)
    }
}
