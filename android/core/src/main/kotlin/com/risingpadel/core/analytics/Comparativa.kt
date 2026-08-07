package com.risingpadel.core.analytics

import com.risingpadel.core.model.PadelSession
import kotlin.math.abs

/**
 * Un número puesto al lado de tu media: la diferencia y si es para bien.
 *
 * "45 km/h" no significa nada para nadie que no lleve años midiéndose. "45 km/h, +3 sobre
 * tu media" sí: dice que hoy pegaste más fuerte de lo normal, que es la única forma en
 * que un número suelto se convierte en información. Es la diferencia entre una ficha que
 * hay que interpretar y una que se lee sola.
 */
data class Comparativa(
    /** Diferencia con la media, en las unidades del número. */
    val delta: Float,
    val media: Float,
    /** La diferencia en tanto por uno de la media. */
    val fraccion: Float,
    /** true = mejor que tu media, false = peor. */
    val mejor: Boolean,
) {
    companion object {
        /**
         * Cuántas sesiones ajenas hacen falta para hablar de "tu media".
         *
         * Con una sola sesión anterior, "tu media" es esa sesión, y comparar dos días
         * sueltos no es una tendencia: es ruido con nombre de estadística.
         */
        const val MIN_SESIONES = 3

        /** Por debajo de esta diferencia relativa no se dice nada: sería ruido. */
        const val UMBRAL = 0.03f

        /**
         * Compara [valor] con [media]. Null si no hay media, si es cero o si la
         * diferencia es tan pequeña que enseñarla sería inventar una tendencia.
         *
         * @param masEsMejor false para métricas donde subir es peor (ninguna todavía,
         *   pero el pulso en reposo o el tiempo de reacción lo serán).
         */
        fun de(valor: Float, media: Float?, masEsMejor: Boolean = true): Comparativa? {
            if (media == null || media == 0f) return null
            val delta = valor - media
            val fraccion = delta / media
            if (abs(fraccion) < UMBRAL) return null
            return Comparativa(
                delta = delta,
                media = media,
                fraccion = fraccion,
                mejor = if (masEsMejor) delta > 0 else delta < 0,
            )
        }
    }
}

/**
 * Las medias del jugador sobre su historial, para poner cada sesión en su sitio.
 *
 * Se calculan **excluyendo la sesión que se va a comparar**. Sin eso, un jugador con tres
 * sesiones compara la de hoy contra una media que incluye la de hoy: la diferencia sale
 * diluida a un tercio y el día que reventó el récord la ficha dice "+2 sobre tu media"
 * cuando fueron seis. Cuantas menos sesiones, más grave el error — justo cuando el
 * jugador es nuevo y más está mirando.
 */
data class MediasDelJugador(
    val golpeos: Float?,
    val minutos: Float?,
    val ritmo: Float?,
    val velocidadMedia: Float?,
    val velocidadMaxima: Float?,
    val nivel: Float?,
) {
    companion object {
        val VACIAS = MediasDelJugador(null, null, null, null, null, null)

        /**
         * @param excluyendo id de la sesión que se va a comparar, para que no se compare
         *   contra sí misma.
         */
        fun de(sesiones: List<PadelSession>, excluyendo: String? = null): MediasDelJugador {
            val otras = sesiones.filter { it.sessionId != excluyendo && it.totalShots > 0 }
            if (otras.size < Comparativa.MIN_SESIONES) return VACIAS

            val puntuables = otras.filter { it.level.gradedShots > 0 }
            return MediasDelJugador(
                golpeos = otras.map { it.totalShots.toFloat() }.average().toFloat(),
                minutos = otras.map { it.durationSeconds / 60f }.average().toFloat(),
                ritmo = otras.map { it.shotsPerMinute }.average().toFloat(),
                velocidadMedia = otras.map { it.intensity.meanRacketSpeedKmh }.average().toFloat(),
                velocidadMaxima = otras.map { it.intensity.maxRacketSpeedKmh }.average().toFloat(),
                nivel = if (puntuables.size < Comparativa.MIN_SESIONES) null
                else puntuables.map { it.level.overall }.average().toFloat(),
            )
        }
    }
}
