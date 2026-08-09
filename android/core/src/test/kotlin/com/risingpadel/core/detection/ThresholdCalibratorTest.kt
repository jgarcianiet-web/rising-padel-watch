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
        alto: Float = 0f,
    ) = ShotFeatures(
        sweptAngleDeg = barrido,
        peakGyroRadS = pico,
        elevationDeg = alto,
        axialRotationRadS = axial,
        swingDurationMs = 250,
        peakElevationDeg = alto,
        prepElevationDeg = prep,
    )

    /** Una tanda de n golpes de un tipo, con pequeñas variaciones alrededor del centro. */
    private fun tanda(
        tipo: ShotType, n: Int, axial: Float, pico: Float, prep: Float?, alto: Float = 0f
    ): List<Pair<ShotType, ShotFeatures>> = (0 until n).map { i ->
        val d = (i - n / 2) * 0.1f
        tipo to rasgos(axial + d, pico + d, prep?.plus(d * 5), alto = alto + d)
    }

    @Test
    fun `sin material suficiente no se calibra nada`() {
        val pocas = tanda(ShotType.VIBORA, 3, axial = 5f, pico = 13f, prep = 60f) +
            tanda(ShotType.BANDEJA, 3, axial = 2f, pico = 12f, prep = 60f)
        val resultado = ThresholdCalibrator.calibrar(pocas)
        assertTrue(resultado.calibracion.vacia, "3 por familia no puede mover un umbral")
    }

    @Test
    fun `el umbral de vibora cae entre las alturas de golpeo del jugador`() {
        // Las dos empiezan igual; la víbora se golpea más baja. Este jugador impacta
        // sus bandejas a +30 y sus víboras a +5.
        val etiquetados = tanda(ShotType.VIBORA, 8, axial = -2f, pico = 13f, prep = 60f, alto = 5f) +
            tanda(ShotType.BANDEJA, 8, axial = -2f, pico = 12f, prep = 60f, alto = 30f)
        val calibracion = ThresholdCalibrator.calibrar(etiquetados).calibracion
        val umbral = assertNotNull(calibracion.viboraElevationDeg)
        assertTrue(umbral in 5f..30f, "el umbral debería caer entre las dos alturas: $umbral")
        assertEquals(16, calibracion.muestras)
    }

    @Test
    fun `familias solapadas dejan el umbral de fabrica`() {
        // Bandejas y víboras golpeadas a la misma altura: ese rasgo no separa a este
        // jugador y no se toca nada.
        val etiquetados = tanda(ShotType.VIBORA, 8, axial = 3f, pico = 13f, prep = 60f, alto = 20f) +
            tanda(ShotType.BANDEJA, 8, axial = 3f, pico = 13f, prep = 60f, alto = 20f)
        assertNull(ThresholdCalibrator.calibrar(etiquetados).calibracion.viboraElevationDeg)
    }

    @Test
    fun `la calibracion mejora el acierto sobre las propias tandas`() {
        // Un jugador que golpea sus víboras muy bajas (+2, con el umbral de fábrica en
        // 18: de fábrica ya salen bien) y sus remates flojos, picando 14 cuando el
        // umbral de fábrica pide 16.
        val etiquetados =
            tanda(ShotType.VIBORA, 8, axial = -3f, pico = 10f, prep = 60f, alto = 2f) +
                tanda(ShotType.BANDEJA, 8, axial = 0.5f, pico = 9f, prep = 60f, alto = 30f) +
                tanda(ShotType.SMASH, 8, axial = -1f, pico = 14f, prep = 60f, alto = 10f)

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
        // Alturas imposibles: el umbral resultante se acota al rango sensato en vez de
        // irse a 200° y dejar el detector sin poder llamar bandeja a nada.
        val etiquetados = tanda(ShotType.VIBORA, 8, axial = -2f, pico = 13f, prep = 60f, alto = 150f) +
            tanda(ShotType.BANDEJA, 8, axial = -2f, pico = 12f, prep = 60f, alto = 300f)
        val umbral = ThresholdCalibrator.calibrar(etiquetados).calibracion.viboraElevationDeg
        assertNotNull(umbral)
        assertTrue(umbral <= 45f, "el umbral debe quedar acotado: $umbral")
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

    // --- el signo del eje, decidido por las etiquetas ---

    @Test
    fun `si los golpes altos se preparan mas abajo que los bajos, el eje esta invertido`() {
        // Los números de pista (ago 2026): bandejas preparando a -45 y voleas a -28.
        // Un golpe alto NO se arma más abajo que una volea; el eje lee al revés.
        val etiquetados =
            List(8) { ShotType.BANDEJA to rasgos(axial = 3f, pico = 12f, prep = -45f) } +
            List(8) { ShotType.BACKHAND_VOLLEY to rasgos(axial = 1f, pico = 8f, prep = -28f) }

        val calibracion = ThresholdCalibrator.calibrar(etiquetados).calibracion

        assertEquals(true, calibracion.ejeDeElevacionInvertido)
    }

    @Test
    fun `con el eje bien puesto no se toca nada`() {
        val etiquetados =
            List(8) { ShotType.BANDEJA to rasgos(axial = 3f, pico = 12f, prep = 55f) } +
            List(8) { ShotType.BACKHAND_VOLLEY to rasgos(axial = 1f, pico = 8f, prep = 10f) }

        assertEquals(false, ThresholdCalibrator.calibrar(etiquetados).calibracion.ejeDeElevacionInvertido)
    }

    @Test
    fun `una diferencia pequena no basta para girar el eje`() {
        // Cinco grados entre familias puede ser ruido, y girar el eje por ruido rompería
        // un detector que a lo mejor estaba bien.
        val etiquetados =
            List(8) { ShotType.BANDEJA to rasgos(axial = 3f, pico = 12f, prep = 20f) } +
            List(8) { ShotType.BACKHAND_VOLLEY to rasgos(axial = 1f, pico = 8f, prep = 25f) }

        assertNull(ThresholdCalibrator.calibrar(etiquetados).calibracion.ejeDeElevacionInvertido)
    }

    @Test
    fun `sin tandas suficientes no se decide el signo`() {
        val etiquetados =
            List(2) { ShotType.BANDEJA to rasgos(axial = 3f, pico = 12f, prep = -45f) } +
            List(2) { ShotType.BACKHAND_VOLLEY to rasgos(axial = 1f, pico = 8f, prep = -20f) }

        assertNull(ThresholdCalibrator.calibrar(etiquetados).calibracion.ejeDeElevacionInvertido)
    }

    @Test
    fun `el eje invertido gira la elevacion que mide el clasificador`() {
        val calibracion = DetectorCalibration(ejeDeElevacionInvertido = true)
        val config = DetectorConfig.DEFAULT.aplicando(calibracion)

        assertEquals(-DetectorConfig.DEFAULT.forearmAxis.y, config.forearmAxis.y, 0.001f)
    }
}
