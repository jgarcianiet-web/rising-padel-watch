import PadelCore
import SwiftUI

/// La tarjeta "¿Acertó el reloj?" de la ficha de sesión: invita a revisar los
/// recuentos y, una vez revisados, enseña la precisión medida.
///
/// Esta revisión es la pieza más valiosa que puede aportar quien juega: la
/// verdad-terreno de la detección. Sus correcciones mandan en la liga y en los
/// objetivos, y la comparación con lo que contó el reloj es la medida real de la
/// precisión del detector.
struct SessionReviewCard: View {
    let session: PadelSession
    @State private var revisando = false

    var body: some View {
        PadelCard(title: "¿Acertó el reloj?", icon: "checkmark.seal.fill") {
            VStack(alignment: .leading, spacing: 10) {
                if let precision = session.reviewAccuracy {
                    HStack(spacing: 12) {
                        Text("\(Int((precision * 100).rounded()))%")
                            .font(.system(size: 30, weight: .heavy, design: .rounded))
                            .foregroundStyle(precision >= 0.85 ? T.verde : Color.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Precisión del reloj en esta sesión")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(T.tinta)
                            Text("Según tu revisión. La liga y los objetivos usan tus recuentos.")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(T.tintaSuave)
                        }
                    }
                    Button("Volver a revisar") { revisando = true }
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                } else {
                    Text("Repasa los recuentos y corrige los que no cuadren. "
                         + "Tus correcciones mandan en la liga y en los objetivos, "
                         + "y miden cuánto acierta el reloj de verdad.")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(T.tintaSuave)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        revisando = true
                    } label: {
                        Text("Revisar recuentos")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .sheet(isPresented: $revisando) {
            SessionReviewSheet(session: session)
        }
    }
}

/// La hoja de corrección: cada tipo con el recuento del reloj y un ajuste directo.
struct SessionReviewSheet: View {
    let session: PadelSession

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var liga: LigaModel
    @Environment(\.dismiss) private var dismiss

    /// Recuentos editables por `wireName`. Arrancan en lo que contó el reloj.
    @State private var counts: [String: Int] = [:]

    /// Los tipos que se revisan: lo que el reloj detectó más los golpes altos, que
    /// son los que más se confunden entre sí — aunque el reloj no haya contado
    /// ninguno, poder decir "fueron 3 smashes" es justo el caso interesante.
    private var tipos: [ShotType] {
        let detectados = Set(session.shotsByType.keys)
        let altos: Set<ShotType> = [.bandeja, .vibora, .smash]
        return ShotType.allCases.filter {
            $0 != .unknown && (detectados.contains($0) || altos.contains($0))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(tipos, id: \.self) { tipo in
                        Stepper(value: binding(tipo), in: 0...199) {
                            HStack {
                                Text(tipo.label)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                Spacer()
                                Text("\(counts[tipo.wireName] ?? 0)")
                                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(cambiado(tipo) ? T.pista : T.tinta)
                            }
                        }
                    }
                } header: {
                    Text("El reloj contó \(session.totalShots) golpeos")
                } footer: {
                    Text("Deja cada recuento en lo que de verdad pasó en la pista. "
                         + "Lo que no toques se queda como lo contó el reloj.")
                }
            }
            .navigationTitle("Revisar recuentos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { guardar() }
                        .fontWeight(.bold)
                }
            }
        }
        .onAppear {
            guard counts.isEmpty else { return }
            // Se parte de la revisión anterior si la hay; si no, del reloj.
            let base = session.effectiveShotsByType
            for tipo in tipos { counts[tipo.wireName] = base[tipo] ?? 0 }
        }
    }

    private func binding(_ tipo: ShotType) -> Binding<Int> {
        Binding(
            get: { counts[tipo.wireName] ?? 0 },
            set: { counts[tipo.wireName] = $0 }
        )
    }

    private func cambiado(_ tipo: ShotType) -> Bool {
        (counts[tipo.wireName] ?? 0) != (session.shotsByType[tipo] ?? 0)
    }

    private func guardar() {
        // Solo se guardan los tipos que difieren del reloj: la revisión es la lista
        // de correcciones, no una copia de todos los recuentos.
        let corregidos = counts.filter { wire, valor in
            valor != (session.shotsByType[ShotType.fromWire(wire)] ?? 0)
        }
        model.applyReview(sessionId: session.sessionId, correctedCounts: corregidos)

        // Si el partido ya estaba en la liga (o se guarda solo), se reescribe con los
        // recuentos corregidos: mismo id, actualiza en vez de duplicar.
        if let actualizada = model.sessions.first(where: { $0.sessionId == session.sessionId }),
           actualizada.score != nil,
           liga.matches.contains(where: { $0.id == actualizada.startedAtEpochMs })
            || UserDefaults.standard.bool(forKey: "ligaAutoGuardar") {
            liga.saveMatch(from: actualizada, playerAverage: model.playerAverageLevel)
        }
        dismiss()
    }
}
