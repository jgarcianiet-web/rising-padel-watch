package com.risingpadel.core.detection

import com.risingpadel.core.model.ShotFeatures
import com.risingpadel.core.model.ShotType
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ThresholdCalibratorTest {

    private fun rasgos(
        axial: Float,
        pico: Float,
        prep: Float?,
        barrido: Float = 160f,
    ) = ShotFeatures(
        sweptAngleDeg = barrido,
        peakGyroRadS = pico,
        elevationDeg = 0f,
        axialRotationRadS = axial,
        swingDurationMs = 250,
        peakElevationDeg = 0f,
        prepElevationDeg = prep,
    )

    /** Una tanda de n golpes de un tipo, con pequeñas variaciones alrededor del centro. */
    private fun tanda(
        tipo: ShotType, n: Int, axial: Float, pico: Float, prep: Float?
    ): List<Pair<ShotType, ShotFeatures>> = (0 until n).map { i ->
        val d = (i - n / 2) * 0.1f
        tipo to rasgos(axial + d, pico + d, prep?.plus(d * 5))
    }

    @Test
    fun `sin material suficiente no se calibra nada`() {
        val pocas = tanda(ShotType.VIBORA, 3, axial = 5f, pico = 13f, prep = 60f) +
            tanda(ShotType.BANDEJA, 3, axial = 2f, pico = 12f, prep = 60f)
        val resultado = ThresholdCalibrator.calibrar(pocas)
        assertTrue(resultado.calibracion.vacia, "3 por familia no puede mover un umbral")
    }

    @Test
    fun `el umbral de vibora cae entre las medianas de las tandas del jugador`() {
        // El caso real: víboras de |4-5| y bandejas de |2|, con el umbral de fábrica en
        // 4 — este jugador necesita el suyo, no el de catálogo.
        val etiquetados = tanda(ShotType.VIBORA, 8, axial = -5f, pico = 13f, prep = 60f) +
            tanda(ShotType.BANDEJA, 8, axial = 1.5f, pico = 12f, prep = 60f)
        val calibracion = ThresholdCalibrator.calibrar(etiquetados).calibracion
        val umbral = assertNotNull(calibracion.viboraAxialRadS)
        assertTrue(umbral in 2f..5f, "el umbral debería caer entre 1.5 y 5: $umbral")
        assertEquals(16, calibracion.muestras)
    }

    @Test
    fun `familias solapadas dejan el umbral de fabrica`() {
        // Bandejas y víboras con el mismo efecto: ese rasgo no separa a este jugador.
        val etiquetados = tanda(ShotType.VIBORA, 8, axial = 3f, pico = 13f, prep = 60f) +
            tanda(ShotType.BANDEJA, 8, axial = 3f, pico = 13f, prep = 60f)
        assertNull(ThresholdCalibrator.calibrar(etiquetados).calibracion.viboraAxialRadS)
    }

    @Test
    fun `la calibracion mejora el acierto sobre las propias tandas`() {
        // Un jugador de muñeca suave: sus víboras llevan |3| de efecto (el umbral de
        // fábrica es 4, así que de fábrica salen todas como bandeja) y sus remates
        // pican 12 (el umbral de fábrica es 16: ninguno llega).
        val etiquetados =
            tanda(ShotType.VIBORA, 8, axial = -3f, pico = 10f, prep = 60f) +
                tanda(ShotType.BANDEJA, 8, axial = 0.5f, pico = 9f, prep = 60f) +
                tanda(ShotType.SMASH, 8, axial = -1f, pico = 14f, prep = 60f)

        val resultado = ThresholdCalibrator.calibrar(etiquetados)
        assertTrue(
            resultado.aciertoDespues > resultado.aciertoAntes,
            "antes ${resultado.aciertoAntes}, después ${resultado.aciertoDespues}",
        )
        // Y el detalle por tipo sirve para decirle al jugador qué tandas le faltan.
        assertEquals(8, resultado.porTipo[ShotType.SMASH])
    }

    @Test
    fun `una tanda absurda no puede dejar el detector inservible`() {
        // Etiquetas cruzadas a propósito: víboras sin efecto y bandejas con muchísimo.
        // El umbral resultante se acota al rango sensato en vez de irse a 40.
        val etiquetados = tanda(ShotType.VIBORA, 8, axial = 30f, pico = 13f, prep = 60f) +
            tanda(ShotType.BANDEJA, 8, axial = 20f, pico = 12f, prep = 60f)
        val umbral = ThresholdCalibrator.calibrar(etiquetados).calibracion.viboraAxialRadS
        assertNotNull(umbral)
        assertTrue(umbral <= 12f, "el umbral debe quedar acotado: $umbral")
    }

    @Test
    fun `la elevacion de preparacion se calibra separando altos de bajos`() {
        val etiquetados =
            tanda(ShotType.SMASH, 6, axial = -1f, pico = 18f, prep = 70f) +
                tanda(ShotType.VIBORA, 6, axial = -5f, pico = 13f, prep = 65f) +
                tanda(ShotType.FOREHAND, 6, axial = 9f, pico = 15f, prep = 5f) +
                tanda(ShotType.BACKHAND, 6, axial = -9f, pico = 14f, prep = 0f)
        val prep = ThresholdCalibrator.calibrar(etiquetados).calibracion.prepOverheadElevationDeg
        assertNotNull(prep)
        assertTrue(prep in 20f..70f, "prep fuera de rango: $prep")
    }

    @Test
    fun `sin elevacion de preparacion en las muestras ese umbral no se toca`() {
        // Tandas viejas, grabadas antes de que el rasgo existiera.
        val etiquetados = tanda(ShotType.SMASH, 8, axial = -1f, pico = 18f, prep = null) +
            tanda(ShotType.FOREHAND, 8, axial = 9f, pico = 15f, prep = null)
        assertNull(
            ThresholdCalibrator.calibrar(etiquetados).calibracion.prepOverheadElevationDeg
        )
    }
}
