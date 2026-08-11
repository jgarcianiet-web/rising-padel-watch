package com.risingpadel.core.liga

/**
 * Cómo vas de tiempo en la temporada.
 *
 * La meta de partidos ya salía como barra, pero una barra al 40% no dice nada sin saber
 * cuánta temporada queda: 8 de 20 en octubre va sobrado y 8 de 20 en mayo es un problema.
 * Esto pone las dos cosas juntas — lo que llevas y lo que ha corrido el calendario— y
 * traduce la diferencia a lo único accionable: cada cuántos días te toca jugar.
 *
 * Nace de un detalle de uso: las fechas de la temporada estaban guardadas y no se veían
 * en ningún sitio. Un rango que no se enseña es un rango que nadie recuerda haber puesto.
 */
data class RitmoDeTemporada(
    val diasTotales: Int,
    val diasTranscurridos: Int,
    val diasRestantes: Int,
    val jugados: Int,
    val objetivo: Int,
) {
    /** Cuánta temporada ha corrido, 0 a 1. */
    val fraccionDelTiempo: Float
        get() = if (diasTotales <= 0) 1f else (diasTranscurridos.toFloat() / diasTotales).coerceIn(0f, 1f)

    /** Cuánta meta llevas, 0 a 1. */
    val fraccionDeLaMeta: Float
        get() = if (objetivo <= 0) 0f else (jugados.toFloat() / objetivo).coerceIn(0f, 1f)

    val partidosQueFaltan: Int get() = (objetivo - jugados).coerceAtLeast(0)

    /**
     * Cuántos partidos deberías llevar a estas alturas si repartieras la meta a lo largo
     * de la temporada. Es la referencia contra la que se mide ir adelantado o atrasado.
     */
    val esperados: Int get() = (objetivo * fraccionDelTiempo).toInt()

    /** Positivo = vas por delante del calendario. */
    val diferencia: Int get() = jugados - esperados

    /**
     * Cada cuántos días toca jugar para llegar a la meta con lo que queda.
     *
     * Null cuando la pregunta no tiene respuesta útil: si ya llegaste (no falta nada) o
     * si se acabó el tiempo (no hay días donde repartir). Devolver un número igualmente
     * sería inventarse una recomendación imposible.
     */
    val cadaCuantosDias: Float?
        get() {
            if (partidosQueFaltan == 0) return null
            if (diasRestantes <= 0) return null
            return diasRestantes.toFloat() / partidosQueFaltan
        }

    val cumplida: Boolean get() = objetivo > 0 && jugados >= objetivo
    val terminada: Boolean get() = diasRestantes <= 0

    companion object {
        /**
         * Null si la temporada no tiene con qué medir el ritmo: sin fecha de fin no hay
         * plazo y sin meta de partidos no hay contra qué comparar. Las fechas se siguen
         * enseñando en ese caso; lo que no se puede es fingir un ritmo.
         */
        fun de(temporada: LigaTemporada, jugados: Int, hoyISO: String): RitmoDeTemporada? {
            val objetivo = temporada.objetivoPartidos ?: return null
            if (objetivo <= 0) return null
            val cierre = temporada.fechaDeCierre
            if (cierre.isEmpty()) return null

            val totales = Fechas.diasEntre(temporada.fechaInicio, cierre) ?: return null
            if (totales <= 0) return null
            // Recortado al rango de la temporada: si todavía no ha empezado, no ha
            // corrido nada, y los días de antes no son días donde repartir partidos.
            val transcurridos = (Fechas.diasEntre(temporada.fechaInicio, hoyISO) ?: return null)
                .coerceIn(0, totales)

            return RitmoDeTemporada(
                diasTotales = totales,
                diasTranscurridos = transcurridos,
                diasRestantes = totales - transcurridos,
                jugados = jugados,
                objetivo = objetivo,
            )
        }
    }
}
