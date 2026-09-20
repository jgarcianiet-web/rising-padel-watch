import StoreKit
import SwiftUI

/// La pantalla de venta de Rising Pádel Pro.
///
/// Se enseña en el sitio donde el jugador ha ido a usar algo de pago, y no como un muro
/// al abrir la app: llega cuando ya sabe qué quiere hacer, y por eso la función que le ha
/// traído hasta aquí (`destacando`) va la primera de la lista.
///
/// **Ningún precio está escrito en este fichero.** Los precios salen de
/// `Product.displayPrice`, que es lo que Apple va a cobrar de verdad, con la moneda y el
/// formato del país del jugador. Escribirlos a mano (el §36.21 del documento de producto
/// lo prohíbe) significa que el día que se suba el precio en App Store Connect, o que
/// alguien abra la app en México, la pantalla miente — y una pantalla de venta que miente
/// es una devolución y un rechazo en la revisión.
struct PaywallView: View {

    /// La función que trajo al jugador. Sale la primera, con su explicación.
    var destacando: FuncionPro = .entrenadorIA
    /// True cuando se presenta como hoja y necesita su propio botón de cerrar.
    var enHoja = false

    @StateObject private var tienda = TiendaModel.compartida
    @Environment(\.dismiss) private var dismiss

    @State private var elegido: String?

    /// Los dos enlaces que Apple exige en la pantalla de venta (guía 3.1.2).
    ///
    /// El de términos es el EULA estándar de Apple porque la app no tiene uno propio; si
    /// algún día lo tiene, se cambia aquí. **El de privacidad tiene que ser exactamente
    /// la misma URL declarada en App Store Connect y tiene que abrirse**: hoy apunta al
    /// repositorio, y hay que sustituirlo por la política definitiva antes de enviar la
    /// app a revisión.
    private static let urlTerminos = URL(
        string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
    )!
    private static let urlPrivacidad = URL(
        string: "https://github.com/jgarcianiet-web/rising-padel-watch#privacidad"
    )!

    /// Las funciones que se venden, con la que trajo al jugador en primer lugar.
    private var funciones: [FuncionPro] {
        [destacando] + FuncionPro.allCases.filter {
            $0 != destacando && Gating.requierePro($0)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    cabecera
                    queIncluye
                    if tienda.productos.isEmpty {
                        sinProductos
                    } else {
                        eleccion
                        botonDeCompra
                    }
                    if let mensaje = tienda.mensaje {
                        Text(mensaje)
                            .font(.caption)
                            .foregroundStyle(T.tintaSuave)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    letraPequena
                }
                .padding(16)
            }
            .background(T.fondo)
            .navigationTitle("Rising Pádel Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if enHoja {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cerrar") { dismiss() }
                    }
                }
            }
        }
        .task {
            if tienda.productos.isEmpty { await tienda.cargarProductos() }
            // El anual va preseleccionado porque es el que sale mejor de precio; el
            // ahorro se enseña calculado con los precios reales, no prometido.
            if elegido == nil { elegido = tienda.productos.last?.id }
        }
        // Cuando la suscripción entra en vigor, la pantalla que llevó aquí se desbloquea
        // sola; si esto es una hoja, además se cierra.
        .onChange(of: tienda.plan) { _, nuevo in
            if Gating.esPro(nuevo), enHoja { dismiss() }
        }
    }

    // MARK: Cabecera

    private var cabecera: some View {
        PadelCard {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("TU JUEGO, EN SERIO", icon: "bolt.fill")
                Text(destacando.titulo)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(T.tinta)
                Text(destacando.explicacion)
                    .font(.subheadline)
                    .foregroundStyle(T.tintaSuave)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Qué incluye

    private var queIncluye: some View {
        PadelCard(title: "QUÉ INCLUYE PRO", icon: "checkmark.seal.fill") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(funciones) { funcion in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(T.lima)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(funcion.titulo)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(T.tinta)
                            Text(funcion.explicacion)
                                .font(.caption)
                                .foregroundStyle(T.tintaSuave)
                        }
                    }
                }
            }
        }
    }

    // MARK: Elección de producto

    private var eleccion: some View {
        VStack(spacing: 10) {
            ForEach(tienda.productos, id: \.id) { producto in
                Button {
                    elegido = producto.id
                } label: {
                    FilaDeProducto(
                        producto: producto,
                        periodo: Self.periodo(producto),
                        porMes: Self.porMes(producto),
                        ahorro: ahorro(de: producto),
                        elegido: elegido == producto.id
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var botonDeCompra: some View {
        VStack(spacing: 10) {
            Button {
                guard let producto = tienda.productos.first(where: { $0.id == elegido })
                    ?? tienda.productos.first else { return }
                Task { await tienda.comprar(producto) }
            } label: {
                HStack(spacing: 8) {
                    if tienda.comprando { ProgressView().controlSize(.small).tint(.white) }
                    Text(tienda.comprando ? "Un momento…" : "Empezar")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(T.pista, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(tienda.comprando)

            Button("Restaurar compras") {
                Task { await tienda.restaurar() }
            }
            .font(.subheadline.bold())
            .foregroundStyle(T.pista)
            .disabled(tienda.comprando)
        }
    }

    /// Sin productos no hay nada que vender: se dice y se ofrece reintentar, en vez de
    /// enseñar una pantalla de compra con un botón que no hará nada.
    private var sinProductos: some View {
        PadelCard {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("NO SE PUDO CARGAR")
                Text("La App Store no ha contestado")
                    .font(.headline)
                    .foregroundStyle(T.tinta)
                Text("Comprueba tu conexión y vuelve a intentarlo.")
                    .font(.caption)
                    .foregroundStyle(T.tintaSuave)
                HStack(spacing: 16) {
                    Button("Reintentar") { Task { await tienda.cargarProductos() } }
                    Button("Restaurar compras") { Task { await tienda.restaurar() } }
                }
                .font(.subheadline.bold())
                .foregroundStyle(T.pista)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Letra pequeña

    /// Lo que Apple obliga a decir de una suscripción de renovación automática, y que
    /// además es lo justo: cómo se renueva, cómo se cancela y dónde están las condiciones.
    private var letraPequena: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("La suscripción se renueva sola al final de cada periodo salvo que la "
                 + "canceles al menos 24 horas antes. Se gestiona desde los Ajustes de tu "
                 + "ID de Apple y puedes cancelarla cuando quieras.")
                .font(.caption2)
                .foregroundStyle(T.tintaSuave)

            HStack(spacing: 16) {
                Link("Términos", destination: Self.urlTerminos)
                Link("Privacidad", destination: Self.urlPrivacidad)
            }
            .font(.caption.bold())
            .foregroundStyle(T.pista)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    // MARK: Precios (todos derivados de lo que dice StoreKit)

    private static func periodo(_ producto: Product) -> String {
        guard let periodo = producto.subscription?.subscriptionPeriod else { return "" }
        switch periodo.unit {
        case .day: return periodo.value == 1 ? "al día" : "cada \(periodo.value) días"
        case .week: return periodo.value == 1 ? "a la semana" : "cada \(periodo.value) semanas"
        case .month: return periodo.value == 1 ? "al mes" : "cada \(periodo.value) meses"
        case .year: return periodo.value == 1 ? "al año" : "cada \(periodo.value) años"
        @unknown default: return ""
        }
    }

    /// El equivalente mensual de un plan anual, con la moneda del propio producto. Es
    /// aritmética sobre el precio real, no un número de marketing.
    private static func porMes(_ producto: Product) -> String? {
        guard let periodo = producto.subscription?.subscriptionPeriod,
              periodo.unit == .year, periodo.value == 1 else { return nil }
        let mensual = producto.price / 12
        return mensual.formatted(producto.priceFormatStyle) + " al mes"
    }

    /// Cuánto se ahorra el anual frente a pagar doce meses sueltos. Nil si no hay los dos
    /// productos o si no salen en la misma moneda: un porcentaje calculado entre monedas
    /// distintas sería un número inventado.
    private func ahorro(de producto: Product) -> Int? {
        guard producto.subscription?.subscriptionPeriod.unit == .year,
              let mensual = tienda.productos.first(where: {
                  $0.subscription?.subscriptionPeriod.unit == .month
              }),
              mensual.priceFormatStyle.currencyCode == producto.priceFormatStyle.currencyCode
        else { return nil }

        let doceMeses = mensual.price * 12
        guard doceMeses > 0, producto.price < doceMeses else { return nil }
        let fraccion = (doceMeses - producto.price) / doceMeses
        return Int((NSDecimalNumber(decimal: fraccion).doubleValue * 100).rounded())
    }
}

// MARK: - Fila de producto

private struct FilaDeProducto: View {
    let producto: Product
    let periodo: String
    let porMes: String?
    let ahorro: Int?
    let elegido: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: elegido ? "largecircle.fill.circle" : "circle")
                .font(.system(size: 19))
                .foregroundStyle(elegido ? T.pista : T.borde)

            VStack(alignment: .leading, spacing: 3) {
                Text(producto.displayName)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(T.tinta)
                if let porMes {
                    Text(porMes)
                        .font(.caption)
                        .foregroundStyle(T.tintaSuave)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                // El precio, tal cual lo da StoreKit. Aquí no se formatea nada.
                Text(producto.displayPrice)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(T.tinta)
                Text(periodo)
                    .font(.caption2)
                    .foregroundStyle(T.tintaSuave)
                if let ahorro, ahorro > 0 {
                    Text("Ahorras \(ahorro) %")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(T.lima)
                }
            }
        }
        .padding(14)
        .background(T.superficie, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(elegido ? T.pista : T.borde, lineWidth: elegido ? 2 : 1)
        )
    }
}
