package com.risingpadel.core.training

import com.risingpadel.core.model.MotionSample
import com.risingpadel.core.model.Shot

/** Ventana cruda alrededor de un golpeo, lista para etiquetar. */
data class CapturedWindow(
    val shot: Shot,
    val impactTimestampMs: Long,
    val samples: List<MotionSample>,
    /** Índice de la muestra del impacto dentro de [samples]. */
    val impactIndex: Int,
)

/**
 * Recorta la señal cruda alrededor de cada golpeo detectado.
 *
 * El detalle que obliga a hacerlo así: **la ventana necesita un segundo posterior al
 * impacto, que todavía no ha llegado** cuando el detector avisa del golpeo. Así que un
 * golpeo detectado queda pendiente y solo se emite cuando el tiempo lo alcanza. Guardar
 * únicamente lo anterior al impacto perdería la frenada del brazo, que es justo lo que
 * distingue una volea bloqueada de una derecha completa.
 *
 * El buffer es circular y acotado: en una sesión de una hora no crece.
 *
 * No es thread-safe: se llama desde el hilo de sensores, igual que el detector.
 */
class TrainingCapture(
    private val sampleRateHz: Int = 50,
    private val windowBeforeMs: Long = 1_000,
    private val windowAfterMs: Long = 1_000,
) {
    private val intervalMs = (1000L / sampleRateHz).coerceAtLeast(1L)

    /**
     * Capacidad con margen: hay que retener toda la ventana más holgura para el jitter
     * de los sensores y para golpeos encadenados.
     */
    private val capacity =
        (((windowBeforeMs + windowAfterMs) / intervalMs) * 3 / 2).toInt() + 16

    private val buffer = ArrayDeque<MotionSample>()
    private val pending = ArrayDeque<PendingShot>()

    private data class PendingShot(val shot: Shot, val impactTimestampMs: Long)

    val pendingCount: Int get() = pending.size

    fun reset() {
        buffer.clear()
        pending.clear()
    }

    /** Marca un golpeo como pendiente de recorte. [impactTimestampMs] es monótono. */
    fun onShotDetected(shot: Shot, impactTimestampMs: Long) {
        pending.addLast(PendingShot(shot, impactTimestampMs))
    }

    /**
     * Consume una muestra y devuelve las ventanas que han quedado completas con ella.
     * Normalmente vacía; devuelve una lista y no un valor único porque dos golpeos muy
     * seguidos pueden completarse en la misma muestra.
     */
    fun onSample(sample: MotionSample): List<CapturedWindow> {
        push(sample)

        val ready = mutableListOf<CapturedWindow>()
        while (pending.isNotEmpty()) {
            val next = pending.first()
            // Todavía no ha llegado la cola de este golpeo: como la cola crece con el
            // tiempo, ninguno posterior puede estar listo tampoco.
            if (sample.timestampMs < next.impactTimestampMs + windowAfterMs) break
            pending.removeFirst()
            extract(next)?.let { ready.add(it) }
        }
        return ready
    }

    /**
     * Cierra las ventanas pendientes al parar la grabación, aunque les falte cola.
     *
     * Se conservan en vez de descartarse: el último golpeo de cada tanda entra aquí, y
     * tirarlo perdería uno de cada treinta.
     */
    fun flush(): List<CapturedWindow> {
        val ready = pending.mapNotNull { extract(it) }
        pending.clear()
        return ready
    }

    private fun extract(pendingShot: PendingShot): CapturedWindow? {
        val from = pendingShot.impactTimestampMs - windowBeforeMs
        val to = pendingShot.impactTimestampMs + windowAfterMs
        val window = buffer.filter { it.timestampMs in from..to }
        if (window.isEmpty()) return null

        // El impacto es la muestra más cercana al instante del impacto: con jitter de
        // sensores puede no haber ninguna exactamente en ese milisegundo.
        val impactIndex = window.indices.minBy {
            kotlin.math.abs(window[it].timestampMs - pendingShot.impactTimestampMs)
        }
        return CapturedWindow(
            shot = pendingShot.shot,
            impactTimestampMs = pendingShot.impactTimestampMs,
            samples = window,
            impactIndex = impactIndex,
        )
    }

    private fun push(sample: MotionSample) {
        buffer.addLast(sample)
        while (buffer.size > capacity) buffer.removeFirst()
    }
}
