import PadelCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var liga: LigaModel
    @EnvironmentObject private var comunidad: ComunidadModel
    @AppStorage("ultimaCopia") private var ultimaCopia: Double = 0
    @State private var copiando = false
    @State private var codigoRecuperacion: String?
    @State private var resultadoCalibracion: ResultadoCalibracion?
    @State private var referencias: [ReferenciaNivel] = []
    @State private var mandoAbierto = false
    @Environment(\.dismiss) private var dismiss

    @State private var token = ""
    @State private var coachKey = ""
    @State private var hasCoachKey = CoachKeyStore.read() != nil

    var body: some View {
        NavigationStack {
            Form {
                leagueSection
                copiaSection
                ligaLocalSection
                coachSection
                privacySection
                playerSection
                sensitivitySection
                // El modo de recogida de datos es una herramienta de quien construye el
                // dataset, no de quien juega: para un usuario normal no existe. Se
                // desbloquea con siete toques en la versión, y cuando la app tenga
                // cuentas de la liga pasará a depender de un rol de verdad.
                if model.developerMode {
                    trainingDataSection
                }
                aboutSection
            }
            // Mismo fondo crema que el resto de la app: un Form con el gris del sistema
            // se veía como una pantalla de otra aplicación.
            .scrollContentBackground(.hidden)
            .fullScreenCover(isPresented: $mandoAbierto) {
                TrainingRemoteView().environmentObject(model)
            }
            .background(T.fondo)
            .tint(T.pista)
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hecho") { dismiss() }
                }
            }
        }
    }

    private var leagueSection: some View {
        Section {
            TextField("https://mi-liga.example.com/api", text: $model.leagueBaseURL)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            SecureField(model.hasToken ? "Token (ya guardado)" : "Token", text: $token)
            Button("Guardar token") {
                model.setToken(token)
                token = ""
            }
            .disabled(token.isEmpty)
        } header: {
            Text("Liga")
        } footer: {
            Text("La app enviará las sesiones a <URL>/v1/padel-sessions. "
                 + "El token se guarda cifrado en el Llavero y no se muestra nunca.")
        }
    }

    @AppStorage("ligaAutoGuardar") private var ligaAutoGuardar = false

    /// Copia de seguridad en el servidor de la comunidad: se renueva sola con cada
    /// sesión y se restaura sola al reinstalar. Aquí solo viven el estado, el botón
    /// manual y el código de recuperación.
    @ViewBuilder
    private var copiaSection: some View {
        if comunidad.tieneCuenta {
            Section {
                if ultimaCopia > 0 {
                    LabeledContent("Última copia") {
                        Text(Date(timeIntervalSince1970: ultimaCopia),
                             format: .dateTime.day().month().hour().minute())
                    }
                } else {
                    Text("Todavía no hay ninguna copia. Se hace sola con cada sesión.")
                        .font(.footnote)
                        .foregroundStyle(T.tintaSuave)
                }
                Button(copiando ? "Guardando…" : "Guardar copia ahora") {
                    copiando = true
                    Task {
                        if let data = CopiaSeguridad.construir(
                            sesiones: model.sessions, liga: liga.backupData()
                        ), await comunidad.subirCopia(data) {
                            ultimaCopia = Date().timeIntervalSince1970
                            model.message = "Copia guardada en el servidor"
                        } else {
                            model.message = "No se pudo guardar la copia"
                        }
                        copiando = false
                    }
                }
                .disabled(copiando)

                if let codigo = codigoRecuperacion {
                    LabeledContent("Código de recuperación") {
                        Text(codigo)
                            .font(.system(.body, design: .monospaced).bold())
                            .textSelection(.enabled)
                    }
                    Text("Apúntalo en un sitio seguro: es lo único que devuelve tu "
                         + "cuenta si pierdes el móvil. No lo compartas.")
                        .font(.footnote)
                        .foregroundStyle(T.tintaSuave)
                } else {
                    Button("Ver mi código de recuperación") {
                        Task { codigoRecuperacion = await comunidad.codigoRecuperacion() }
                    }
                }
            } header: {
                Text("Copia de seguridad")
            } footer: {
                Text("El historial y la liga se guardan en tu cuenta de la comunidad "
                     + "con cada sesión. Al reinstalar la app, vuelven solos.")
            }
        }
    }

    private var ligaLocalSection: some View {
        Section {
            Toggle("Guardar partidos automáticamente", isOn: $ligaAutoGuardar)
        } header: {
            Text("Liga personal")
        } footer: {
            Text("Cada sesión con marcador que llegue del reloj se guardará sola como "
                 + "partido en la pestaña Liga, con los objetivos medibles ya marcados. "
                 + "Guardar dos veces la misma sesión actualiza, no duplica.")
        }
    }

    private var coachSection: some View {
        Section {
            SecureField(hasCoachKey ? "Clave (ya guardada)" : "sk-ant-…", text: $coachKey)
            Button("Guardar clave") {
                CoachKeyStore.write(coachKey)
                coachKey = ""
                hasCoachKey = CoachKeyStore.read() != nil
            }
            .disabled(coachKey.isEmpty)
            if hasCoachKey {
                Button("Borrar clave", role: .destructive) {
                    CoachKeyStore.write(nil)
                    hasCoachKey = false
                }
            }
        } header: {
            Text("Entrenador IA")
        } footer: {
            Text("Tu clave de la API de Anthropic (console.anthropic.com) para pedir "
                 + "análisis al entrenador de la liga. Se guarda cifrada en el Llavero "
                 + "y nunca viaja en la copia de seguridad de la liga.")
        }
    }

    private var privacySection: some View {
        Section {
            Toggle("Compartir datos de salud", isOn: $model.shareHealth)
            Toggle("Compartir el detalle de cada golpeo", isOn: $model.shareShotEvents)
        } header: {
            Text("Privacidad")
        } footer: {
            Text("Sin el primero, el reloj ni siquiera mide frecuencia cardiaca ni calorías. "
                 + "Sin el segundo solo se suben los totales por tipo, no la secuencia de golpeos.")
        }
    }

    private var playerSection: some View {
        Section {
            Picker("Mano de la pala", selection: $model.playerHandRaw) {
                Text("Diestro").tag(Hand.right.rawValue)
                Text("Zurdo").tag(Hand.left.rawValue)
            }
            Picker("Muñeca del reloj", selection: $model.watchWristRaw) {
                Text("Derecha").tag(Hand.right.rawValue)
                Text("Izquierda").tag(Hand.left.rawValue)
            }
            if !model.profile.watchOnRacketArm {
                Text("Para contar golpeos el reloj tiene que ir en el brazo con el que juegas. "
                     + "En la otra muñeca no ve el swing.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Jugador")
        }
    }

    private var aboutSection: some View {
        Section {
            Text("Rising Padel \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                .onTapGesture { model.versionTapped() }
            if model.developerMode {
                Text("Modo desarrollador activado. Siete toques en la versión lo desactivan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Acerca de")
        }
    }

    @ViewBuilder
    private var trainingDataSection: some View {
        Section {
            Toggle("Recoger datos de entrenamiento", isOn: $model.collectTrainingData)
            if model.collectTrainingData {
                TextField("Alias del jugador", text: $model.playerAlias)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                // El nivel viaja con cada golpe grabado y es lo que ancla la escala:
                // ponerle el reloj a un jugador de nivel 6-7 media hora es el "esto es
                // un 7". Es el nivel TÉCNICO de quien lleva el reloj, no el de una
                // plataforma de partidos: ese mide con quién ganas, no cómo golpeas.
                Picker("Nivel técnico de quien lleva el reloj", selection: $model.playerLevelRaw) {
                    Text("Sin indicar").tag(0)
                    ForEach(1...7, id: \.self) { Text("\($0)").tag($0) }
                }

                // Grabar tandas desde aquí y no desde la muñeca: el que dirige el
                // ejercicio no es el que lleva el reloj, y pararlo todo para cambiar de
                // golpe entre tanda y tanda es la razón por la que se graban pocas.
                Button {
                    mandoAbierto = true
                } label: {
                    Label("Dirigir tandas desde el móvil", systemImage: "dot.radiowaves.left.and.right")
                }

                if let url = model.trainingDataURL {
                    // Lo que convierte una tanda en algo útil hoy mismo, sin ordenador
                    // y sin modelo entrenado: tus etiquetas mueven tus umbrales.
                    Button {
                        resultadoCalibracion = model.calibrarConTandas()
                        referencias = model.recalcularEscalaDeNivel()
                    } label: {
                        Label("Calibrar con las tandas", systemImage: "slider.horizontal.3")
                    }
                    if !referencias.isEmpty {
                        escalaDeNivel(referencias)
                    }
                    if let resultado = resultadoCalibracion {
                        resumenCalibracion(resultado)
                    } else if let calibracion = model.calibration, !calibracion.vacia {
                        Text("Calibrado con \(calibracion.muestras) golpes tuyos.")
                            .font(.caption)
                            .foregroundStyle(T.verde)
                    }
                    if model.calibration != nil {
                        Button("Volver a los umbrales de fábrica") {
                            model.borrarCalibracion()
                            resultadoCalibracion = nil
                        }
                        .font(.caption)
                    }

                    // ShareLink en vez de subir a ningún sitio: el fichero solo sale del
                    // móvil si el usuario lo comparte a mano.
                    ShareLink(item: url) {
                        Label("Exportar \(model.trainingDataSizeKB) KB", systemImage: "square.and.arrow.up")
                    }
                    Button("Borrar datos recogidos", role: .destructive) {
                        model.deleteTrainingData()
                    }
                } else {
                    // Decir solo "no ha llegado nada" deja al usuario mirando una tanda
                    // que sí grabó en el reloj sin saber qué falta. Se dice el paso.
                    Text("""
                        Todavía no ha llegado ningún dato del reloj. Se envían solos al parar \
                        una tanda; si el iPhone estaba lejos, abre **Datos de entrenamiento** \
                        en el reloj y pulsa **Enviar al móvil**.
                        """)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Datos de entrenamiento")
        } footer: {
            // Sin concatenar: SwiftUI solo interpreta el markdown de un literal, y con
            // `+` los asteriscos salían en pantalla tal cual.
            Text("""
                Graba tandas de golpes etiquetados en el reloj para entrenar un clasificador \
                propio. Guarda la señal cruda de los sensores, que en el resto de la app nunca \
                sale del dispositivo. **No se sube a la liga**: solo sale de aquí si lo \
                exportas tú.
                """)
        }
    }

    /// El parte de la calibración: qué tandas la sostienen, cuánto acierta el detector
    /// sobre ellas antes y después, y qué familias faltan por grabar.
    private func resumenCalibracion(_ resultado: ResultadoCalibracion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            let antes = Int((resultado.aciertoAntes * 100).rounded())
            let despues = Int((resultado.aciertoDespues * 100).rounded())
            Text("Con tus \(resultado.calibracion.muestras) golpes etiquetados: "
                 + "el detector acertaba el \(antes)% y ahora acierta el \(despues)%.")
                .font(.caption)
                .foregroundStyle(despues >= antes ? T.verde : T.rojo)

            if resultado.calibracion.vacia {
                Text("Ninguna familia tiene todavía \(ThresholdCalibrator.minPorFamilia) "
                     + "golpes suyos, así que se quedan los umbrales de fábrica. "
                     + "Graba tandas de cada tipo y vuelve a pulsar.")
                    .font(.caption2)
                    .foregroundStyle(T.tintaSuave)
            } else {
                if let vibora = resultado.calibracion.viboraElevationDeg {
                    linea("Altura que separa tu bandeja de tu víbora",
                          String(format: "%.0f°", vibora))
                }
                if let smash = resultado.calibracion.smashPeakGyroRadS {
                    linea("Violencia mínima de tu remate", String(format: "%.1f", smash))
                }
                if resultado.calibracion.ejeDeElevacionInvertido == true {
                    linea("Eje de la elevación", "corregido (tu reloj lo lee al revés)")
                }
                if let prep = resultado.calibracion.prepOverheadElevationDeg {
                    linea("Altura a la que armas los golpes altos", String(format: "%.0f°", prep))
                }
                if let volea = resultado.calibracion.volleyAxialMaxRadS {
                    linea("Efecto máximo de tu volea", String(format: "%.1f", volea))
                }
            }

            // Qué falta: es la instrucción concreta para la próxima sesión de pista.
            let faltan = [ShotType.forehand, .backhand, .forehandVolley, .backhandVolley,
                          .bandeja, .vibora, .smash]
                .filter { (resultado.porTipo[$0] ?? 0) < ThresholdCalibrator.minPorFamilia }
            if !faltan.isEmpty {
                Text("Te faltan tandas de: " + faltan.map(\.label).joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(T.tintaSuave)
            }
        }
    }

    private func linea(_ titulo: String, _ valor: String) -> some View {
        HStack {
            Text(titulo)
                .font(.caption2)
                .foregroundStyle(T.tintaSuave)
            Spacer()
            Text(valor)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(T.tinta)
        }
    }

    /// El parte de la escala de nivel: con qué jugadores está anclada y si ya se
    /// sostiene. Sin dos niveles técnicos distintos no se calibra nada, y se dice.
    private func escalaDeNivel(_ referencias: [ReferenciaNivel]) -> some View {
        let niveles = Set(referencias.filter {
            $0.golpes >= LevelReferenceCalibrator.minGolpes
        }.map(\.nivelTecnico)).sorted()
        return VStack(alignment: .leading, spacing: 4) {
            Divider().overlay(T.borde)
            Text("Escala de nivel")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(T.tinta)
            if niveles.count >= LevelReferenceCalibrator.minNiveles {
                Text("Anclada con tandas de nivel "
                     + niveles.map { String(format: "%.0f", $0) }.joined(separator: " y ")
                     + ". El nivel que mide la app se compara con esos jugadores.")
                    .font(.caption2)
                    .foregroundStyle(T.verde)
            } else {
                Text("Necesita tandas de al menos dos niveles técnicos distintos. "
                     + "Hoy hay: "
                     + (niveles.isEmpty
                        ? "ninguna con \(LevelReferenceCalibrator.minGolpes)+ golpes"
                        : niveles.map { String(format: "%.0f", $0) }.joined(separator: ", "))
                     + ". Grábale una tanda a alguien de otro nivel y la escala se ancla.")
                    .font(.caption2)
                    .foregroundStyle(T.tintaSuave)
            }
        }
    }

    private var sensitivitySection: some View {
        Section {
            Picker("Sensibilidad", selection: $model.sensitivityRaw) {
                Text("Baja").tag(Sensitivity.low.rawValue)
                Text("Media").tag(Sensitivity.medium.rawValue)
                Text("Alta").tag(Sensitivity.high.rawValue)
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Detección")
        } footer: {
            Text("Si la app cuenta golpeos de más, baja la sensibilidad. "
                 + "Si se deja golpeos flojos sin contar, súbela.")
        }
    }
}

#Preview {
    SettingsView().environmentObject(AppModel(store: InMemorySessionStore()))
}
