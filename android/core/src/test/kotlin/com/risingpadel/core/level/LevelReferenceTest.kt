package com.risingpadel.core.level

import com.risingpadel.core.model.ShotType
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class LevelReferenceTest {

    private fun referencia(nivel: Float, derecha: Float, golpes: Int = 20) = ReferenciaNivel(
        nivelTecnico = nivel,
        velocidadPorTipo = mapOf(ShotType.FOREHAND.wireName to derecha),
        golpes = golpes,
    )

    @Test
    fun `con un solo nivel no hay recta que ajustar`() {
        val bandas = LevelReferenceCalibrator.bandas(
            listOf(referencia(3f, 60f), referencia(3f, 62f))
        )
        assertTrue(bandas.isEmpty(), "todas las referencias del mismo nivel no calibran nada")
    }

    @Test
    fun `dos jugadores de nivel distinto fijan la banda de ese golpe`() {
        // Un 3 pega su derecha a 60 y un 5 a 80: 10 km/h por nivel.
        val bandas = LevelReferenceCalibrator.bandas(
            listOf(referencia(3f, 60f), referencia(5f, 80f))
        )
        val derecha = bandas[ShotType.FOREHAND]
        assertTrue(derecha != null, "la derecha debería quedar calibrada")
        // Extrapolando la recta: nivel 1 = 40, nivel 7 = 100.
        assertEquals(40f, derecha!!.speedAtLevel1, 1f)
        assertEquals(100f, derecha.speedAtLevel7, 1f)
    }

    @Test
    fun `una tanda corta no cuenta como referencia`() {
        val bandas = LevelReferenceCalibrator.bandas(
            listOf(referencia(3f, 60f, golpes = 4), referencia(5f, 80f, golpes = 4))
        )
        assertTrue(bandas.isEmpty(), "con 4 golpes no se calibra el nivel de nadie")
    }

    @Test
    fun `si mas nivel no significa mas velocidad, ese golpe no se toca`() {
        // Un 5 que pega más flojo que un 3: o la referencia está mal o ese rasgo no
        // separa niveles en ese golpe. En cualquier caso, banda de fábrica.
        val bandas = LevelReferenceCalibrator.bandas(
            listOf(referencia(3f, 80f), referencia(5f, 60f))
        )
        assertTrue(bandas[ShotType.FOREHAND] == null)
    }

    @Test
    fun `solo se calibran los golpes con referencias, el resto sigue de fabrica`() {
        val bandas = LevelReferenceCalibrator.bandas(
            listOf(referencia(3f, 60f), referencia(5f, 80f))
        )
        assertTrue(bandas.containsKey(ShotType.FOREHAND))
        assertTrue(!bandas.containsKey(ShotType.SMASH), "sin tandas de smash no hay banda nueva")

        // Y la configuración resultante mezcla lo calibrado con lo de fábrica.
        val config = LevelConfig(bands = LevelConfig.DEFAULT_BANDS + bandas)
        assertEquals(
            LevelConfig.DEFAULT_BANDS[ShotType.SMASH]?.speedAtLevel7,
            config.bands[ShotType.SMASH]?.speedAtLevel7,
        )
        assertEquals(100f, config.bands[ShotType.FOREHAND]!!.speedAtLevel7, 1f)
    }
}
