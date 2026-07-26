package com.risingpadel.core.level

import com.risingpadel.core.model.Shot
import com.risingpadel.core.model.ShotFeatures
import com.risingpadel.core.model.ShotType
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class LevelEstimatorTest {

    private val estimator = LevelEstimator()

    private fun shot(
        type: ShotType = ShotType.FOREHAND,
        speedKmh: Float = 45f,
        sweptDeg: Float = 200f,
        confidence: Float = 0.9f,
        offsetMs: Long = 0,
    ) = Shot(
        offsetMs = offsetMs,
        type = type,
        racketSpeedKmh = speedKmh,
        impactG = 5f,
        confidence = confidence,
        features = ShotFeatures(
            sweptAngleDeg = sweptDeg,
            peakGyroRadS = speedKmh / 2.34f,
            elevationDeg = 20f,
            axialRotationRadS = 3f,
            swingDurationMs = 300,
        ),
    )

    // --- nota de un golpeo suelto ---

    @Test
    fun `una derecha en el extremo bajo de la banda puntua 1`() {
        val grade = estimator.grade(shot(speedKmh = 28f, sweptDeg = 200f))

        // Velocidad en el mínimo, swing perfecto: solo puntúa la parte de swing.
        assertNotNull(grade)
        assertEquals(1f + 0.35f * 6f, grade, 0.1f)
    }

    @Test
    fun `una derecha en el extremo alto de la banda puntua 7`() {
        assertEquals(7f, estimator.grade(shot(speedKmh = 65f, sweptDeg = 200f)))
    }

    @Test
    fun `pasarse de la banda no puntua mas de 7`() {
        assertEquals(7f, estimator.grade(shot(speedKmh = 200f, sweptDeg = 400f)))
    }

    @Test
    fun `un golpeo de tipo desconocido no puntua`() {
        assertNull(estimator.grade(shot(type = ShotType.UNKNOWN)))
    }

    /** Puntuar un golpeo que no se sabe qué es sería inventar. */
    @Test
    fun `un golpeo mal clasificado no puntua`() {
        assertNull(estimator.grade(shot(confidence = 0.2f)))
    }

    // --- la asimetría de la volea ---

    @Test
    fun `una volea compacta puntua mejor que una volea con swing largo`() {
        val compacta = estimator.grade(shot(type = ShotType.FOREHAND_VOLLEY, speedKmh = 18f, sweptDeg = 40f))
        val larga = estimator.grade(shot(type = ShotType.FOREHAND_VOLLEY, speedKmh = 18f, sweptDeg = 85f))

        assertNotNull(compacta)
        assertNotNull(larga)
        assertTrue(compacta > larga, "la volea se bloquea, no se golpea: $compacta vs $larga")
    }

    @Test
    fun `en la derecha en cambio el swing corto penaliza`() {
        val completa = estimator.grade(shot(speedKmh = 45f, sweptDeg = 200f))
        val corta = estimator.grade(shot(speedKmh = 45f, sweptDeg = 80f))

        assertNotNull(completa)
        assertNotNull(corta)
        assertTrue(completa > corta)
    }

    // --- nivel de la sesión ---

    @Test
    fun `sin golpeos clasificables el nivel no es fiable`() {
        val level = estimator.estimate(List(50) { shot(type = ShotType.UNKNOWN) })

        assertFalse(level.reliable)
        assertEquals(0, level.gradedShots)
    }

    @Test
    fun `con menos golpeos del minimo el nivel se calcula pero no es fiable`() {
        val level = estimator.estimate(List(10) { shot(speedKmh = 45f) })

        assertFalse(level.reliable)
        assertTrue(level.overall > 1f, "se sigue dando una estimación, solo que avisando")
    }

    @Test
    fun `con golpeos suficientes el nivel es fiable`() {
        val level = estimator.estimate(List(40) { shot(speedKmh = 45f) })

        assertTrue(level.reliable)
        assertEquals(40, level.gradedShots)
    }

    @Test
    fun `un jugador mas rapido saca mas nivel`() {
        val flojo = estimator.estimate(List(40) { shot(speedKmh = 32f) })
        val fuerte = estimator.estimate(List(40) { shot(speedKmh = 60f) })

        assertTrue(fuerte.overall > flojo.overall)
    }

    /** En pádel el nivel **es** regularidad: misma punta, distinta constancia. */
    @Test
    fun `a igual media el jugador regular saca mas nivel que el irregular`() {
        val regular = estimator.estimate(List(40) { shot(speedKmh = 46f) })
        val irregular = estimator.estimate(
            List(40) { index -> shot(speedKmh = if (index % 2 == 0) 30f else 62f) }
        )

        assertTrue(
            regular.overall > irregular.overall,
            "regular ${regular.overall} debería superar a irregular ${irregular.overall}",
        )
        assertTrue(regular.consistency > irregular.consistency)
    }

    @Test
    fun `la regularidad se mide dentro de cada tipo y no entre tipos`() {
        // Voleas lentas y derechas rápidas: es lo normal, no es irregularidad.
        val mixto = List(20) { shot(type = ShotType.FOREHAND, speedKmh = 46f) } +
            List(20) { shot(type = ShotType.FOREHAND_VOLLEY, speedKmh = 18f) }

        assertTrue(estimator.estimate(mixto).consistency > 0.9f)
    }

    /** Penalizar una sesión de solo derechas sería castigar entrenar. */
    @Test
    fun `el repertorio suma pero nunca resta`() {
        val soloDerechas = estimator.estimate(List(40) { shot(speedKmh = 46f) })
        val completo = estimator.estimate(
            ShotType.entries.filter { it != ShotType.UNKNOWN }.flatMap { type ->
                List(10) { shot(type = type, speedKmh = midBandSpeed(type), sweptDeg = idealSwept(type)) }
            }
        )

        // Un solo tipo de seis da 1/6: una bonificación de 0,07 niveles, o sea ninguna.
        // Lo que importa es que no baja de cero y que el repertorio completo suma más.
        assertTrue(soloDerechas.repertoire >= 0f, "el repertorio nunca resta")
        assertTrue(completo.repertoire > soloDerechas.repertoire)
        assertTrue(completo.overall > soloDerechas.overall)
    }

    @Test
    fun `la media es por tipo de golpe y no por golpeo suelto`() {
        // 100 derechas flojas y 10 smashes buenos. Si la media fuera por golpeo, los
        // smashes no se notarían; siendo por tipo, pesan igual que las derechas.
        val sesion = List(100) { shot(type = ShotType.FOREHAND, speedKmh = 30f) } +
            List(10) { shot(type = ShotType.OVERHEAD, speedKmh = 88f, sweptDeg = 200f) }

        val level = estimator.estimate(sesion)
        val soloDerechas = estimator.estimate(List(100) { shot(type = ShotType.FOREHAND, speedKmh = 30f) })

        assertTrue(level.overall > soloDerechas.overall)
    }

    @Test
    fun `el desglose por tipo solo trae los tipos jugados`() {
        val level = estimator.estimate(
            List(20) { shot(type = ShotType.FOREHAND) } + List(20) { shot(type = ShotType.SERVE) }
        )

        assertEquals(setOf(ShotType.FOREHAND, ShotType.SERVE), level.byShotType.keys)
    }

    @Test
    fun `el nivel nunca se sale de la escala`() {
        val bestial = estimator.estimate(
            ShotType.entries.filter { it != ShotType.UNKNOWN }.flatMap { type ->
                List(20) { shot(type = type, speedKmh = 500f, sweptDeg = idealSwept(type)) }
            }
        )
        val flojisimo = estimator.estimate(List(40) { shot(speedKmh = 1f, sweptDeg = 1f) })

        assertTrue(bestial.overall <= 7f, "se pasó a ${bestial.overall}")
        assertTrue(flojisimo.overall >= 1f, "bajó a ${flojisimo.overall}")
    }

    @Test
    fun `el nivel redondeado va de medio en medio`() {
        val level = SessionLevel(
            overall = 4.37f,
            byShotType = emptyMap(),
            consistency = 1f,
            repertoire = 0f,
            gradedShots = 40,
            reliable = true,
        )

        assertEquals(4.5f, level.rounded)
    }

    @Test
    fun `una sesion vacia no revienta`() {
        val level = estimator.estimate(emptyList())

        assertEquals(0, level.gradedShots)
        assertFalse(level.reliable)
    }

    private fun midBandSpeed(type: ShotType): Float {
        val band = LevelConfig.DEFAULT_BANDS.getValue(type)
        return (band.speedAtLevel1 + band.speedAtLevel7) / 2
    }

    private fun idealSwept(type: ShotType): Float =
        LevelConfig.DEFAULT_BANDS.getValue(type).idealSweptDeg
}
