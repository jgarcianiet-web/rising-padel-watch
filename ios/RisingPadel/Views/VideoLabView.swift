import CoreTransferable
import PadelCore
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// VIDEO LAB: los vídeos de entrenamiento con sus golpes marcados a mano.
///
/// Por qué existe: el reloj cuenta golpes mirando una señal, y hasta ahora la única
/// forma de saber si acertaba era la etiqueta que el jugador le ponía a la tanda entera
/// ("estos 40 son bandejas"). Eso mide el tipo, pero no mide **cuántos** ni **cuándo**.
/// El vídeo sí: un ojo humano ve el golpe y lo pone en el segundo 3. Marcar a mano es
/// tedioso y por eso está aquí y no en el flujo normal — es trabajo de laboratorio, no
/// de después del partido.
///
/// No hay visión artificial y no la va a haber por ahora: un modelo que detectara los
/// golpes en el vídeo necesitaría exactamente estos vídeos etiquetados para entrenarse.
/// Primero el corpus.
struct VideoLabView: View {
    /// El laboratorio se lleva su propio almacén: es un dominio con su fichero y su
    /// carpeta de medios, como la liga. La vista se instancia sin nada — `VideoLabView()`.
    @StateObject private var lab = VideoLabModel()
    @Environment(\.dismiss) private var dismiss

    @State private var elegido: PhotosPickerItem?
    /// La ruta de navegación es explícita para poder empujar la pantalla de etiquetado
    /// nada más importar: el usuario acaba de elegir un vídeo, lo que quiere es marcarlo.
    @State private var ruta: [UUID] = []

    var body: some View {
        NavigationStack(path: $ruta) {
            Group {
                if lab.etiquetados.isEmpty {
                    vacio
                } else {
                    lista
                }
            }
            .background(T.fondo)
            // El observador vive aquí y no dentro del selector: hay dos selectores en
            // pantalla cuando el laboratorio está vacío (el del "+" y el del estado
            // vacío) y con un `onChange` en cada uno el mismo vídeo se importaba dos
            // veces, con sus dos copias en disco.
            .onChange(of: elegido) { _, nuevo in
                guard let nuevo else { return }
                Task { await importar(nuevo) }
            }
            .navigationTitle("Video Lab")
            .navigationDestination(for: UUID.self) { id in
                VideoEtiquetadoView(id: id, lab: lab)
            }
            .toolbar {
                // El laboratorio se abre a pantalla completa, y a pantalla completa no
                // hay gesto de arrastrar hacia abajo que valga: sin este botón la única
                // salida era matar la app. Pasó de verdad.
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cerrar") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if lab.importando {
                        ProgressView()
                    } else {
                        selectorDeVideo {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .alert(
                lab.message ?? "",
                isPresented: Binding(
                    get: { lab.message != nil },
                    set: { if !$0 { lab.message = nil } }
                )
            ) {
                Button("Vale", role: .cancel) { lab.message = nil }
            }
        }
    }

    // MARK: Importar

    /// `PhotosPicker` y no `.fileImporter`: los vídeos de entrenamiento se graban con el
    /// móvil apoyado en la valla y acaban en el carrete, no en Archivos. Además el
    /// selector de Fotos corre fuera del proceso de la app, así que **no hace falta pedir
    /// permiso de fototeca** —ni la cadena `NSPhotoLibraryUsageDescription`— y el usuario
    /// solo comparte el vídeo que elige. Con `.fileImporter` habría que andar navegando
    /// carpetas y pidiendo acceso con ámbito de seguridad para el caso raro.
    private func selectorDeVideo<Etiqueta: View>(
        @ViewBuilder label: () -> Etiqueta
    ) -> some View {
        PhotosPicker(selection: $elegido, matching: .videos, label: label)
    }

    @MainActor
    private func importar(_ item: PhotosPickerItem) async {
        defer { elegido = nil }
        guard let video = try? await item.loadTransferable(type: VideoDelCarrete.self) else {
            lab.message = "No se pudo leer ese vídeo del carrete"
            return
        }
        // El temporal que entrega PhotosUI ya está copiado por nosotros; en cuanto el
        // almacén se queda con el suyo, este sobra y son megas en el disco.
        defer { try? FileManager.default.removeItem(at: video.url) }
        if let id = await lab.importar(desde: video.url, nombre: "") {
            ruta = [id]
        }
    }

    // MARK: Lista

    private var lista: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(lab.ordenados) { etiquetado in
                    NavigationLink(value: etiquetado.id) {
                        tarjeta(etiquetado)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            lab.borrar(etiquetado.id)
                        } label: {
                            Label("Borrar vídeo y etiquetado", systemImage: "trash")
                        }
                    }
                }
                explicacion
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func tarjeta(_ etiquetado: EtiquetadoDeVideo) -> some View {
        PadelCard {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(etiquetado.nombre)
                        .font(.padelTitle())
                        .foregroundStyle(T.tinta)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(ShotBreakdownChart.etiqueta(etiquetado.tipo).uppercased())
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .kerning(1)
                            .foregroundStyle(T.lima)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(T.limaTinte, in: Capsule())
                        Text("\(etiquetado.marcas.count) marcas · \(Self.duracion(etiquetado.duracion))")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(T.tintaSuave)
                    }

                    // El ancla es lo que decide si este vídeo podrá cruzarse algún día
                    // con las tandas del reloj, así que se ve desde la lista y no
                    // enterrada dentro: un vídeo sin ancla se arregla en 5 segundos si
                    // te enteras el mismo día, y es irrecuperable seis meses después.
                    if etiquetado.ancla.epochMs == nil {
                        Label("Sin hora de inicio", systemImage: "clock.badge.questionmark")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(T.rojo)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(T.tintaSuave)
            }
        }
    }

    private var explicacion: some View {
        PadelCard(title: "Para qué sirve", icon: "questionmark.circle") {
            Text("""
                Marca a mano cada golpe que ves en el vídeo. Esa lista es la verdad: con \
                ella se podrá medir cuántos golpes se le escapan al reloj y cuáles \
                confunde, en vez de fiarse de la etiqueta de la tanda entera.
                """)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(T.tintaSuave)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var vacio: some View {
        ContentUnavailableView {
            Label("El laboratorio, vacío", systemImage: "film.stack")
        } description: {
            Text("Importa un vídeo de un entrenamiento, di qué golpe contiene y marca "
                 + "cada golpe según lo ves. Queda una línea temporal (00:03 — BANDEJA) "
                 + "exportable para cruzarla con lo que grabó el reloj.")
        } actions: {
            selectorDeVideo {
                Label("Importar un vídeo", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    /// `mm:ss`, el mismo formato que la línea temporal.
    static func duracion(_ segundos: Double) -> String {
        let total = Int(segundos.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

/// El vídeo que sale del carrete, como fichero.
///
/// `PhotosPickerItem` entrega el vídeo en un temporal que el sistema borra en cuanto
/// vuelve el closure de importación, así que hay que copiarlo **dentro** del closure:
/// quedarse con la URL recibida y leerla después es el fallo clásico, y se manifiesta
/// como "el fichero no existe" solo en dispositivo y solo con vídeos grandes.
struct VideoDelCarrete: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { recibido in
            let sufijo = recibido.file.pathExtension.isEmpty ? "mov" : recibido.file.pathExtension
            let destino = FileManager.default.temporaryDirectory
                .appendingPathComponent("videolab-\(UUID().uuidString)")
                .appendingPathExtension(sufijo)
            try? FileManager.default.removeItem(at: destino)
            try FileManager.default.copyItem(at: recibido.file, to: destino)
            return VideoDelCarrete(url: destino)
        }
    }
}
