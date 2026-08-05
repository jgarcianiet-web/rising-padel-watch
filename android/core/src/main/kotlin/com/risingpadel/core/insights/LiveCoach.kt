package com.risingpadel.core.insights

import com.risingpadel.core.model.GameRecord
import com.risingpadel.core.score.Side

/**
 * Un aviso corto para la muñeca, a mitad de partido.
 *
 * @property key identifica la regla, para no repetir el mismo aviso dos veces.
 * @property text lo que se lee de reojo entre puntos. Corto a propósito.
 */
data class LiveTip(val key: String, val text: String)

/**
 * El entrenador en vivo: mira los juegos cerrados y, si hay un patrón claro, suelta un
 * aviso de una línea.
 *
 * Es el `InsightEngine` con dos diferencias: pasa **durante** el partido, así que solo
 * puede mirar juegos completos (nunca golpeos, que a mitad de juego no dicen nada), y
 * habla poquísimo. Un aviso a mitad de partido interrumpe; si no cambia lo que vas a
 * hacer en el siguiente juego, no se dice.
 *
 * Las mismas reglas de evidencia que el resto: por debajo del mínimo, silencio.
 */
object LiveCoach {

    /** Sin esto una racha de dos juegos ya "sería un patrón", y no lo es. */
    const val MIN_GAMES = 4

    /**
     * Tres por lado, uno más que el `InsightEngine` de después del partido: un aviso en
     * vivo interrumpe, y con dos juegos por lado un 50%-0% es todavía una moneda.
     */
    const val MIN_GAMES_PER_SIDE = 3

    /** Diferencia de puntos porcentuales que hace que saque y resto sean dos partidos. */
    const val MIN_SIDE_GAP = 40

    /** Juegos seguidos perdidos que merecen un aviso. */
    const val LOSING_STREAK = 3

    /**
     * Devuelve el aviso que toca ahora, o null si no hay nada que decir.
     *
     * @param games juegos cerrados en orden de juego.
     * @param alreadySaid claves de avisos ya dados en este partido.
     */
    fun tip(games: List<GameRecord>, alreadySaid: Set<String>): LiveTip? {
        if (games.size < MIN_GAMES) return null

        // La racha manda sobre el resto: es lo más urgente y lo más accionable.
        val streak = games.takeLast(LOSING_STREAK)
        if (streak.size == LOSING_STREAK && streak.all { it.winner == Side.THEM }) {
            val key = "racha-${games.size}"
            if (key !in alreadySaid) {
                return LiveTip(key, "$LOSING_STREAK juegos seguidos. Cambia el patrón: globo y a la red.")
            }
        }

        val serving = games.filter { it.server == Side.US }
        val returning = games.filter { it.server == Side.THEM }
        if (serving.size >= MIN_GAMES_PER_SIDE && returning.size >= MIN_GAMES_PER_SIDE) {
            val pctServing = pct(serving)
            val pctReturning = pct(returning)
            if (pctServing - pctReturning >= MIN_SIDE_GAP && "saque-mejor" !in alreadySaid) {
                return LiveTip(
                    "saque-mejor",
                    "Aguantas tu saque ($pctServing%) pero al resto vas a $pctReturning%. Presiona la primera bola.",
                )
            }
            if (pctReturning - pctServing >= MIN_SIDE_GAP && "resto-mejor" !in alreadySaid) {
                return LiveTip(
                    "resto-mejor",
                    "Restando ganas el $pctReturning% y sacando el $pctServing%. Asegura el primer saque y sube.",
                )
            }
        }

        return null
    }

    // Redondeo, no truncado: es el convenio del resto del core (ver InsightEngine) y
    // el Swift tiene que dar exactamente el mismo número.
    private fun pct(games: List<GameRecord>): Int =
        Math.round(games.count { it.winner == Side.US } * 100.0f / games.size)
}
