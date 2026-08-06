import PadelCore
import SwiftUI

/// El primer arranque, en tres pasos: qué hace la app, la cuenta de la comunidad y el
/// primer objetivo. Decide si quien instala la app la entiende en 30 segundos.
///
/// Solo aparece una vez. Un usuario que ya tiene sesiones o cuenta no lo ve nunca:
/// `RootTabView` lo marca como hecho al detectar cualquiera de las dos cosas.
struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var liga: LigaModel
    @EnvironmentObject private var comunidad: ComunidadModel
    @AppStorage("onboardingDone") private var onboardingDone = false

    @State private var paso = 0
    @State private var alias = ""
    @State private var creando = false
    @State private var objetivo = ""

    /// Objetivos de arranque que el reloj puede medir solo — es la promesa diferencial
    /// de la app, así que es lo primero que se enseña.
    private static let sugerencias = [
        "Hacer 15 bandejas",
        "Mínimo 10 víboras",
        "Hacer 5 smashes",
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $paso) {
                pasoReloj.tag(0)
                pasoComunidad.tag(1)
                pasoObjetivo.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        }
        .background(T.fondo)
    }

    // MARK: Paso 1 — el reloj

    private var pasoReloj: some View {
        pagina(
            icono: "applewatch.radiowaves.left.and.right",
            titulo: "Tu reloj cuenta el partido"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                punto("figure.tennis", "Golpes por tipo",
                      "Bandejas, víboras, smashes, voleas… el reloj los detecta y los "
                      + "cuenta mientras juegas.")
                punto("list.number", "Marcador desde la muñeca",
                      "Lleva el partido tocando la pantalla: arriba nosotros, abajo "
                      + "ellos. Con punto de oro si quieres.")
                punto("chart.line.uptrend.xyaxis", "Tu nivel, medido",
                      "Cada sesión sale con un nivel del 1 al 7 y sus gráficas, para "
                      + "ver si de verdad mejoras.")
                punto("lock.shield", "Tu salud, tuya",
                      "El pulso y las calorías solo se comparten si tú lo activas en "
                      + "Ajustes. Sin permiso, no salen del reloj.")
            }
        } boton: {
            Button {
                withAnimation { paso = 1 }
            } label: {
                Text("Seguir")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: Paso 2 — la comunidad

    private var pasoComunidad: some View {
        pagina(
            icono: "person.3.fill",
            titulo: "Únete a la comunidad"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Con un alias tienes cuenta: tus amigos te siguen, les avisa "
                     + "cuando estás jugando y pueden ver tu partido en vivo. También "
                     + "enciende el ranking, los retos y el muro.")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(T.tintaSuave)
                    .fixedSize(horizontal: false, vertical: true)

                TextField("Tu alias (ej: jesus-g)", text: $alias)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if let message = comunidad.message {
                    Text(message)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(T.rojo)
                }
            }
        } boton: {
            VStack(spacing: 8) {
                Button {
                    creando = true
                    Task {
                        await comunidad.registrar(
                            servidor: ComunidadRegistroView.servidorOficial,
                            alias: alias
                        )
                        creando = false
                        if comunidad.tieneCuenta { withAnimation { paso = 2 } }
                    }
                } label: {
                    if creando {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Crear mi cuenta")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(alias.trimmingCharacters(in: .whitespaces).count < 2 || creando)

                Button("Ahora no") { withAnimation { paso = 2 } }
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(T.tintaSuave)
            }
        }
    }

    // MARK: Paso 3 — el primer objetivo

    private var pasoObjetivo: some View {
        pagina(
            icono: "target",
            titulo: "Tu primer objetivo"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Elige un objetivo que el reloj pueda medir: al acabar cada "
                     + "partido se marca solo si lo cumpliste. Luego puedes cambiarlo "
                     + "en Liga → Objetivos y perfil.")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(T.tintaSuave)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(Self.sugerencias, id: \.self) { texto in
                    Button {
                        objetivo = texto
                    } label: {
                        HStack {
                            Image(systemName: objetivo == texto
                                  ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(objetivo == texto ? T.verde : T.tintaSuave)
                            Text(texto)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(T.tinta)
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(T.superficie, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }

                TextField("O escribe el tuyo…", text: $objetivo)
                    .textFieldStyle(.roundedBorder)
            }
        } boton: {
            Button {
                terminar()
            } label: {
                Text("Empezar a jugar")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func terminar() {
        let elegido = objetivo.trimmingCharacters(in: .whitespaces)
        if !elegido.isEmpty {
            // El objetivo elegido entra el primero; el resto de la terna se queda.
            var objetivos = liga.state.objetivos
            if objetivos.isEmpty { objetivos = LigaCatalogos.defaultObjetivos }
            objetivos[0] = elegido
            liga.saveObjetivos(objetivos)
        }
        onboardingDone = true
    }

    // MARK: Piezas

    private func pagina(
        icono: String, titulo: String,
        @ViewBuilder cuerpo: () -> some View,
        @ViewBuilder boton: () -> some View
    ) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: icono)
                    .font(.system(size: 44))
                    .foregroundStyle(T.pista)
                    .padding(.top, 48)
                Text(titulo)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(T.tinta)
                    .multilineTextAlignment(.center)
                cuerpo()
                    .padding(.horizontal, 4)
                boton()
                    .padding(.top, 6)
                Spacer(minLength: 40)
            }
            .padding(.horizontal, 24)
        }
    }

    private func punto(_ icono: String, _ titulo: String, _ detalle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icono)
                .font(.system(size: 18))
                .foregroundStyle(T.pista)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(T.tinta)
                Text(detalle)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(T.tintaSuave)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
