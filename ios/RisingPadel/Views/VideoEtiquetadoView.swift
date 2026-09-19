import AVKit
import CoreMedia
import PadelCore
import SwiftUI
import UIKit

/// La mesa de trabajo del VIDEO LAB: ver el vídeo y marcar cada golpe según pasa.
///
/// El botón de marcar es enorme y está debajo del reproductor porque así se usa esto de
/// verdad: mirando el vídeo, no la interfaz. Todo lo demás (tipo, nombre, hora de
/// inicio, exportar) está más abajo, fuera del camino.
struct VideoEtiquetadoView: View {
    /// Se guarda el id y no el etiquetado: cada marca lo cambia, y la vista tiene que
    /// redibujarse con lo que hay en el almacén. Mismo patrón que `LigaMatchDetailView`.
    let id: UUID
    @ObservedObject var lab: VideoLabModel

    @State private var reproductor: AVPlayer?
    /// El token del observador periódico. Hay que quitarlo antes de soltar el
    /// reproductor: si no, AVFoundation revienta al liberar un player con observadores.
    @State private var observador: Any?
    /// Segundo que se está viendo, refrescado 10 veces por segundo para el contador.
    @State private var instante: Double = 0
    @State private var nombre = ""
    @State private var fechaAncla = Date()
    @State private var exportando: VideoExportItem?

    /// Los tipos que se pueden marcar. `unknown` no es un golpe, es la ausencia de
    /// clasificación — igual que en el mando de tandas.
    private var grabables: [ShotType] { ShotType.allCases.filter { $0 != .unknown } }

    var body: some View {
        Group {
            if let etiquetado = lab.etiquetado(id) {
                contenido(etiquetado)
            } else {
                ContentUnavailableView("Ese vídeo ya no está", systemImage: "film")
            }
        }
        .background(T.fondo)
        .navigationTitle("Etiquetar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        exportando = lab.exportar(id).map(VideoExportItem.init)
                    } label: {
                        Label("Exportar etiquetado (JSON)", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $exportando) { item in
            VideoShareSheet(url: item.url)
        }
        .onAppear { preparar() }
        .onDisappear { soltar() }
    }

    private func contenido(_ etiquetado: EtiquetadoDeVideo) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                reproductorCard(etiquetado)
                marcarCard(etiquetado)
                lineaTemporalCard(etiquetado)
                tipoCard(etiquetado)
                anclaCard(etiquetado)
                nombreCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: Reproductor

    @ViewBuilder
    private func reproductorCard(_ etiquetado: EtiquetadoDeVideo) -> some View {
        if let reproductor {
            VideoPlayer(player: reproductor)
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else if !lab.existeVideo(etiquetado) {
            // El etiquetado sobrevive aunque el vídeo no: las marcas son el trabajo
            // caro y siguen valiendo para exportarlas.
            PadelCard {
                Label(
                    "El fichero de vídeo ya no está en el móvil. Las marcas se conservan "
                        + "y se pueden exportar, pero no se puede seguir etiquetando.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(T.rojo)
            }
        } else {
            ProgressView().frame(height: 180)
        }
    }

    // MARK: Marcar

    private func marcarCard(_ etiquetado: EtiquetadoDeVideo) -> some View {
        PadelCard {
            VStack(spacing: 12) {
                Text(Self.tiempo(instante))
                    .font(.padelDisplay(44))
                    .monospacedDigit()
                    .foregroundStyle(T.tinta)

                Button {
                    marcar(etiquetado)
                } label: {
                    Label(
                        "MARCAR \(ShotBreakdownChart.etiqueta(etiquetado.tipo).uppercased())",
                        systemImage: "flag.fill"
                    )
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(T.lima)
                .disabled(reproductor == nil)

                // Se marca tarde: entre que ves el golpe y pulsas pasan dos o tres
                // décimas. Retroceder unos segundos y volver a marcar es la forma
                // práctica de afinar, así que los saltos van aquí al lado y no dentro
                // de los controles del reproductor.
                HStack(spacing: 8) {
                    Button { saltar(-3) } label: {
                        Label("3 s atrás", systemImage: "gobackward")
                            .frame(maxWidth: .infinity)
                    }
                    Button { saltar(3) } label: {
                        Label("3 s adelante", systemImage: "goforward")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .disabled(reproductor == nil)
            }
        }
    }

    private func marcar(_ etiquetado: EtiquetadoDeVideo) {
        // El instante bueno es el del reproductor, no el del contador: el contador se
        // refresca cada 100 ms y marcaría hasta una décima tarde.
        let actual = reproductor?.currentTime().seconds ?? instante
        lab.marcar(id, segundos: actual.isFinite ? actual : 0, tipo: etiquetado.tipo)
        // Confirmación en la mano: la vista está en el vídeo, no en la lista de marcas.
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func saltar(_ delta: Double) {
        guard let reproductor else { return }
        let ahora = reproductor.currentTime().seconds
        let destino = max(0, (ahora.isFinite ? ahora : 0) + delta)
        // Sin tolerancia: un salto que cae en el fotograma clave más cercano puede
        // desplazarte varios segundos, y aquí se salta justo para afinar.
        reproductor.seek(
            to: CMTime(seconds: destino, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    // MARK: Línea temporal

    private func lineaTemporalCard(_ etiquetado: EtiquetadoDeVideo) -> some View {
        PadelCard(title: "Línea temporal", icon: "list.bullet") {
            if etiquetado.marcas.isEmpty {
                Text("Todavía no has marcado ningún golpe.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(T.tintaSuave)
            } else {
                VStack(spacing: 0) {
                    ForEach(etiquetado.marcasOrdenadas) { marca in
                        fila(marca)
                        if marca.id != etiquetado.marcasOrdenadas.last?.id {
                            Divider().overlay(T.borde)
                        }
                    }
                    Text("\(etiquetado.marcas.count) golpes marcados")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(T.tintaSuave)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 10)
                }
            }
        }
    }

    private func fila(_ marca: MarcaDeVideo) -> some View {
        HStack(spacing: 10) {
            // Tocar la marca lleva el vídeo a ese instante: revisar lo marcado es la
            // mitad del trabajo, y sin esto habría que buscarlo arrastrando la barra.
            Button {
                saltarA(marca.segundos)
            } label: {
                Text("\(marca.tiempo) — \(ShotBreakdownChart.etiqueta(marca.tipo).uppercased())")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .kerning(0.5)
                    .foregroundStyle(T.tinta)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                lab.borrarMarca(marca.id, de: id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(T.rojo)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Borrar la marca de \(marca.tiempo)")
        }
        .padding(.vertical, 9)
    }

    private func saltarA(_ segundos: Double) {
        reproductor?.seek(
            to: CMTime(seconds: segundos, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    // MARK: Qué contiene el vídeo

    private func tipoCard(_ etiquetado: EtiquetadoDeVideo) -> some View {
        PadelCard(title: "Qué contiene el vídeo", icon: "figure.tennis") {
            VStack(alignment: .leading, spacing: 8) {
                Picker(
                    "Golpe",
                    selection: Binding(
                        get: { etiquetado.tipo },
                        set: { lab.fijarTipo($0, en: id) }
                    )
                ) {
                    ForEach(grabables, id: \.self) { tipo in
                        Text(ShotBreakdownChart.etiqueta(tipo)).tag(tipo)
                    }
                }
                .pickerStyle(.menu)

                Text("Es el golpe con el que se guardan las marcas nuevas. Cambiarlo no "
                     + "toca las que ya hiciste.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(T.tintaSuave)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Ancla temporal

    /// Lo que permitirá cruzar este vídeo con las tandas del reloj. Ver el comentario
    /// largo en `EtiquetadoDeVideo.epochMs(de:)` para lo que falta.
    private func anclaCard(_ etiquetado: EtiquetadoDeVideo) -> some View {
        PadelCard(title: "Hora de inicio del vídeo", icon: "clock") {
            VStack(alignment: .leading, spacing: 10) {
                switch etiquetado.ancla.origen {
                case .metadatos:
                    Label(
                        "Tomada del propio fichero: \(Self.fechaLarga(etiquetado.ancla.fecha))",
                        systemImage: "checkmark.seal.fill"
                    )
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(T.verde)
                case .manual:
                    Label(
                        "Puesta a mano: \(Self.fechaLarga(etiquetado.ancla.fecha))",
                        systemImage: "hand.point.up.left.fill"
                    )
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(T.pista)
                case .ninguno:
                    Label(
                        "Este vídeo no trae fecha de grabación (se pierde al pasar por "
                            + "WhatsApp o al exportar). Sin ella las marcas no se podrán "
                            + "cruzar con las tandas del reloj.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(T.rojo)
                    .fixedSize(horizontal: false, vertical: true)
                }

                DatePicker(
                    "Empezó a",
                    selection: $fechaAncla,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .font(.system(size: 14, design: .rounded))

                Button("Fijar esta hora") { lab.fijarAncla(fechaAncla, en: id) }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))

                // Se dice el límite en pantalla porque afecta a cómo se usa: con el
                // ancla al minuto, cruzar golpe a golpe (van a segundo y medio uno de
                // otro) todavía no sale. Sirve para acotar qué tanda es cuál.
                Text("Al minuto: suficiente para saber qué tanda del reloj corresponde a "
                     + "este vídeo, todavía no para emparejar golpe a golpe.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(T.tintaSuave)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Nombre

    private var nombreCard: some View {
        PadelCard(title: "Nombre", icon: "textformat") {
            TextField("Nombre del vídeo", text: $nombre)
                .font(.system(size: 15, design: .rounded))
                .onSubmit { lab.renombrar(nombre, en: id) }
                // También al salir: casi nadie pulsa "intro" en un campo suelto, y el
                // nombre escrito y no guardado se perdía al volver a la lista.
                .onDisappear { lab.renombrar(nombre, en: id) }
        }
    }

    // MARK: Ciclo de vida del reproductor

    private func preparar() {
        guard let etiquetado = lab.etiquetado(id) else { return }
        nombre = etiquetado.nombre
        fechaAncla = etiquetado.ancla.fecha ?? Date()

        guard reproductor == nil, lab.existeVideo(etiquetado) else { return }
        let player = AVPlayer(url: lab.urlDelVideo(etiquetado))
        observador = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 10),
            queue: .main
        ) { tiempo in
            let segundos = tiempo.seconds
            instante = segundos.isFinite ? segundos : 0
        }
        reproductor = player
    }

    private func soltar() {
        if let observador { reproductor?.removeTimeObserver(observador) }
        observador = nil
        reproductor?.pause()
        reproductor = nil
    }

    // MARK: Formato

    /// `00:03`, el mismo formato que la línea temporal del documento de producto.
    static func tiempo(_ segundos: Double) -> String {
        let total = Int(segundos.rounded(.down))
        return String(format: "%02d:%02d", max(0, total) / 60, max(0, total) % 60)
    }

    private static func fechaLarga(_ fecha: Date?) -> String {
        guard let fecha else { return "sin fecha" }
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy, HH:mm:ss"
        return formatter.string(from: fecha)
    }
}

/// Envoltorio mínimo del share sheet del sistema para sacar el JSON del etiquetado.
private struct VideoShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Caja Identifiable para el sheet: conformar URL retroactivamente avisa en Swift 6.
private struct VideoExportItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
