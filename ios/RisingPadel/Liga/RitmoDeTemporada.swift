import Foundation
import PadelCore

/// Cómo vas de tiempo en la temporada.
///
/// La meta de partidos ya salía como barra, pero una barra al 40% no dice nada sin saber
/// cuánta temporada queda: 8 de 20 en octubre va sobrado y 8 de 20 en mayo es un problema.
/// Esto pone las dos cosas juntas —lo que llevas y lo que ha corrido el calendario— y
/// traduce la diferencia a lo único accionable: cada cuántos días te toca jugar.
///
/// Nace de un detalle de uso: las fechas de la temporada estaban guardadas y no se veían
/// en ningún sitio. Un rango que no se enseña es un rango que nadie recuerda haber puesto.
///
/// Espejo del core Kotlin, con tests allí.
struct RitmoDeTemporada {
    let diasTotales: Int
    let diasTranscurridos: Int
    let diasRestantes: Int
    let jugados: Int
    let objetivo: Int

    /// Cuánta temporada ha corrido, 0 a 1.
    var fraccionDelTiempo: Float {
        diasTotales <= 0 ? 1 : min(1, max(0, Float(diasTranscurridos) / Float(diasTotales)))
    }

    /// Cuánta meta llevas, 0 a 1.
    var fraccionDeLaMeta: Float {
        objetivo <= 0 ? 0 : min(1, max(0, Float(jugados) / Float(objetivo)))
    }

    var partidosQueFaltan: Int { max(0, objetivo - jugados) }

    /// Cuántos partidos deberías llevar a estas alturas si repartieras la meta a lo largo
    /// de la temporada. Es la referencia contra la que se mide ir adelantado o atrasado.
    var esperados: Int { Int(Float(objetivo) * fraccionDelTiempo) }

    /// Positivo = vas por delante del calendario.
    var diferencia: Int { jugados - esperados }

    /// Cada cuántos días toca jugar para llegar a la meta con lo que queda.
    ///
    /// Nil cuando la pregunta no tiene respuesta útil: si ya llegaste o si se acabó el
    /// tiempo. Dar un número igualmente sería inventarse una recomendación imposible.
    var cadaCuantosDias: Float? {
        guard partidosQueFaltan > 0, diasRestantes > 0 else { return nil }
        return Float(diasRestantes) / Float(partidosQueFaltan)
    }

    var cumplida: Bool { objetivo > 0 && jugados >= objetivo }
    var terminada: Bool { diasRestantes <= 0 }

    /// Nil si la temporada no tiene con qué medir el ritmo: sin fecha de fin no hay plazo
    /// y sin meta no hay contra qué comparar. Las fechas se siguen enseñando en ese caso;
    /// lo que no se puede es fingir un ritmo.
    static func de(_ temporada: LigaTemporada, jugados: Int, hoyISO: String) -> RitmoDeTemporada? {
        guard let objetivo = temporada.objetivoPartidos, objetivo > 0,
              !temporada.fechaDeCierre.isEmpty,
              let totales = Fechas.diasEntre(temporada.fechaInicio, temporada.fechaDeCierre),
              totales > 0,
              let brutos = Fechas.diasEntre(temporada.fechaInicio, hoyISO) else { return nil }

        // Recortado al rango de la temporada: si todavía no ha empezado, no ha corrido
        // nada, y los días de antes no son días donde repartir partidos.
        let transcurridos = min(totales, max(0, brutos))

        return RitmoDeTemporada(
            diasTotales: totales,
            diasTranscurridos: transcurridos,
            diasRestantes: totales - transcurridos,
            jugados: jugados,
            objetivo: objetivo
        )
    }
}

extension LigaTemporada {
    /// "Del 1 sep 2025 al 30 jun 2026", o "Desde el 1 sep 2025" si sigue abierta.
    ///
    /// Con año a propósito: una liga que dura años tiene varias temporadas que empiezan
    /// en septiembre, y sin el año no se distinguen en la tabla de temporada a temporada.
    var rangoLargo: String {
        let desde = LigaFechas.conAnno(fechaInicio)
        guard !fechaDeCierre.isEmpty else { return "Desde el \(desde)" }
        let hasta = LigaFechas.conAnno(fechaDeCierre)
        // Se dice si la fecha es un plan o un hecho: "hasta el 30 de junio" y "acabó el
        // 30 de junio" son cosas distintas y el rango solo no las distingue.
        return fechaFin.isEmpty ? "Del \(desde) al \(hasta) (previsto)" : "Del \(desde) al \(hasta)"
    }

    /// "1 sep – 30 jun", para las filas estrechas.
    var rangoCorto: String {
        let desde = LigaFechas.corta(fechaInicio)
        guard !fechaDeCierre.isEmpty else { return "desde \(desde)" }
        return "\(desde) – \(LigaFechas.corta(fechaDeCierre))"
    }
}
