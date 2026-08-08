import Foundation
import PadelCore
import SwiftUI

private let sessionDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "es_ES")
    formatter.dateFormat = "d MMM yyyy · HH:mm"
    return formatter
}()

func formatSessionDate(_ epochMs: Int64) -> String {
    sessionDateFormatter.string(from: Date(timeIntervalSince1970: Double(epochMs) / 1000))
}

func formatDuration(_ seconds: Int64) -> String {
    let hours = seconds / 3_600
    let minutes = (seconds % 3_600) / 60
    return hours > 0 ? "\(hours)h \(minutes)min" : "\(minutes)min"
}

extension ShotType {
    var label: String {
        switch self {
        case .forehand: return "Derecha"
        case .backhand: return "Revés"
        case .forehandVolley: return "Volea de derecha"
        case .backhandVolley: return "Volea de revés"
        case .bandeja: return "Bandeja"
        case .vibora: return "Víbora"
        case .smash: return "Smash"
        case .serve: return "Saque"
        case .unknown: return "Sin clasificar"
        }
    }
}

extension SyncState {
    var label: String {
        switch self {
        case .pending: return "Pendiente de subir"
        case .synced: return "En la liga"
        case .failed: return "Falló la subida"
        case .needsAuth: return "Reconecta la liga"
        }
    }
}

func zoneLabel(_ key: String) -> String {
    switch key {
    case "z1": return "Z1 · suave"
    case "z2": return "Z2 · ligero"
    case "z3": return "Z3 · moderado"
    case "z4": return "Z4 · intenso"
    case "z5": return "Z5 · máximo"
    default: return key
    }
}

/// Cómo se pinta el resultado de un partido de la liga.
///
/// Vive aquí y no repetido en cada pantalla porque estaba repetido en cuatro, y por eso
/// la racha de la portada llevaba meses enseñando **D** en los empates: se había escrito
/// como `resultado == "victoria" ? "V" : "D"`, que colapsa cualquier cosa que no sea una
/// victoria en una derrota. Un partido que se corta empatado no es una derrota.
enum ResultadoDePartido {
    /// Un partido guardado desde un entreno sin marcador no tiene resultado. Antes se
    /// guardaba como derrota, que contaba como partido perdido en la racha y en el
    /// porcentaje de victorias sin que nadie hubiera perdido nada.
    static let sinResultado = "sin resultado"

    static func letra(_ resultado: String) -> String {
        switch resultado {
        case "victoria": return "V"
        case "empate": return "E"
        case sinResultado: return "—"
        default: return "D"
        }
    }

    static func nombre(_ resultado: String) -> String {
        switch resultado {
        case "victoria": return "Victoria"
        case "empate": return "Empate"
        case sinResultado: return "Sin resultado"
        default: return "Derrota"
        }
    }

    static func color(_ resultado: String) -> Color {
        switch resultado {
        case "victoria": return T.verde
        case "empate", sinResultado: return T.tintaSuave
        default: return T.rojo
        }
    }

    /// ¿Cuenta este partido para la racha y para el porcentaje de victorias?
    ///
    /// Un entreno sin marcador no cuenta: meterlo en el denominador bajaría el
    /// porcentaje de victorias por haber entrenado, que es exactamente al revés.
    static func cuenta(_ resultado: String) -> Bool { resultado != sinResultado }
}
