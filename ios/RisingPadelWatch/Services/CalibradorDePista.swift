import CoreLocation
import Foundation
import PadelCore

/// Mide la pista con el GPS del reloj, esquina por esquina.
///
/// ## Qué es esto y qué no es
///
/// No es un mapa de calor. Es **la regla antes del mapa**: la pregunta de si el GPS del
/// Apple Watch da para decir dónde estaba el jugador no se contesta opinando, y una
/// pista de pádel mide 20×10 m por reglamento, así que sirve de patrón. El jugador se
/// planta en las cuatro esquinas, el reloj toma una lectura en cada una, y lo que falle
/// al reconstruir ese rectángulo **es** el error del GPS en esa pista concreta —con su
/// multitrayecto, su techo y su día. Ese número lo calcula `CalibracionGpsDePista` y es el
/// que decide qué se puede enseñar después, o si no se puede enseñar nada.
///
/// ## Por qué cada esquina tarda unos segundos
///
/// Una sola lectura de GPS trae todo el ruido del instante. Se promedian las de unos
/// segundos, que baja el ruido aleatorio — **pero no el sesgo**: si la señal rebota
/// siempre contra el mismo cristal, promediar mil lecturas da mil veces el mismo error
/// desplazado. Por eso el promedio no se vende como precisión: la precisión sale del
/// rectángulo, no de aquí.
final class CalibradorDePista: NSObject, ObservableObject {

    /// Las cuatro esquinas, **en orden**, recorriendo la pista y no en aspa. El orden
    /// importa: `CalibracionGpsDePista.de` empareja cada lectura con su esquina ideal.
    static let nombresDeEsquina = CalibracionGpsDePista.nombresDeEsquina

    /// Cuánto se escucha en cada esquina antes de dar la lectura por buena.
    private static let segundosPorEsquina = 6.0

    /// Lecturas peores que esto no entran en el promedio. Con 25 m de "precisión"
    /// declarada la lectura no está midiendo una esquina, está midiendo el barrio.
    private static let peorAccuracyAceptableM = 25.0

    @Published private(set) var esquinas: [PuntoGeo] = []
    /// La precisión que declara el sistema ahora mismo, para que se vea si merece la
    /// pena marcar ya o esperar a que el reloj fije mejor.
    @Published private(set) var precisionActualM: Double?
    /// Hay una esquina midiéndose en este momento.
    @Published private(set) var midiendo = false
    /// Qué contarle al jugador cuando algo no se puede hacer (permiso, GPS apagado).
    @Published var aviso: String?
    /// La calibración terminada, cuando ya hay cuatro esquinas.
    @Published private(set) var resultado: CalibracionGpsDePista?

    private let gestor = CLLocationManager()
    private var muestras: [CLLocation] = []
    private var finDeLaEscucha: Date?

    override init() {
        super.init()
        gestor.delegate = self
        gestor.desiredAccuracy = kCLLocationAccuracyBestForNavigation
    }

    var siguienteEsquina: String? {
        esquinas.count < Self.nombresDeEsquina.count
            ? Self.nombresDeEsquina[esquinas.count]
            : nil
    }

    var completa: Bool { esquinas.count == Self.nombresDeEsquina.count }

    /// Empieza a escuchar posiciones. Se llama al abrir la pantalla para que el reloj
    /// tenga tiempo de fijar antes del primer toque: un GPS recién encendido da sus
    /// peores lecturas en los primeros segundos.
    func despertar() {
        switch gestor.authorizationStatus {
        case .notDetermined:
            gestor.requestWhenInUseAuthorization()
        case .denied, .restricted:
            aviso = "Sin permiso de ubicación no se puede medir la pista. "
                + "Se activa en Ajustes → Privacidad → Localización."
            return
        default:
            break
        }
        gestor.startUpdatingLocation()
    }

    func dormir() {
        gestor.stopUpdatingLocation()
        midiendo = false
        finDeLaEscucha = nil
        muestras = []
    }

    /// Marca la esquina en la que está el jugador ahora. Recoge durante unos segundos y
    /// al terminar añade la lectura promediada.
    func marcarEsquina() {
        guard !midiendo, !completa else { return }
        guard gestor.authorizationStatus == .authorizedWhenInUse
                || gestor.authorizationStatus == .authorizedAlways else {
            despertar()
            return
        }
        muestras = []
        midiendo = true
        finDeLaEscucha = Date().addingTimeInterval(Self.segundosPorEsquina)
        gestor.startUpdatingLocation()

        // La esquina se cierra cuando llega la lectura que pasa del tiempo, pero si el
        // jugador está quieto pueden dejar de llegar: sin este seguro, el botón se
        // quedaría en "midiendo…" para siempre y no hay forma de salir de ahí.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.segundosPorEsquina + 2) {
            [weak self] in
            guard let self, self.midiendo else { return }
            self.cerrarEsquina()
        }
    }

    /// Borra la última esquina. En una muñeca, marcar sin querer pasa.
    func deshacer() {
        guard !esquinas.isEmpty, !midiendo else { return }
        esquinas.removeLast()
        resultado = nil
    }

    func empezarDeCero() {
        esquinas = []
        resultado = nil
        muestras = []
        midiendo = false
    }

    // MARK: Guardado

    private static let clave = "calibracionDePista"

    /// Guarda la calibración en el reloj. **Se guarda también la mala**: saber que en
    /// esta pista el GPS no llega es un dato, y volver a medirlo cada sábado para
    /// llegar a la misma conclusión no lo es.
    func guardar() {
        guard let resultado, let data = try? JSONEncoder().encode(resultado) else { return }
        UserDefaults.standard.set(data, forKey: Self.clave)
    }

    static func guardada() -> CalibracionGpsDePista? {
        guard let data = UserDefaults.standard.data(forKey: clave) else { return nil }
        return try? JSONDecoder().decode(CalibracionGpsDePista.self, from: data)
    }

    // MARK: Promedio de una esquina

    private func cerrarEsquina() {
        midiendo = false
        finDeLaEscucha = nil

        let buenas = muestras.filter {
            $0.horizontalAccuracy > 0 && $0.horizontalAccuracy <= Self.peorAccuracyAceptableM
        }
        muestras = []
        guard !buenas.isEmpty else {
            aviso = "No llegó ninguna lectura utilizable en esa esquina. "
                + "Prueba otra vez con el reloj hacia arriba."
            return
        }

        let lat = buenas.reduce(0.0) { $0 + $1.coordinate.latitude } / Double(buenas.count)
        let lon = buenas.reduce(0.0) { $0 + $1.coordinate.longitude } / Double(buenas.count)
        // Se guarda la PEOR precisión declarada y no la media: el dato sirve para
        // desconfiar, y para eso lo que importa es el peor momento, no el típico.
        let peor = buenas.map(\.horizontalAccuracy).max() ?? 0

        esquinas.append(PuntoGeo(latitud: lat, longitud: lon, accuracyM: peor))
        if completa {
            resultado = CalibracionGpsDePista.de(esquinas: esquinas)
            gestor.stopUpdatingLocation()
        }
    }
}

extension CalibradorDePista: CLLocationManagerDelegate {

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let ultima = locations.last else { return }
        precisionActualM = ultima.horizontalAccuracy > 0 ? ultima.horizontalAccuracy : nil

        guard midiendo, let fin = finDeLaEscucha else { return }
        muestras.append(ultima)
        if Date() >= fin { cerrarEsquina() }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Un fallo suelto es normal en interiores; solo se cuenta si estaba midiendo,
        // porque entonces sí deja al jugador esperando a una esquina que no llega.
        guard midiendo else { return }
        midiendo = false
        finDeLaEscucha = nil
        muestras = []
        aviso = "El reloj no consiguió posición. Sal al centro de la pista y reintenta."
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            aviso = nil
            manager.startUpdatingLocation()
        case .denied, .restricted:
            aviso = "Sin permiso de ubicación no se puede medir la pista."
        default:
            break
        }
    }
}
