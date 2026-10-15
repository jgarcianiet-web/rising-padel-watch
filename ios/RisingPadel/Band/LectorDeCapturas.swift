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

    /// Los trozos reconocidos **con su posición en la imagen**.
    ///
    /// La posición no es un adorno: es lo que permite leer una rejilla. En estas apps
    /// `Num. golpes` y `Calidad` van uno al lado del otro y sus valores en la fila de
    /// abajo, y en las tarjetas de actividad el número va encima del rótulo. Sin saber en
    /// qué columna está cada cosa no hay forma de emparejarlos. Ver `LecturaDeCaptura`.
    ///
    /// **Vision da el origen abajo a la izquierda y aquí se voltea**, una sola vez y en
    /// este sitio, para que en todo el resto del código `y = 0` sea el borde de arriba.
    /// Tener dos convenios de `y` dando vueltas es el fallo que deja la lectura del revés
    /// y nadie sabe dónde.
    static func trozos(de imagen: UIImage) async throws -> [LecturaDeCaptura.Trozo] {
        try await observaciones(de: imagen).map { observacion in
            let caja = observacion.boundingBox
            return LecturaDeCaptura.Trozo(
                texto: observacion.topCandidates(1).first?.string ?? "",
                x: caja.midX,
                y: 1 - caja.midY
            )
        }
    }

    /// Las líneas reconocidas, de arriba abajo y de izquierda a derecha.
    ///
    /// Se mantiene para cuando solo hace falta el texto. Para interpretar una captura
    /// de verdad usa `trozos(de:)`: sin posiciones, una rejilla de dos columnas se lee
    /// como una sopa de rótulos y números sin dueño.
    static func lineas(de imagen: UIImage) async throws -> [String] {
        try await observaciones(de: imagen).compactMap { $0.topCandidates(1).first?.string }
    }

    private static func observaciones(
        de imagen: UIImage
    ) async throws -> [VNRecognizedTextObservation] {
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

        return ordenadas
    }

    /// El atajo completo: imagen → lo que se pudo entender de ella.
    static func leer(_ imagen: UIImage) async throws -> LecturaDeCaptura.CapturaLeida {
        LecturaDeCaptura.leerTrozos(try await trozos(de: imagen))
    }
}
