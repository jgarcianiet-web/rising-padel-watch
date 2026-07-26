import Foundation

/// Ventana cruda alrededor de un golpeo, lista para etiquetar.
public struct CapturedWindow: Equatable, Sendable {
    public let shot: Shot
    public let impactTimestampMs: Int64
    public let samples: [MotionSample]
    /// Índice de la muestra del impacto dentro de `samples`.
    public let impactIndex: Int
}

/// Recorta la señal cruda alrededor de cada golpeo detectado.
///
/// El detalle que obliga a hacerlo así: **la ventana necesita un segundo posterior al
/// impacto, que todavía no ha llegado** cuando el detector avisa del golpeo. Así que un
/// golpeo detectado queda pendiente y solo se emite cuando el tiempo lo alcanza. Guardar
/// únicamente lo anterior al impacto perdería la frenada del brazo, que es justo lo que
/// distingue una volea bloqueada de una derecha completa.
///
/// El buffer es circular y acotado: en una sesión de una hora no crece.
///
/// No es thread-safe: se llama desde la cola de sensores, igual que el detector.
public final class TrainingCapture {
    private struct PendingShot {
        let shot: Shot
        let impactTimestampMs: Int64
    }

    private let windowBeforeMs: Int64
    private let windowAfterMs: Int64
    private let capacity: Int

    private var buffer: [MotionSample] = []
    private var pending: [PendingShot] = []

    public init(sampleRateHz: Int = 50, windowBeforeMs: Int64 = 1_000, windowAfterMs: Int64 = 1_000) {
        self.windowBeforeMs = windowBeforeMs
        self.windowAfterMs = windowAfterMs
        let intervalMs = max(Int64(1000 / sampleRateHz), 1)
        // Capacidad con margen: hay que retener toda la ventana más holgura para el
        // jitter de los sensores y para golpeos encadenados.
        self.capacity = Int(((windowBeforeMs + windowAfterMs) / intervalMs) * 3 / 2) + 16
        self.buffer.reserveCapacity(capacity)
    }

    public var pendingCount: Int { pending.count }

    public func reset() {
        buffer.removeAll(keepingCapacity: true)
        pending.removeAll(keepingCapacity: true)
    }

    /// Marca un golpeo como pendiente de recorte. `impactTimestampMs` es monótono.
    public func onShotDetected(_ shot: Shot, impactTimestampMs: Int64) {
        pending.append(PendingShot(shot: shot, impactTimestampMs: impactTimestampMs))
    }

    /// Consume una muestra y devuelve las ventanas que han quedado completas con ella.
    ///
    /// Normalmente vacía; devuelve una lista y no un valor único porque dos golpeos muy
    /// seguidos pueden completarse en la misma muestra.
    public func onSample(_ sample: MotionSample) -> [CapturedWindow] {
        push(sample)

        var ready: [CapturedWindow] = []
        while let next = pending.first {
            // Todavía no ha llegado la cola de este golpeo: como la cola crece con el
            // tiempo, ninguno posterior puede estar listo tampoco.
            guard sample.timestampMs >= next.impactTimestampMs + windowAfterMs else { break }
            pending.removeFirst()
            if let window = extract(next) { ready.append(window) }
        }
        return ready
    }

    /// Cierra las ventanas pendientes al parar la grabación, aunque les falte cola.
    ///
    /// Se conservan en vez de descartarse: el último golpeo de cada tanda entra aquí, y
    /// tirarlo perdería uno de cada treinta.
    public func flush() -> [CapturedWindow] {
        let ready = pending.compactMap { extract($0) }
        pending.removeAll(keepingCapacity: true)
        return ready
    }

    private func extract(_ pendingShot: PendingShot) -> CapturedWindow? {
        let from = pendingShot.impactTimestampMs - windowBeforeMs
        let to = pendingShot.impactTimestampMs + windowAfterMs
        let window = buffer.filter { $0.timestampMs >= from && $0.timestampMs <= to }
        guard !window.isEmpty else { return nil }

        // El impacto es la muestra más cercana al instante del impacto: con jitter de
        // sensores puede no haber ninguna exactamente en ese milisegundo.
        var impactIndex = 0
        var best = Int64.max
        for (index, sample) in window.enumerated() {
            let distance = abs(sample.timestampMs - pendingShot.impactTimestampMs)
            if distance < best {
                best = distance
                impactIndex = index
            }
        }
        return CapturedWindow(
            shot: pendingShot.shot,
            impactTimestampMs: pendingShot.impactTimestampMs,
            samples: window,
            impactIndex: impactIndex
        )
    }

    private func push(_ sample: MotionSample) {
        buffer.append(sample)
        if buffer.count > capacity {
            buffer.removeFirst(buffer.count - capacity)
        }
    }
}
