import SwiftUI

/// El panel de un club (§36.19): las cuentas de arriba, quién está dentro y con qué
/// papel, y las ligas que cuelgan de él.
///
/// El club es el contenedor de la competición contra otros — nada que ver con la Liga
/// Personal del móvil (ver la cabecera de `CompeticionModel.swift`).
struct ClubView: View {
    @EnvironmentObject private var competicion: CompeticionModel

    let clubId: Int
    /// El nombre ya conocido, para no dejar la cabecera vacía mientras carga.
    var nombreConocido: String = ""

    @State private var panel: PanelDeClub?
    @State private var cargando = true
    @State private var uniendome = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let panel {
                    resumen(panel)
                    entrada(panel)
                    miembros(panel)
                    ligas(panel)
                } else if cargando {
                    ProgressView().padding(.top, 40)
                } else {
                    Text("No se pudo abrir este club. Comprueba el número y que sigues "
                         + "teniendo conexión.")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(T.tintaSuave)
                        .multilineTextAlignment(.center)
                        .padding(.top, 40)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(T.fondo)
        .navigationTitle(panel?.club.nombre ?? nombreConocido)
        .navigationBarTitleDisplayMode(.inline)
        .task { await cargar() }
        .refreshable { await cargar() }
    }

    private func cargar() async {
        cargando = true
        panel = await competicion.club(clubId)
        cargando = false
    }

    // MARK: El resumen del §36.19

    /// Las tres cuentas del club. Vienen calculadas del servidor: son cuentas exactas de
    /// filas, no estimaciones, y recalcularlas aquí solo serviría para que un día
    /// dijeran algo distinto que el panel del servidor.
    private func resumen(_ panel: PanelDeClub) -> some View {
        PadelCard(title: "El club en números", icon: "chart.bar.fill") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    StatTile(
                        label: "Jugadores", value: "\(panel.resumen.jugadores)",
                        icon: "figure.tennis", tint: T.pista
                    )
                    StatTile(
                        label: "Entrenadores", value: "\(panel.resumen.entrenadores)",
                        icon: "megaphone.fill", tint: T.tinta
                    )
                    StatTile(
                        label: "Ligas", value: "\(panel.resumen.ligas)",
                        icon: "trophy.fill", tint: T.lima
                    )
                }
                if let ciudad = panel.club.ciudad, !ciudad.isEmpty {
                    Text("\(ciudad) · club nº \(panel.club.id)")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(T.tintaSuave)
                } else {
                    Text("Club nº \(panel.club.id) · pasa el número a quien quieras dentro")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(T.tintaSuave)
                }
            }
        }
    }

    /// El botón de entrar, solo para quien está fuera. Quien ya es miembro ve su papel:
    /// un botón de "unirme" que no hace nada es peor que no tener botón.
    @ViewBuilder
    private func entrada(_ panel: PanelDeClub) -> some View {
        if let mio = miPapel(panel) {
            PadelCard {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(T.verde)
                    Text("Estás dentro como \(CompeticionTextos.papel(mio).lowercased())")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(T.tinta)
                    Spacer()
                }
            }
        } else {
            PadelCard {
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        unirme()
                    } label: {
                        Text("Unirme a este club")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(uniendome)
                    Text("Entrarás como jugador. Los papeles los cambia quien administra "
                         + "el club.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(T.tintaSuave)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func miPapel(_ panel: PanelDeClub) -> String? {
        guard let alias = competicion.alias, !alias.isEmpty else { return nil }
        return panel.miembros.first {
            $0.alias.caseInsensitiveCompare(alias) == .orderedSame
        }?.papel
    }

    private func unirme() {
        uniendome = true
        Task {
            if await competicion.unirmeAlClub(clubId) {
                await cargar()
            }
            uniendome = false
        }
    }

    // MARK: Miembros

    private func miembros(_ panel: PanelDeClub) -> some View {
        PadelCard(title: "Miembros", icon: "person.3.fill") {
            VStack(spacing: 8) {
                ForEach(panel.miembros) { miembro in
                    HStack(spacing: 10) {
                        AvatarView(alias: miembro.alias, size: 32)
                        Text("@\(miembro.alias)")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(T.tinta)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(CompeticionTextos.papel(miembro.papel).uppercased())
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .kerning(0.8)
                            .foregroundStyle(T.pista)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(T.pistaTinte, in: Capsule())
                    }
                }
                if panel.miembros.isEmpty {
                    Text("Este club todavía no tiene a nadie dentro.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(T.tintaSuave)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: Ligas del club

    private func ligas(_ panel: PanelDeClub) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Ligas del club", icon: "trophy.fill")
            if panel.ligas.isEmpty {
                PadelCard {
                    Text("Aún no hay ligas colgadas de este club. Se crean desde "
                         + "Competición eligiendo el club.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(T.tintaSuave)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(panel.ligas) { liga in
                NavigationLink(value: DestinoDeCompeticion.liga(liga.id, liga.nombre)) {
                    PadelCard {
                        HStack(spacing: 12) {
                            Text(liga.nombre)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(T.tinta)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            EstadoDeCompeticion(estado: liga.estado)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(T.tintaSuave)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
