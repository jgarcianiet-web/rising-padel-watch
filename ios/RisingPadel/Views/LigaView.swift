import PadelCore
import SwiftUI
import UniformTypeIdentifiers

/// La Liga Personal, viviendo dentro de esta app.
///
/// Es la fusión que faltaba: el historial de partidos de la app Expo y las sesiones del
/// reloj en el mismo sitio. La puerta de entrada del historial existente es la copia de
/// seguridad de la app de liga — importa aquí sin transformación, y el export de aquí
/// reimporta allí, así que ningún dato queda rehén de ninguna de las dos apps.
struct LigaView: View {
    @EnvironmentObject private var liga: LigaModel
    @State private var importing = false
    @State private var exportURL: ExportItem?
    @State private var creating = false
    @State private var editingAjustes = false

    var body: some View {
        NavigationStack {
            Group {
                if liga.matches.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .background(T.fondo)
            .navigationTitle("Liga")
            .navigationDestination(for: Int64.self) { matchId in
                LigaMatchDetailView(matchId: matchId)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        creating = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Nuevo partido")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            editingAjustes = true
                        } label: {
                            Label("Objetivos y perfil", systemImage: "person.crop.circle")
                        }
                        Button {
                            importing = true
                        } label: {
                            Label("Importar copia de la liga", systemImage: "square.and.arrow.down")
                        }
                        Button {
                            exportURL = liga.exportBackup().map(ExportItem.init)
                        } label: {
                            Label("Exportar copia", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $creating) {
                LigaMatchFormView().environmentObject(liga)
            }
            .sheet(isPresented: $editingAjustes) {
                LigaAjustesView(liga: liga).environmentObject(liga)
            }
            .fileImporter(
                isPresented: $importing,
                allowedContentTypes: [.json, .plainText]
            ) { result in
                guard case let .success(url) = result else { return }
                // Fuera del sandbox de la app hace falta pedir acceso explícito.
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) {
                    liga.importBackup(data)
                }
            }
            .sheet(item: $exportURL) { item in
                ShareSheet(url: item.url)
            }
            .alert(
                liga.message ?? "",
                isPresented: Binding(
                    get: { liga.message != nil },
                    set: { if !$0 { liga.message = nil } }
                )
            ) {
                Button("Vale", role: .cancel) { liga.message = nil }
            }
        }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 12) {
                summaryCard
                CoachCard()
                ForEach(liga.matches) { match in
                    // NavigationLink por valor: la ficha busca el partido por id, así
                    // que editarlo desde dentro la redibuja sin volver atrás.
                    NavigationLink(value: match.id) {
                        matchCard(match)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private var summaryCard: some View {
        let matches = liga.matches
        let victorias = matches.filter { $0.resultado == "victoria" }.count
        let racha = LigaMetrics.racha(matches)
        // El nivel medio de sesión sale del reloj (o de la curva si el campo directo
        // falta), como en el panel de la app Expo.
        let conNivel = matches.compactMap(LigaMetrics.nivelDeSesion)

        // La tarjeta es la puerta del panel de temporada: rachas, evolución y stats.
        return NavigationLink {
            LigaSeasonView()
        } label: {
            PadelCard(title: "Temporada", icon: "trophy.fill") {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        StatTile(label: "Partidos", value: "\(matches.count)")
                        StatTile(
                            label: "Victorias",
                            value: matches.isEmpty
                                ? "–"
                                : "\(victorias) (\(victorias * 100 / matches.count)%)",
                            tint: T.verde
                        )
                        StatTile(
                            label: racha > 0 ? "Racha 🔥" : "Racha",
                            value: matches.isEmpty ? "–" : "\(racha)",
                            tint: racha > 0 ? T.bola : T.tintaSuave
                        )
                        StatTile(
                            label: "Nivel sesión",
                            value: conNivel.isEmpty
                                ? "–"
                                : String(format: "%.1f", conNivel.reduce(0, +) / Double(conNivel.count)),
                            tint: T.pista
                        )
                    }
                    HStack(spacing: 4) {
                        Text("Ver la temporada entera")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                        Spacer()
                    }
                    .foregroundStyle(T.pista)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func matchCard(_ match: LigaMatch) -> some View {
        PadelCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(match.fecha)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .kerning(1.2)
                            .foregroundStyle(T.tintaSuave)
                        if !match.sets.isEmpty {
                            Text(match.sets)
                                .font(.system(size: 20, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(T.tinta)
                        } else {
                            Text(match.tipo)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(T.tinta)
                        }
                    }
                    Spacer()
                    OutcomeBadge(text: badge(match.resultado), color: badgeColor(match.resultado))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(T.tintaSuave)
                        .padding(.top, 6)
                }

                HStack(spacing: 12) {
                    if let nivel = match.nivelBand {
                        tag(String(format: "nivel %.1f", nivel), icon: "gauge.with.needle")
                    }
                    if let total = match.totalGolpes {
                        tag("\(total) golpeos", icon: "figure.tennis")
                    }
                    if !match.club.isEmpty {
                        tag(match.club, icon: "mappin")
                    }
                    Spacer()
                }
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                liga.delete(match.id)
            } label: {
                Label("Borrar partido", systemImage: "trash")
            }
        }
    }

    private func tag(_ text: String, icon: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9))
            Text(text).font(.system(size: 12, weight: .medium, design: .rounded)).monospacedDigit()
        }
        .foregroundStyle(T.tintaSuave)
    }

    private func badge(_ resultado: String) -> String {
        switch resultado {
        case "victoria": return "V"
        case "empate": return "E"
        default: return "D"
        }
    }

    private func badgeColor(_ resultado: String) -> Color {
        switch resultado {
        case "victoria": return T.verde
        case "empate": return T.tintaSuave
        default: return T.rojo
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("La liga, todavía vacía", systemImage: "trophy")
        } description: {
            Text("Guarda una sesión como partido desde su detalle, apunta uno a mano "
                 + "con el botón +, o importa la copia de seguridad de tu app Liga "
                 + "Pádel con el menú de arriba: todo tu historial aparecerá aquí.")
        } actions: {
            Button {
                creating = true
            } label: {
                Label("Apuntar un partido", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

/// Envoltorio mínimo del share sheet del sistema para exportar el backup.
private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Caja Identifiable para el sheet: conformar URL retroactivamente avisa en Swift 6.
private struct ExportItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
