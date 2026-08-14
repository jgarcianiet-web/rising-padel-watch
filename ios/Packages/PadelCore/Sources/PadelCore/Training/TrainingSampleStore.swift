import Foundation

/// Almacén de muestras de entrenamiento en JSONL: una muestra por línea.
///
/// JSONL y no un JSON único porque grabar es **añadir**: cada golpeo se escribe en cuanto
/// está listo, sin releer ni reescribir lo anterior. Si el reloj se queda sin batería a
/// mitad de una tanda, se pierde como mucho la última línea; con un array JSON se
/// perdería el fichero entero.
///
/// También es el formato que espera `tools/train_classifier.py`.
public final class TrainingSampleStore {
    public let url: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let fileManager = FileManager.default

    public init(url: URL) {
        self.url = url
        try? fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    public var exists: Bool { fileManager.fileExists(atPath: url.path) }

    public var sizeBytes: Int64 {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int64 else { return 0 }
        return size
    }

    public func append(_ sample: TrainingSample) {
        appendAll([sample])
    }

    public func appendAll(_ samples: [TrainingSample]) {
        guard !samples.isEmpty else { return }
        let lines = samples.compactMap { sample -> String? in
            guard let data = try? encoder.encode(sample) else { return nil }
            return String(data: data, encoding: .utf8)
        }
        guard !lines.isEmpty else { return }
        let text = lines.joined(separator: "\n") + "\n"
        guard let data = text.data(using: .utf8) else { return }

        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Añade una tanda cruda (formato 2) al mismo fichero.
    ///
    /// Mismo fichero a propósito: las tandas viejas (una línea por golpe) y las nuevas
    /// (una línea por tanda) conviven, se exportan juntas y se suben juntas. Quien lee
    /// distingue el formato por línea.
    public func appendTanda(_ tanda: TandaCruda) {
        guard let data = try? encoder.encode(tanda),
              let linea = String(data: data, encoding: .utf8),
              let bytes = (linea + "\n").data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: bytes)
        } else {
            try? bytes.write(to: url, options: .atomic)
        }
    }

    /// Los pares (etiqueta, rasgos del golpe) de todo el fichero, vengan del formato que
    /// vengan. Es lo que comen la calibración y el panel de precisión.
    public func paresEtiquetados() -> [(ShotType, ShotFeatures)] {
        guard exists, let texto = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        var pares: [(ShotType, ShotFeatures)] = []
        for linea in texto.split(separator: "\n") where !linea.isEmpty {
            guard let data = linea.data(using: .utf8) else { continue }
            // Primero el formato nuevo; si no cuela, el viejo. Una línea corrupta no
            // tira el fichero.
            if let tanda = try? decoder.decode(TandaCruda.self, from: data), tanda.formato >= 2 {
                pares.append(contentsOf: tanda.golpes.map { (tanda.label, $0.features) })
            } else if let muestra = try? decoder.decode(TrainingSample.self, from: data) {
                pares.append((muestra.label, muestra.heuristicFeatures))
            }
        }
        return pares
    }

    /// Cuenta líneas sin parsear: es lo que se enseña en la UI mientras se graba.
    public func count() -> Int {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
        return text.split(separator: "\n").filter { !$0.isEmpty }.count
    }

    /// Una línea corrupta se salta; el resto del fichero sigue sirviendo.
    public func readAll() -> [TrainingSample] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            guard let data = line.data(using: .utf8) else { return nil }
            return try? decoder.decode(TrainingSample.self, from: data)
        }
    }

    /// Cuántas muestras hay de cada tipo. Sirve para saber qué falta por grabar.
    public func countsByLabel() -> [String: Int] {
        readAll().reduce(into: [String: Int]()) { counts, sample in
            counts[sample.label.wireName, default: 0] += 1
        }
    }

    public func clear() {
        try? fileManager.removeItem(at: url)
    }
}
