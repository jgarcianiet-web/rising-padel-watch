package com.risingpadel.core.score

import kotlinx.serialization.Serializable

/** Los dos bandos de un partido de pádel, desde el punto de vista del jugador. */
@Serializable
enum class Side(val wireName: String) {
    US("us"),
    THEM("them");

    val other: Side get() = if (this == US) THEM else US

    companion object {
        fun fromWire(value: String): Side = if (value == "them") THEM else US
    }
}

/**
 * Reglas del partido. Cambian de una liga a otra, así que son configurables.
 *
 * @param goldenPoint punto de oro: a 40-40 el siguiente punto decide el juego, sin
 *   ventajas. Es lo habitual en ligas amateur y en circuito profesional, así que viene
 *   activado por defecto.
 */
@Serializable
data class ScoreRules(
    val goldenPoint: Boolean = true,
    val setsToWin: Int = 2,
    val gamesToWinSet: Int = 6,
    val tieBreakTarget: Int = 7,
) {
    companion object {
        val DEFAULT = ScoreRules()
    }
}

/** Juegos ganados por cada bando en un set. */
@Serializable
data class SetScore(val us: Int = 0, val them: Int = 0) {
    fun plus(side: Side): SetScore =
        if (side == Side.US) copy(us = us + 1) else copy(them = them + 1)

    fun forSide(side: Side): Int = if (side == Side.US) us else them

    val isEmpty: Boolean get() = us == 0 && them == 0
}

/**
 * Estado completo del marcador. Es inmutable: [pointTo] devuelve un estado nuevo.
 *
 * Toda la lógica del marcador vive aquí, sin nada de Android ni de UI, para poder
 * verificarla con tests. Ver `docs/scoring.md`.
 */
@Serializable
data class MatchScore(
    val rules: ScoreRules = ScoreRules.DEFAULT,
    val completedSets: List<SetScore> = emptyList(),
    val currentSet: SetScore = SetScore(),
    val usPoints: Int = 0,
    val themPoints: Int = 0,
    val server: Side = Side.US,
    /** Quién abrió el tie-break, para rotar el saque y decidir quién saca en el set siguiente. */
    val tieBreakFirstServer: Side? = null,
    val winner: Side? = null,
    /** True justo cuando acaba de tocar cambio de pista. Se apaga al siguiente punto. */
    val changeEndsPending: Boolean = false,
) {

    val isFinished: Boolean get() = winner != null

    /** En pádel el tie-break se juega al llegar a 6-6 en juegos. */
    val isTieBreak: Boolean
        get() = !isFinished &&
            currentSet.us == rules.gamesToWinSet &&
            currentSet.them == rules.gamesToWinSet

    /** Todos los sets, incluido el que está en juego si ya tiene algún juego. */
    val allSets: List<SetScore>
        get() = if (currentSet.isEmpty && completedSets.isNotEmpty()) completedSets
        else completedSets + currentSet

    fun setsWon(side: Side): Int = completedSets.count { it.forSide(side) > it.forSide(side.other) }

    fun pointsFor(side: Side): Int = if (side == Side.US) usPoints else themPoints

    /**
     * Etiqueta del marcador de juego: `0`, `15`, `30`, `40`, `AD` o el número crudo en
     * tie-break. Con punto de oro `AD` no aparece nunca, porque a 40-40 el siguiente
     * punto cierra el juego.
     */
    fun pointsLabel(side: Side): String {
        if (isTieBreak) return pointsFor(side).toString()
        val mine = pointsFor(side)
        val theirs = pointsFor(side.other)
        if (mine >= 3 && theirs >= 3) {
            return when {
                mine == theirs -> "40"
                mine > theirs -> "AD"
                else -> "40"
            }
        }
        return POINT_LABELS.getOrElse(mine) { "40" }
    }

    /** Anota un punto. Si el partido ya terminó, no hace nada. */
    fun pointTo(side: Side): MatchScore {
        if (isFinished) return this
        return if (isTieBreak) tieBreakPoint(side) else gamePoint(side)
    }

    // --- juego normal ---

    private fun gamePoint(side: Side): MatchScore {
        val mine = pointsFor(side) + 1
        val theirs = pointsFor(side.other)

        return if (gameWon(mine, theirs)) {
            afterGameWon(side)
        } else {
            withPoints(side, mine).copy(changeEndsPending = false)
        }
    }

    private fun gameWon(mine: Int, theirs: Int): Boolean = when {
        // Punto de oro: desde 40-40 el siguiente punto decide, así que basta con llegar
        // a 4 por delante sin exigir dos de diferencia.
        rules.goldenPoint -> mine >= 4 && mine > theirs
        else -> mine >= 4 && mine - theirs >= 2
    }

    private fun afterGameWon(side: Side): MatchScore {
        val newSet = currentSet.plus(side)
        val gamesTotal = newSet.us + newSet.them
        // Se cambia de pista tras cada juego impar del set.
        val changeEnds = gamesTotal % 2 == 1

        return if (setWon(newSet, side)) {
            afterSetWon(newSet, side)
        } else {
            copy(
                currentSet = newSet,
                usPoints = 0,
                themPoints = 0,
                server = server.other,
                tieBreakFirstServer = if (newSet.us == rules.gamesToWinSet &&
                    newSet.them == rules.gamesToWinSet
                ) server.other else null,
                changeEndsPending = changeEnds,
            )
        }
    }

    private fun setWon(set: SetScore, side: Side): Boolean {
        val mine = set.forSide(side)
        val theirs = set.forSide(side.other)
        return mine >= rules.gamesToWinSet && mine - theirs >= 2
    }

    // --- tie-break ---

    private fun tieBreakPoint(side: Side): MatchScore {
        val mine = pointsFor(side) + 1
        val theirs = pointsFor(side.other)

        if (mine >= rules.tieBreakTarget && mine - theirs >= 2) {
            return afterSetWon(currentSet.plus(side), side)
        }

        val playedPoints = mine + theirs
        return withPoints(side, mine).copy(
            server = tieBreakServerAfter(playedPoints),
            // En el tie-break se cambia de pista cada seis puntos.
            changeEndsPending = playedPoints % 6 == 0,
        )
    }

    /**
     * En el tie-break saca uno un punto y a partir de ahí se alterna cada dos, de modo
     * que cada bando saca siempre desde el mismo lado de la pista.
     */
    private fun tieBreakServerAfter(playedPoints: Int): Side {
        val first = tieBreakFirstServer ?: server
        val blocks = (playedPoints + 1) / 2
        return if (blocks % 2 == 0) first else first.other
    }

    // --- cierre de set y de partido ---

    private fun afterSetWon(set: SetScore, side: Side): MatchScore {
        val sets = completedSets + set
        val won = sets.count { it.forSide(side) > it.forSide(side.other) }

        // Quien abrió el tie-break resta primero en el set siguiente.
        val nextServer = tieBreakFirstServer?.other ?: server.other

        return copy(
            completedSets = sets,
            currentSet = SetScore(),
            usPoints = 0,
            themPoints = 0,
            server = nextServer,
            tieBreakFirstServer = null,
            winner = if (won >= rules.setsToWin) side else null,
            // Al empezar un set se cambia de pista salvo que el set anterior sumara un
            // número par de juegos.
            changeEndsPending = (set.us + set.them) % 2 == 1,
        )
    }

    private fun withPoints(side: Side, value: Int): MatchScore =
        if (side == Side.US) copy(usPoints = value) else copy(themPoints = value)

    companion object {
        private val POINT_LABELS = listOf("0", "15", "30", "40")

        fun start(rules: ScoreRules = ScoreRules.DEFAULT, firstServer: Side = Side.US) =
            MatchScore(rules = rules, server = firstServer)
    }
}
