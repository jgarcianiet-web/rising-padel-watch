import Foundation
import PadelCore
import UIKit
import Vision

/// Saca las líneas de texto de una captura de pantalla, **en el dispositivo**.
///
/// La parte lista (qué número es qué) vive en `LecturaDeCaptura`, en el core, con sus
/// tests. Esto es solo el puente: imagen → líneas de texto en orden de lectura. Separarlo
/// no es ceremonia: el reconocimiento necesita Vision y un dispositivo, y la
/// interpretación es texto puro que se puede probar sin ninguno de los dos.
///
/// ## Nada sale del móvil
///
/// `VNRecognizeTextRequest` corre en local. La captura no se sube a ningún sitio, no se
/// guarda en la app y no entra en la copia de seguridad: se lee, se saca el texto y la
/// imagen se suelta. Lo que acaba guardado son los números que el jugador confirma.
enum LectorDeCapturas {

    enum Fallo: LocalizedError {
        case sinImagen
        case noSePudoLeer

        var errorDescription: String? {
            switch self {
            case .sinImagen: return "Esa imagen no se pudo abrir."
            case .noSePudoLeer: return "No se ha reconocido texto en la captura."
            }
        }
    }

    /// Las líneas reconocidas, de arriba abajo y de izquierda a derecha.
    ///
    /// **El orden es parte del dato, no una cortesía.** `LecturaDeCaptura` cuenta con que
    /// el rótulo y su número vengan seguidos, porque en una app el rótulo pequeño va
    /// encima del número grande. Si las líneas llegaran en el orden interno de Vision, los
    /// rótulos y los números se mezclarían y no habría forma de saber de quién es cada
    /// número.
    static func lineas(de imagen: UIImage) async throws -> [String] {
        guard let cg = imagen.cgImage else { throw Fallo.sinImagen }

        let peticion = VNRecognizeTextRequest()
        peticion.recognitionLevel = .accurate
        // Español primero y luego inglés: la app puede estar en cualquiera de los dos.
        peticion.recognitionLanguages = ["es-ES", "en-US"]
        // **Corrección lingüística apagada.** Está pensada para prosa y aquí estropea
        // justo lo que importa: convierte "3,5" en "3.5" o en "35", y un "ppm" en una
        // palabra del diccionario. Lo que se lee son números y rótulos cortos.
        peticion.usesLanguageCorrection = false

        let manejador = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
        do {
            try manejador.perform([peticion])
        } catch {
            throw Fallo.noSePudoLeer
        }

        guard let observaciones = peticion.results, !observaciones.isEmpty else {
            throw Fallo.noSePudoLeer
        }

        // Vision da el origen abajo-izquierda, así que "más arriba" es mayor `minY`: se
        // ordena descendente por y para leer de arriba abajo. A igual altura (una fila con
        // dos columnas), de izquierda a derecha.
        let ordenadas = observaciones.sorted { a, b in
            let alturaA = a.boundingBox.minY
            let alturaB = b.boundingBox.minY
            // El margen de 1,5 % de la altura decide cuándo dos trozos son "la misma
            // fila". Sin él, dos columnas de la misma fila se ordenarían por diferencias
            // de un píxel y saldrían intercaladas al azar.
            if abs(alturaA - alturaB) > 0.015 { return alturaA > alturaB }
            return a.boundingBox.minX < b.boundingBox.minX
        }

        return ordenadas.compactMap { $0.topCandidates(1).first?.string }
    }

    /// El atajo completo: imagen → lo que se pudo entender de ella.
    static func leer(_ imagen: UIImage) async throws -> LecturaDeCaptura.CapturaLeida {
        LecturaDeCaptura.leer(try await lineas(de: imagen))
    }
}
