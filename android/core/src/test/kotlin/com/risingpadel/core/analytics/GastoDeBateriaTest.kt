package com.risingpadel.core.analytics

import com.risingpadel.core.model.BatteryUse
import com.risingpadel.core.model.PadelSession
import com.risingpadel.core.model.Platform
import com.risingpadel.core.model.PlayerProfile
import com.risingpadel.core.model.SourceInfo
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

class GastoDeBateriaTest {

    private var siguiente = 0

    private fun sesion(minutos: Int, de: Int?, a: Int? = null): PadelSession {
        siguiente++
        return PadelSession(
            sessionId = "s$siguiente",
            source = SourceInfo(Platform.WATCHOS, "Watch", "1.0"),
            startedAtEpochMs = 0,
            endedAtEpochMs = minutos * 60_000L,
            profile = PlayerProfile(),
            shots = emptyList(),
            battery = if (de == null || a == null) null else BatteryUse(de, a),
        )
    }

    @Test
    fun `sin sesiones con bateria no hay nada que decir`() {
        assertNull(GastoDeBateria.de(listOf(sesion(60, null))))
    }

    @Test
    fun `con una sola sesion no se promedia`() {
        assertNull(
            GastoDeBateria.de(listOf(sesion(60, 90, 80))),
            "un día no es una medida",
        )
    }

    @Test
    fun `dos horas de juego y veinte puntos son diez por hora`() {
        val gasto = GastoDeBateria.de(
            listOf(sesion(60, 90, 80), sesion(60, 80, 70))
        )
        assertNotNull(gasto)
        assertEquals(10f, gasto.porHora, 0.1f)
        assertEquals(2, gasto.sesiones)
        assertEquals(2f, gasto.horas, 0.01f)
    }

    @Test
    fun `las sesiones cortas no cuentan`() {
        // 15 minutos y 1 punto darían un 4%/h que es puro redondeo del indicador.
        assertNull(
            GastoDeBateria.de(listOf(sesion(15, 90, 89), sesion(15, 89, 88)))
        )
    }

    @Test
    fun `una sesion con el reloj cargando se descarta`() {
        val gasto = GastoDeBateria.de(
            listOf(
                sesion(60, 90, 80),
                sesion(60, 80, 70),
                // Cargando: subió del 40 al 95. No es "gastó poco", es que no se midió.
                sesion(60, 40, 95),
            )
        )
        assertNotNull(gasto)
        assertEquals(2, gasto.sesiones)
        assertEquals(10f, gasto.porHora, 0.1f)
    }

    @Test
    fun `una sesion sin dato de bateria no cuenta como que gasto cero`() {
        val gasto = GastoDeBateria.de(
            listOf(sesion(60, 90, 80), sesion(60, 80, 70), sesion(60, null))
        )
        assertNotNull(gasto)
        assertEquals(2, gasto.sesiones)
        assertEquals(10f, gasto.porHora, 0.1f)
    }

    @Test
    fun `una sesion larga pesa mas que una corta en la media`() {
        // 3 h gastando 30 (10%/h) y 0,5 h gastando 10 (20%/h). Promediando ritmos
        // saldría 15%/h; lo correcto es 40 puntos entre 3,5 h = 11,4%/h.
        val gasto = GastoDeBateria.de(
            listOf(sesion(180, 90, 60), sesion(30, 60, 50))
        )
        assertNotNull(gasto)
        assertEquals(11.4f, gasto.porHora, 0.2f)
    }

    @Test
    fun `la autonomia sale de dividir cien entre el ritmo`() {
        val gasto = GastoDeBateria.de(
            listOf(sesion(60, 90, 80), sesion(60, 80, 70))
        )
        assertNotNull(gasto)
        assertEquals(10f, gasto.horasDeAutonomia, 0.1f)
    }

    @Test
    fun `un consumo de cero es una medida valida, no un dato roto`() {
        val gasto = GastoDeBateria.de(
            listOf(sesion(60, 90, 90), sesion(60, 90, 80))
        )
        assertNotNull(gasto)
        assertEquals(2, gasto.sesiones)
        assertEquals(5f, gasto.porHora, 0.1f)
    }
}
