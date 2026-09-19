import AVFoundation
import CoreMedia
import Foundation
import PadelCore
import SwiftUI

/// El almacén del VIDEO LAB: los vídeos importados y su etiquetado.
///
/// Mismo patrón que `LigaModel`: un único JSON con todo el estado en Application Support,
/// que se lee al arrancar y se reescribe entero en cada cambio. Es poco elegante y es
/// deliberado — el volumen es de decenas de vídeos, no de miles, y un solo fichero no
/// puede quedarse a medias entre dos estructuras.
///
/// Los vídeos en sí **no** van dentro del JSON: se copian a una carpeta aparte y el
/// etiquetado guarda solo el nombre del fichero.
@MainActor
final class VideoLabModel: ObservableObject {

    @Published private(set) var etiquetados: [EtiquetadoDeVideo] = []
    @Published var message: String?
    /// Importar copia un fichero que puede pesar cientos de megas: la pantalla necesita
    /// saber que está en ello o parece que el botón no hizo nada.
    @Published private(set) var importando = false

    private let fileURL: URL
    private let mediaDir: URL

    init(fileURL: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.fileURL = fileURL ?? base.appendingPathComponent("videolab/etiquetados.json")
        self.mediaDir = (fileURL?.deletingLastPathComponent() ?? base.appendingPathComponent("videolab"))
            .appendingPathComponent("media", isDirectory: true)
        prepararCarpetas()
        load()
    }

    /// El más nuevo primero, como el historial de sesiones y el de la liga.
    var ordenados: [EtiquetadoDeVideo] {
        etiquetados.sorted { $0.creado > $1.creado }
    }

    func etiquetado(_ id: UUID) -> EtiquetadoDeVideo? {
        etiquetados.first { $0.id == id }
    }

    /// Dónde está el vídeo ahora mismo. Se resuelve en cada uso y no se guarda: el
    /// contenedor de la app cambia de ruta al actualizar.
    func urlDelVideo(_ etiquetado: EtiquetadoDeVideo) -> URL {
        mediaDir.appendingPathComponent(etiquetado.fichero)
    }

    /// El fichero puede no estar: alguien pudo borrarlo desde Archivos, o la copia se
    /// quedó a medias. Mejor decirlo que enseñar un reproductor negro para siempre.
    func existeVideo(_ etiquetado: EtiquetadoDeVideo) -> Bool {
        FileManager.default.fileExists(atPath: urlDelVideo(etiquetado).path)
    }

    // MARK: Importar

    /// Copia el vídeo dentro de la app y crea su etiquetado. Devuelve el id para poder
    /// abrir la pantalla de etiquetado justo después.
    ///
    /// Se copia y no se referencia el original: un vídeo del carrete puede borrarse
    /// desde Fotos, y perder el vídeo dejaría el etiquetado huérfano — que es justo el
    /// trabajo manual que más cuesta rehacer.
    @discardableResult
    func importar(desde origen: URL, nombre: String, tipo: ShotType = .bandeja) async -> UUID? {
        importando = true
        defer { importando = false }

        let id = UUID()
        // La extensión se conserva: AVFoundation elige el demuxer por el tipo del
        // fichero, y un .mov renombrado a .dat no se reproduce.
        let sufijo = origen.pathExtension.isEmpty ? "mov" : origen.pathExtension
        let fichero = "\(id.uuidString).\(sufijo)"
        let destino = mediaDir.appendingPathComponent(fichero)

        do {
            try await Self.copiar(origen, a: destino)
        } catch {
            message = "No se pudo copiar el vídeo a la app"
            return nil
        }

        let (duracion, ancla) = await Self.leerMetadatos(destino)
        let nuevo = EtiquetadoDeVideo(
            id: id,
            nombre: nombre.isEmpty ? Self.nombrePorDefecto(ancla) : nombre,
            fichero: fichero,
            duracion: duracion,
            tipo: tipo,
            creado: Int64(Date().timeIntervalSince1970 * 1000),
            ancla: ancla
        )
        etiquetados.append(nuevo)
        save()
        // Sin aviso de "importado": la pantalla de etiquetado se abre sola justo
        // después, y una alerta encima de una pantalla que acaba de entrar se come el
        // primer toque. Lo que sí hay que saber —que el vídeo no trae hora de inicio—
        // se ve allí mismo, en la tarjeta del ancla.
        return id
    }

    /// Copiar fuera del hilo principal: un vídeo de 4K de dos minutos son cientos de
    /// megas y hacerlo en el main actor congela la interfaz mientras tanto.
    private nonisolated static func copiar(_ origen: URL, a destino: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            try? FileManager.default.removeItem(at: destino)
            try FileManager.default.copyItem(at: origen, to: destino)
        }.value
    }

    /// Duración y fecha de grabación del fichero ya copiado.
    ///
    /// La fecha sale de los metadatos QuickTime que escribe la cámara del iPhone
    /// (`com.apple.quicktime.creationdate`). Un vídeo que ha pasado por WhatsApp o por
    /// una exportación los pierde: en ese caso no se inventa nada y el ancla queda sin
    /// fijar, para que el usuario la ponga si le hace falta.
    private nonisolated static func leerMetadatos(_ url: URL) async -> (Double, AnclaDeVideo) {
        let asset = AVURLAsset(url: url)
        let segundos = (try? await asset.load(.duration)).map(CMTimeGetSeconds) ?? 0
        let duracion = segundos.isFinite && segundos > 0 ? segundos : 0

        guard let item = try? await asset.load(.creationDate),
              let fecha = try? await item.load(.dateValue) else {
            return (duracion, .sinFijar)
        }
        return (
            duracion,
            AnclaDeVideo(epochMs: Int64(fecha.timeIntervalSince1970 * 1000), origen: .metadatos)
        )
    }

    private static func nombrePorDefecto(_ ancla: AnclaDeVideo) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM HH:mm"
        return "Entreno \(formatter.string(from: ancla.fecha ?? Date()))"
    }

    // MARK: Etiquetar

    /// Marca un golpe en el instante que se está viendo.
    ///
    /// El tipo por defecto es el del vídeo ("este vídeo contiene bandejas"), pero cada
    /// marca guarda el suyo: en una tanda real se cuela alguna víbora, y obligar a que
    /// todas las marcas sean del mismo tipo convertiría el etiquetado en ruido.
    func marcar(_ id: UUID, segundos: Double, tipo: ShotType? = nil) {
        guard let index = etiquetados.firstIndex(where: { $0.id == id }) else { return }
        let marca = MarcaDeVideo(
            segundos: max(0, segundos),
            tipo: tipo ?? etiquetados[index].tipo
        )
        etiquetados[index].marcas.append(marca)
        save()
    }

    func borrarMarca(_ marcaId: UUID, de id: UUID) {
        guard let index = etiquetados.firstIndex(where: { $0.id == id }) else { return }
        etiquetados[index].marcas.removeAll { $0.id == marcaId }
        save()
    }

    /// Cambia el golpe que contiene el vídeo.
    ///
    /// No reescribe las marcas ya puestas a propósito: si alguien corrigió a mano una
    /// víbora dentro de un vídeo de bandejas, cambiar el selector no puede tirar esa
    /// corrección. Solo manda sobre las marcas nuevas.
    func fijarTipo(_ tipo: ShotType, en id: UUID) {
        guard let index = etiquetados.firstIndex(where: { $0.id == id }) else { return }
        etiquetados[index].tipo = tipo
        save()
    }

    func renombrar(_ nombre: String, en id: UUID) {
        guard let index = etiquetados.firstIndex(where: { $0.id == id }),
              !nombre.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        etiquetados[index].nombre = nombre
        save()
    }

    /// Fija a mano el instante en que empieza el vídeo, para los ficheros que no traen
    /// fecha de grabación. Ver `EtiquetadoDeVideo.epochMs(de:)`.
    func fijarAncla(_ fecha: Date, en id: UUID) {
        guard let index = etiquetados.firstIndex(where: { $0.id == id }) else { return }
        etiquetados[index].ancla = AnclaDeVideo(
            epochMs: Int64(fecha.timeIntervalSince1970 * 1000), origen: .manual
        )
        save()
    }

    /// Borra el etiquetado y el vídeo copiado. Los dos: dejar el fichero sería acumular
    /// gigas invisibles que el usuario no puede encontrar ni borrar desde la app.
    func borrar(_ id: UUID) {
        guard let etiquetado = etiquetado(id) else { return }
        try? FileManager.default.removeItem(at: urlDelVideo(etiquetado))
        etiquetados.removeAll { $0.id == id }
        save()
    }

    // MARK: Exportar

    /// El etiquetado como JSON legible, para compartirlo con el share sheet.
    ///
    /// Sale con sangrado y las claves ordenadas porque este fichero se lee a ojo y se
    /// revisa en un diff: es la verdad-terreno con la que se juzgará al detector, y una
    /// línea de 40 KB no se revisa.
    ///
    /// Es el modelo tal cual, no un formato aparte: así el JSON exportado vuelve a
    /// entrar sin transformación el día que haya import, y el instante de época de cada
    /// marca se calcula de `ancla` + `segundos` sin tener que duplicarlo en el fichero.
    func exportar(_ id: UUID) -> URL? {
        guard var etiquetado = etiquetado(id) else { return nil }
        // Se exporta con las marcas ya ordenadas: quien lo consuma no debería tener que
        // volver a ordenarlas para leer la línea temporal.
        etiquetado.marcas = etiquetado.marcasOrdenadas

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(etiquetado) else { return nil }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("videolab-\(Self.slug(etiquetado.nombre)).json")
        guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        return url
    }

    /// Nombre de fichero sin sorpresas: el nombre del vídeo lo escribe el usuario y
    /// puede traer barras o acentos, que en un nombre de fichero compartido molestan.
    private static func slug(_ texto: String) -> String {
        let plano = texto.folding(options: [.diacriticInsensitive], locale: .current).lowercased()
        let limpio = plano.map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return String(limpio).prefix(40).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    // MARK: Persistencia

    private func prepararCarpetas() {
        try? FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        // Los vídeos no van a la copia de iCloud: son el dato más pesado de la app con
        // diferencia y se pueden volver a importar del carrete. El etiquetado (el
        // trabajo manual de verdad) sí se respalda, que es un JSON de nada.
        var carpeta = mediaDir
        var valores = URLResourceValues()
        valores.isExcludedFromBackup = true
        try? carpeta.setResourceValues(valores)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode([EtiquetadoDeVideo].self, from: data)
        else { return }
        etiquetados = stored
    }

    private func save() {
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let data = try? JSONEncoder().encode(etiquetados) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
