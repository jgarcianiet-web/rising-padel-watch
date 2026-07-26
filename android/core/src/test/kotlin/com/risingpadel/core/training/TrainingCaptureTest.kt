package com.risingpadel.core.training

import com.risingpadel.core.MotionFixtures
import com.risingpadel.core.detection.DetectorConfig
import com.risingpadel.core.detection.ShotDetector
import com.risingpadel.core.model.MotionSample
import com.risingpadel.core.model.Platform
import com.risingpadel.core.model.PlayerProfile
import com.risingpadel.core.model.ShotType
import com.risingpadel.core.model.SourceInfo
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class TrainingCaptureTest {

    private val source = SourceInfo(Platform.WEAROS, "Pixel Watch 3", "1.0.0")

    private fun recorder(alias: String = "jugador-1", label: ShotType = ShotType.FOREHAND) =
        TrainingRecorder(
            source = source,
            profile = PlayerProfile(),
            sampleIdProvider = { "sample-fijo" },
            nowEpochMs = { 1_785_002_652_000 },
        ).apply {
            this.label = label
            this.playerAlias = alias
        }

    /** Un golpeo con reposo antes y después, para que la ventana quepa entera. */
    private fun golpeoConMargen(): List<MotionSample> =
        MotionFixtures.rest(startMs = 0, durationMs = 1_500) +
            MotionFixtures.forehand(startMs = 1_500) +
            MotionFixtures.rest(startMs = 1_820, durationMs = 1_500)

    // --- recorte de la ventana ---

    @Test
    fun `captura una muestra por golpeo detectado`() {
        val recorder = recorder()
        recorder.start(0)
        val captured = golpeoConMargen().flatMap { recorder.onMotion(it) } + recorder.stop()

        assertEquals(1, captured.size)
        assertEquals(1, recorder.capturedCount)
    }

    @Test
    fun `la ventana va de un segundo antes a un segundo despues del impacto`() {
        val recorder = recorder()
        recorder.start(0)
        val sample = (golpeoConMargen().flatMap { recorder.onMotion(it) } + recorder.stop()).single()

        assertTrue(sample.offsetsMs.first() <= -900, "falta señal previa: ${sample.offsetsMs.first()}")
        assertTrue(sample.offsetsMs.last() >= 900, "falta señal posterior: ${sample.offsetsMs.last()}")
        // 2 s a 50 Hz son unas 100 muestras.
        assertTrue(sample.sampleCount in 95..106, "muestras inesperadas: ${sample.sampleCount}")
    }

    @Test
    fun `el impacto queda en el centro de la ventana y su offset es cero`() {
        val recorder = recorder()
        recorder.start(0)
        val sample = (golpeoConMargen().flatMap { recorder.onMotion(it) } + recorder.stop()).single()

        assertEquals(0, sample.offsetsMs[sample.impactIndex], "el impacto debe estar en el offset 0")
        val mitad = sample.sampleCount / 2
        assertTrue(
            kotlin.math.abs(sample.impactIndex - mitad) <= 3,
            "el impacto debería quedar centrado: ${sample.impactIndex} de ${sample.sampleCount}",
        )
    }

    @Test
    fun `la ventana no se emite hasta que llega la cola posterior al impacto`() {
        val recorder = recorder()
        recorder.start(0)

        // Solo hasta el impacto: todavía no puede haber ventana completa.
        val hastaElImpacto = MotionFixtures.rest(0, 1_500) + MotionFixtures.forehand(1_500)
        val duranteElGolpeo = hastaElImpacto.flatMap { recorder.onMotion(it) }
        assertTrue(duranteElGolpeo.isEmpty(), "no puede emitirse sin el segundo posterior")

        val despues = MotionFixtures.rest(1_820, 1_500).flatMap { recorder.onMotion(it) }
        assertEquals(1, despues.size, "al llegar la cola sí se emite")
    }

    @Test
    fun `stop cierra el ultimo golpeo aunque le falte cola`() {
        val recorder = recorder()
        recorder.start(0)
        // La tanda acaba justo tras el golpeo: sin flush se perdería uno de cada treinta.
        (MotionFixtures.rest(0, 1_500) + MotionFixtures.forehand(1_500))
            .forEach { recorder.onMotion(it) }

        assertEquals(1, recorder.stop().size)
    }

    @Test
    fun `una tanda de treinta golpeos captura los treinta`() {
        val recorder = recorder()
        recorder.start(0)

        val samples = mutableListOf<MotionSample>()
        var t = 0L
        samples += MotionFixtures.rest(t, 1_500); t += 1_500
        repeat(30) {
            samples += MotionFixtures.forehand(t); t += 320
            samples += MotionFixtures.rest(t, 1_200); t += 1_200
        }
        val captured = samples.flatMap { recorder.onMotion(it) } + recorder.stop()

        assertEquals(30, captured.size)
    }

    // --- etiquetado y metadatos ---

    @Test
    fun `la etiqueta es la que eligio el jugador, no la que adivino la heuristica`() {
        // Se graba una tanda de reveses pero la señal es de derecha: la etiqueta manda.
        val recorder = recorder(label = ShotType.BACKHAND)
        recorder.start(0)
        val sample = (golpeoConMargen().flatMap { recorder.onMotion(it) } + recorder.stop()).single()

        assertEquals(ShotType.BACKHAND, sample.label, "la etiqueta la pone el jugador")
        assertEquals(ShotType.FOREHAND, sample.heuristicPrediction, "y se guarda lo que dijo la heurística")
        assertTrue(!sample.heuristicWasRight, "aquí la heurística no acertaría")
    }

    @Test
    fun `guarda el alias del jugador para poder validar dejandolo fuera`() {
        val recorder = recorder(alias = "marta")
        recorder.start(0)
        val sample = (golpeoConMargen().flatMap { recorder.onMotion(it) } + recorder.stop()).single()

        assertEquals("marta", sample.playerAlias)
    }

    @Test
    fun `guarda las tres series crudas alineadas`() {
        val recorder = recorder()
        recorder.start(0)
        val sample = (golpeoConMargen().flatMap { recorder.onMotion(it) } + recorder.stop()).single()

        assertEquals(sample.sampleCount, sample.accel.size)
        assertEquals(sample.sampleCount, sample.gyro.size)
        assertEquals(sample.sampleCount, sample.gravity.size)
        assertTrue(sample.accel.all { it.size == 3 }, "cada muestra son tres ejes")
    }

    @Test
    fun `guarda los rasgos de la heuristica para medir la mejora del modelo`() {
        val recorder = recorder()
        recorder.start(0)
        val sample = (golpeoConMargen().flatMap { recorder.onMotion(it) } + recorder.stop()).single()

        assertTrue(sample.heuristicFeatures.peakGyroRadS > 0)
        assertTrue(sample.heuristicConfidence > 0)
    }

    // --- memoria ---

    @Test
    fun `el buffer no crece con la duracion de la sesion`() {
        val capture = TrainingCapture(sampleRateHz = 50)
        // Media hora de señal sin ningún golpeo.
        MotionFixtures.rest(0, 1_800_000).forEach { capture.onSample(it) }

        assertEquals(0, capture.pendingCount)
        // Si el buffer creciera sin límite, esto habría reventado la memoria mucho antes.
        assertTrue(capture.flush().isEmpty())
    }

    @Test
    fun `sin start no se captura nada`() {
        val recorder = recorder()
        val captured = golpeoConMargen().flatMap { recorder.onMotion(it) }

        assertTrue(captured.isEmpty())
        assertTrue(!recorder.isRecording)
    }

    @Test
    fun `start reinicia el contador entre tandas`() {
        val recorder = recorder()
        recorder.start(0)
        golpeoConMargen().forEach { recorder.onMotion(it) }
        recorder.stop()
        assertEquals(1, recorder.capturedCount)

        recorder.start(10_000)
        assertEquals(0, recorder.capturedCount, "cada tanda cuenta desde cero")
    }

    /** El detector v1 no es perfecto: si se deja un golpeo, la tanda tiene uno menos. */
    @Test
    fun `solo se capturan los golpeos que el detector encuentra`() {
        val recorder = recorder()
        recorder.start(0)
        // Señal sin impacto: el detector no ve golpeo y no hay nada que capturar.
        val amago = MotionFixtures.swing(
            startMs = 1_500, peakGyroRadS = 18f, swingDurationMs = 300, impactG = 0f,
            axialFraction = 0.8f, elevationDeg = 10f,
        )
        val captured = (MotionFixtures.rest(0, 1_500) + amago + MotionFixtures.rest(1_820, 1_500))
            .flatMap { recorder.onMotion(it) } + recorder.stop()

        assertTrue(captured.isEmpty())
    }

    @Test
    fun `el detector del grabador usa la configuracion que se le pasa`() {
        val recorder = TrainingRecorder(
            source = source,
            profile = PlayerProfile(),
            config = DetectorConfig(sampleRateHz = 50, impactG = 20f), // umbral inalcanzable
            sampleIdProvider = { "x" },
            nowEpochMs = { 0 },
        )
        recorder.start(0)
        val captured = golpeoConMargen().flatMap { recorder.onMotion(it) } + recorder.stop()

        assertTrue(captured.isEmpty(), "con el umbral por las nubes no debería detectar nada")
    }

    @Test
    fun `el detector standalone y el del grabador ven los mismos golpeos`() {
        val detector = ShotDetector()
        detector.reset(0)
        val samples = golpeoConMargen()
        val directos = samples.mapNotNull { detector.process(it) }.size +
            (if (detector.flush() != null) 1 else 0)

        val recorder = recorder()
        recorder.start(0)
        val capturados = samples.flatMap { recorder.onMotion(it) }.size + recorder.stop().size

        assertEquals(directos, capturados, "grabar no debe cambiar qué golpeos se detectan")
    }
}
