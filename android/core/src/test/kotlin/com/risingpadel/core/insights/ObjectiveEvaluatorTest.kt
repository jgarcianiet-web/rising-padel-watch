package com.risingpadel.core.insights

import com.risingpadel.core.model.ShotType
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ObjectiveEvaluatorTest {

    private val golpes = mapOf(
        ShotType.BANDEJA to 16,
        ShotType.VIBORA to 2,
        ShotType.SMASH to 7,
        ShotType.SERVE to 11,
        ShotType.FOREHAND_VOLLEY to 25,
        ShotType.BACKHAND_VOLLEY to 18,
    )

    private fun mide(objetivo: String) =
        ObjectiveEvaluator.evaluate(objetivo, golpes, totalShots = 120)

    @Test
    fun `hacer N bandejas se mide y cuenta como minimo`() {
        val medida = mide("Hacer 15 bandejas")
        assertEquals(ObjectiveMeasurement(target = 15, actual = 16, met = true), medida)
    }

    @Test
    fun `un minimo sin alcanzar sale como no cumplido`() {
        val medida = mide("Mínimo 3 víboras en el partido")
        assertEquals(ObjectiveMeasurement(target = 3, actual = 2, met = false), medida)
    }

    @Test
    fun `un maximo respeta la direccion`() {
        assertEquals(true, mide("Máximo 10 remates")?.met)
        assertEquals(false, mide("Como mucho 5 remates")?.met)
    }

    @Test
    fun `la volea suma los dos lados`() {
        assertEquals(43, mide("Dar 40 voleas")?.actual)
    }

    @Test
    fun `los golpes totales usan el total de la sesion`() {
        val medida = mide("Llegar a 100 golpes")
        assertEquals(120, medida?.actual)
        assertTrue(medida!!.met)
    }

    @Test
    fun `hablar de puntos no se mide aunque nombre un golpe`() {
        // El reloj cuenta bandejas, pero no sabe quién ganó el punto: medir mentiría.
        assertNull(mide("Ganar al menos 2 puntos con bandeja"))
    }

    @Test
    fun `errores y porcentajes quedan fuera del alcance`() {
        assertNull(mide("Menos de 5 errores no forzados"))
        assertNull(mide("Meter el 80% de primeros saques"))
    }

    @Test
    fun `la colocacion del saque no es medible`() {
        assertNull(mide("Variar el saque: mínimo 3 saques a la T"))
    }

    @Test
    fun `sin numero no hay medida`() {
        assertNull(mide("Subir a la red tras cada globo ofensivo"))
    }
}
