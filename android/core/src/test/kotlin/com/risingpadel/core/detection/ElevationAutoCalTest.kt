package com.risingpadel.core.detection

import com.risingpadel.core.MotionFixtures
import com.risingpadel.core.model.MotionSample
import com.risingpadel.core.model.Shot
import com.risingpadel.core.model.ShotType
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * La autocalibración del signo de la elevación, contra el caso real de pista: en una
 * combinación de muñeca y corona que invierte el eje, los smashes salían con elevación
 * negativa (clasificados como golpes de fondo) y las derechas con +70° (mandadas a la
 * rama de golpes altos).
 */
class ElevationAutoCalTest {

    private fun detect(samples: List<MotionSample>): List<Shot> {
        val detector = ShotDetector()
        detector.reset(samples.first().timestampMs)
        val shots = samples.mapNotNull { detector.process(it) }.toMutableList()
        detector.flush()?.let { shots.add(it) }
        return shots
    }

    private fun smash(startMs: Long, elevationDeg: Float) = MotionFixtures.swing(
        startMs = startMs,
        peakGyroRadS = 27f, // por encima del umbral de smash (24)
        swingDurationMs = 220,
        impactG = 8f,
        axialFraction = 0.3f,
        elevationDeg = elevationDeg,
    )

    @Test
    fun `mundo normal - el smash sigue siendo smash`() {
        // Brazo colgando (−40°) entre puntos; el remate llega con el brazo en alto.
        val samples = MotionFixtures.rest(0, 12_000, elevationDeg = -40f) +
            smash(12_000, elevationDeg = 70f)
        val shots = detect(samples)
        assertEquals(listOf(ShotType.SMASH), shots.map { it.type })
    }

    @Test
    fun `mundo invertido - la autocalibracion endereza el smash`() {
        // La misma sesión vista por un eje invertido: el reposo lee +40° ("en alto"
        // durante minutos, imposible) y el remate lee −70°. Sin corrección, esto se
        // clasificaba como golpe de fondo.
        val samples = MotionFixtures.rest(0, 12_000, elevationDeg = 40f) +
            smash(12_000, elevationDeg = -70f)
        val shots = detect(samples)
        assertEquals(listOf(ShotType.SMASH), shots.map { it.type })
    }

    @Test
    fun `sin calentamiento suficiente no se toca el signo`() {
        // Con solo un par de segundos de datos la media no es fiable: el signo se queda
        // en +1 — antes quieto que corregir de más.
        val samples = MotionFixtures.rest(0, 2_000, elevationDeg = 40f) +
            smash(2_000, elevationDeg = 70f)
        val shots = detect(samples)
        assertEquals(listOf(ShotType.SMASH), shots.map { it.type })
    }
}
