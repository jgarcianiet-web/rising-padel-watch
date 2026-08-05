package com.risingpadel.core.detection

import com.risingpadel.core.MotionFixtures
import com.risingpadel.core.model.MotionSample
import com.risingpadel.core.model.Shot
import com.risingpadel.core.model.ShotType
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class ShotDetectorTest {

    private fun detect(samples: List<MotionSample>, config: DetectorConfig = DetectorConfig.DEFAULT): List<Shot> {
        val detector = ShotDetector(config)
        detector.reset(samples.first().timestampMs)
        val shots = samples.mapNotNull { detector.process(it) }.toMutableList()
        detector.flush()?.let { shots.add(it) }
        return shots
    }

    @Test
    fun `detecta un golpeo aislado`() {
        val shots = detect(MotionFixtures.rest(0, 400) + MotionFixtures.forehand(400))
        assertEquals(1, shots.size, "un swing con impacto debería dar exactamente un golpeo")
    }

    @Test
    fun `no cuenta correr por la pista`() {
        val shots = detect(MotionFixtures.running(0, 6_000))
        assertEquals(0, shots.size, "el braceo de correr no debe contar como golpeo")
    }

    @Test
    fun `no cuenta un impacto sin swing`() {
        val shots = detect(MotionFixtures.rest(0, 400) + MotionFixtures.tapWithoutSwing(400))
        assertEquals(0, shots.size, "un pico de aceleración sin rotación no es un golpeo")
    }

    @Test
    fun `no cuenta un swing que no llega a impactar`() {
        // Mismo swing pero sin pico de impacto: preparación o amago.
        val amago = MotionFixtures.swing(
            startMs = 400,
            peakGyroRadS = 18f,
            swingDurationMs = 300,
            impactG = 0f,
            axialFraction = 0.8f,
            elevationDeg = 10f,
        )
        assertEquals(0, detect(MotionFixtures.rest(0, 400) + amago).size)
    }

    /** Swing corto para poder encadenar dos sin que se solapen en el tiempo. */
    private fun golpeoCorto(startMs: Long) = MotionFixtures.swing(
        startMs = startMs,
        peakGyroRadS = 20f,
        swingDurationMs = 160,
        impactG = 6f,
        axialFraction = 0.8f,
        elevationDeg = 10f,
    )

    @Test
    fun `el periodo refractario evita contar dos veces el mismo golpeo`() {
        // Impactos a 200 ms: por debajo del refractario de 320 ms, es el rebote del
        // mismo golpeo y no dos golpeos distintos.
        val samples = MotionFixtures.rest(0, 400) + golpeoCorto(400) + golpeoCorto(600)
        assertEquals(1, detect(samples).size)
    }

    @Test
    fun `cuenta dos golpeos separados por un intercambio normal`() {
        // Impactos a 400 ms: por encima del refractario, son dos golpeos.
        val samples = MotionFixtures.rest(0, 400) + golpeoCorto(400) + golpeoCorto(800)
        assertEquals(2, detect(samples).size)
    }

    @Test
    fun `cuenta todos los golpeos de un peloteo largo`() {
        val samples = mutableListOf<MotionSample>()
        var t = 0L
        samples += MotionFixtures.rest(t, 500); t += 500
        repeat(12) {
            samples += MotionFixtures.forehand(t); t += 320
            samples += MotionFixtures.rest(t, 700); t += 700
        }
        assertEquals(12, detect(samples).size)
    }

    @Test
    fun `el offset del golpeo es relativo al inicio de la sesion`() {
        val detector = ShotDetector()
        val samples = MotionFixtures.rest(10_000, 400) + MotionFixtures.forehand(10_400)
        detector.reset(10_000)
        val shot = samples.firstNotNullOf { detector.process(it) }
        // El impacto cae al 75% de un swing de 300 ms que empieza en +400 ms.
        assertTrue(shot.offsetMs in 550..700, "offset inesperado: ${shot.offsetMs}")
    }

    @Test
    fun `estima velocidad de pala y g de impacto`() {
        val shot = detect(MotionFixtures.rest(0, 400) + MotionFixtures.forehand(400)).single()
        // 20 rad/s * 0.65 m * 3.6 ≈ 47 km/h
        assertTrue(shot.racketSpeedKmh in 40f..55f, "velocidad inesperada: ${shot.racketSpeedKmh}")
        assertTrue(shot.impactG in 5f..8f, "impacto inesperado: ${shot.impactG}")
    }

    @Test
    fun `la sensibilidad baja descarta golpeos flojos que la alta si detecta`() {
        val flojo = MotionFixtures.rest(0, 400) + MotionFixtures.swing(
            startMs = 400,
            peakGyroRadS = 6.5f,
            swingDurationMs = 280,
            impactG = 3.4f,
            axialFraction = 0.7f,
            elevationDeg = 10f,
        )
        val baja = detect(flojo, DetectorConfig.DEFAULT.withSensitivity(Sensitivity.LOW))
        val alta = detect(flojo, DetectorConfig.DEFAULT.withSensitivity(Sensitivity.HIGH))
        assertEquals(0, baja.size, "con sensibilidad baja no debería contar")
        assertEquals(1, alta.size, "con sensibilidad alta sí debería contar")
    }

    @Test
    fun `un hueco en las muestras no infla el angulo barrido`() {
        // Simula la app suspendida 2 s en mitad del swing: el dt se acota a 100 ms.
        val swing = MotionFixtures.forehand(400)
        val conHueco = swing.take(6) + swing.drop(6).map { it.copy(timestampMs = it.timestampMs + 2_000) }
        val shots = detect(MotionFixtures.rest(0, 400) + conHueco)
        shots.forEach {
            assertTrue(
                it.features.sweptAngleDeg < 720f,
                "el hueco infló el ángulo barrido: ${it.features.sweptAngleDeg}",
            )
        }
    }

    @Test
    fun `reset limpia el estado entre sesiones`() {
        val detector = ShotDetector()
        detector.reset(0)
        MotionFixtures.forehand(0).forEach { detector.process(it) }
        detector.reset(10_000)
        val shots = (MotionFixtures.rest(10_000, 400) + MotionFixtures.forehand(10_400))
            .mapNotNull { detector.process(it) }
        assertEquals(1, shots.size)
        assertTrue(shots.single().offsetMs < 1_000)
    }

    @Test
    fun `clasifica los golpeos tipo`() {
        val cases = listOf(
            ShotType.FOREHAND to MotionFixtures.forehand(400),
            ShotType.BACKHAND to MotionFixtures.backhand(400),
            ShotType.FOREHAND_VOLLEY to MotionFixtures.forehandVolley(400),
            ShotType.BACKHAND_VOLLEY to MotionFixtures.backhandVolley(400),
            ShotType.BANDEJA to MotionFixtures.bandeja(400),
            ShotType.VIBORA to MotionFixtures.vibora(400),
            ShotType.SMASH to MotionFixtures.smash(400),
            ShotType.SERVE to MotionFixtures.serve(400),
        )
        cases.forEach { (expected, samples) ->
            val shot = detect(MotionFixtures.rest(0, 400) + samples).singleOrNull()
                ?: error("no se detectó el golpeo esperado $expected")
            assertEquals(
                expected,
                shot.type,
                "clasificación incorrecta (confianza ${shot.confidence}, rasgos ${shot.features})",
            )
        }
    }

    // --- robustez de la elevación ---
    //
    // El caso real que motiva estas pruebas: en pista, una tanda de derechas midió
    // +41..+77° de elevación y una de víboras −20..+56°. La estimación de gravedad del
    // sistema se descuadra en mitad de un swing violento, así que un valor instantáneo
    // no vale para decidir; las estadísticas sobre el swing entero sí.

    /** Sustituye la gravedad de unas muestras del swing por una lectura descuadrada. */
    private fun conGravedadRota(
        samples: List<MotionSample>,
        indices: IntRange,
        elevationDeg: Float,
    ): List<MotionSample> {
        val rad = elevationDeg * Math.PI.toFloat() / 180f
        val rota = com.risingpadel.core.model.Vector3(
            -kotlin.math.cos(rad),
            -kotlin.math.sin(rad),
            0f,
        )
        return samples.mapIndexed { i, s -> if (i in indices) s.copy(gravity = rota) else s }
    }

    @Test
    fun `un pico suelto de gravedad no convierte una derecha en golpe alto`() {
        val swing = MotionFixtures.forehand(400)
        // Dos muestras de las quince con la gravedad disparada a +85°.
        val conPico = conGravedadRota(swing, 6..7, elevationDeg = 85f)

        val shot = detect(MotionFixtures.rest(0, 400) + conPico).single()

        assertEquals(ShotType.FOREHAND, shot.type, "rasgos ${shot.features}")
        assertTrue(
            shot.features.peakElevationDeg < DetectorConfig.DEFAULT.overheadElevationDeg,
            "el percentil se dejó arrastrar por el pico: ${shot.features.peakElevationDeg}",
        )
    }

    @Test
    fun `una bandeja se reconoce aunque la gravedad falle justo en el impacto`() {
        val swing = MotionFixtures.bandeja(400)
        // Las tres últimas muestras (el impacto y su entorno) leen el brazo a la altura
        // de la cintura, que es justo el error que se veía en pista.
        val rotas = conGravedadRota(swing, (swing.size - 3)..swing.lastIndex, elevationDeg = 5f)

        val shot = detect(MotionFixtures.rest(0, 400) + rotas).single()

        assertEquals(ShotType.BANDEJA, shot.type, "rasgos ${shot.features}")
    }

    @Test
    fun `la elevación de pico es mayor o igual que la mediana`() {
        val shot = detect(MotionFixtures.rest(0, 400) + MotionFixtures.bandeja(400)).single()

        assertTrue(shot.features.peakElevationDeg >= shot.features.elevationDeg)
    }
}
