import Foundation
import PadelCore

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
        case .overhead: return "Bandeja / smash"
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
