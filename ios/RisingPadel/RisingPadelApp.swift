import SwiftUI

@main
struct RisingPadelApp: App {
    // El delegate clásico solo para APNs: token del dispositivo y toques en
    // notificaciones. Todo lo demás sigue siendo SwiftUI puro.
    @UIApplicationDelegateAdaptor(PushDelegate.self) private var pushDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(model)
                // La tienda se despierta al arrancar y no cuando alguien abre el
                // muro de pago. `TiendaModel` escucha `Transaction.updates` desde su
                // init, y esa escucha es la que entera a la app de una renovación,
                // una baja o una devolución tramitada fuera. Si el objeto naciera al
                // abrir la pantalla de venta, un reembolso llegaría justo a quien ya
                // no piensa volver a abrirla: seguiría con Pro para siempre.
                .task { await TiendaModel.compartida.revisarDerechos() }
        }
    }
}
