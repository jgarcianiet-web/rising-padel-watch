package com.risingpadel.core.session

import com.risingpadel.core.detection.DetectorConfig
import com.risingpadel.core.detection.ShotDetector
import com.risingpadel.core.model.GameRecord
import com.risingpadel.core.model.HealthMetrics
import com.risingpadel.core.model.HeartRateSample
import com.risingpadel.core.model.HeartRateSummary
import com.risingpadel.core.model.HeartRateZones
import com.risingpadel.core.model.MatchRef
import com.risingpadel.core.model.MotionSample
import com.risingpadel.core.model.PadelSession
import com.risingpadel.core.model.PlayerProfile
import com.risingpadel.core.model.Shot
import com.risingpadel.core.model.ShotContext
import com.risingpadel.core.model.SourceInfo
import com.risingpadel.core.score.MatchScore
import com.risingpadel.core.score.Side
import kotlin.math.roundToInt

/**
 * Acumula una sesión en curso: golpeos detectados + métricas de salud del workout.
 *
 * Vive en el reloj y es el único punto donde se junta todo. Las apps solo tienen que
 * bombear muestras y métricas; el resultado es una [PadelSession] lista para enviar al
 * móvil.
 *
 * Los tiempos vienen por duplicado a propósito: **epoch** para fechar la sesión y
 * **monótono** para medir dentro de ella (el epoch puede saltar si el reloj se
 * sincroniza a mitad de partido).
 */
class SessionRecorder(
    private val source: SourceInfo,
    private val profile: PlayerProfile = PlayerProfile(),
    config: DetectorConfig = DetectorConfig.DEFAULT,
    private val currentYear: Int = 2026,
    private val sessionIdProvider: () -> String,
) {
    private val detector = ShotDetector(config, profile)
    private val maxHeartRate = profile.effectiveMaxHeartRate(currentYear)

    private var sessionId: String? = null
    private var startedAtEpochMs = 0L
    private var startedAtMonotonicMs = 0L

    private val collectedShots = mutableListOf<Shot>()

    private var lastHeartRateBpm: Int? = null
    private var lastHeartRateAtMs: Long? = null
    private var maxObservedBpm = 0
    private var weightedBpmSum = 0.0
    private var weightedSeconds = 0.0
    private val zoneSeconds = mutableMapOf<String, Double>()
    private val heartRateSeries = mutableListOf<HeartRateSample>()

    private var activeEnergyKcal: Float? = null
    private var totalEnergyKcal: Float? = null
    private var steps: Int? = null
    private var distanceMeters: Float? = null

    var matchRef: MatchRef? = null

    /**
     * Los movimientos que el detector vio y tiró en lo que va de sesión.
     *
     * Se expone en vivo y no solo al acabar porque es lo que hace falta para poder
     * enseñarlo en la ficha de la sesión sin esperar a que termine.
     */
    val descartes get() = detector.descartes

    private val gameRecords = mutableListOf<GameRecord>()

    /**
     * Puntos jugados en lo que va de partido, para poder situar cada golpeo.
     *
     * Se cuenta aquí y no se saca del marcador porque [MatchScore] guarda el tanteo
     * (15-30, sets ganados), no cuántos puntos se llevan jugados: al cerrarse un juego
     * los puntos vuelven a cero y esa cuenta se perdería.
     */
    private var pointsPlayed = 0

    /** Juegos cerrados hasta ahora. */
    val games: List<GameRecord> get() = gameRecords

    /**
     * Avisa de un cambio del marcador para anotar los juegos que se cierren.
     *
     * Se compara antes/después en vez de que el llamante decida: así el reloj solo tiene
     * que pasar los dos marcadores y la regla de "cuándo se cerró un juego y quién
     * sacaba" vive en un único sitio, con tests.
     *
     * El servidor del juego es el de **antes** del punto: al cerrarse un juego el
     * marcador ya ha rotado el saque para el siguiente.
     */
    fun onScoreChanged(previous: MatchScore, current: MatchScore, monotonicMs: Long) {
        // Cualquier cambio de marcador es un punto jugado, se cerrara juego o no.
        if (current != previous) pointsPlayed++

        val closedForUs = current.gamesWon(Side.US) - previous.gamesWon(Side.US)
        val closedForThem = current.gamesWon(Side.THEM) - previous.gamesWon(Side.THEM)
        val winner = when {
            closedForUs > 0 -> Side.US
            closedForThem > 0 -> Side.THEM
            else -> return
        }
        gameRecords += GameRecord(
            offsetMs = (monotonicMs - startedAtMonotonicMs).coerceAtLeast(0),
            server = previous.server,
            winner = winner,
        )
    }

    /**
     * Marcador del partido, si el jugador lo está llevando. El reloj lo mantiene aparte
     * del conteo de golpeos: se puede jugar con marcador y sin él, y una sesión sin
     * marcador sigue siendo una sesión válida.
     */
    var score: MatchScore? = null

    /**
     * Esto es un partido, lo lleve el marcador o no. Lo pone quien arranca la sesión.
     *
     * Va aparte de `score` porque "sin marcador" y "sin partido" no son lo mismo: un
     * partido jugado sin ir anotando punto por punto sigue siendo un partido y tiene
     * que entrar en la liga. Ver `PadelSession.esPartido`.
     */
    var esPartido: Boolean = false

    val shots: List<Shot> get() = collectedShots
    val isRecording: Boolean get() = sessionId != null

    /** Identificador de la sesión en curso, para etiquetar el estado en vivo. */
    val currentSessionId: String? get() = sessionId

    fun start(startedAtEpochMs: Long, monotonicMs: Long) {
        sessionId = sessionIdProvider()
        this.startedAtEpochMs = startedAtEpochMs
        this.startedAtMonotonicMs = monotonicMs
        collectedShots.clear()
        gameRecords.clear()
        // Se limpian aquí: son de la sesión que acaba de terminar, y arrastrar el
        // marcador o el "esto era un partido" del partido anterior a un entreno suelto
        // metería en la liga algo que nadie jugó.
        score = null
        esPartido = false
        lastHeartRateBpm = null
        lastHeartRateAtMs = null
        maxObservedBpm = 0
        weightedBpmSum = 0.0
        weightedSeconds = 0.0
        zoneSeconds.clear()
        heartRateSeries.clear()
        activeEnergyKcal = null
        totalEnergyKcal = null
        steps = null
        distanceMeters = null
        detector.reset(monotonicMs)
    }

    /** Devuelve el golpeo si esta muestra cierra uno, para poder avisar en la UI al instante. */
    fun onMotion(sample: MotionSample): Shot? =
        detector.process(sample)
            ?.copy(context = contextoDeJuego())
            ?.also { collectedShots.add(it) }

    /**
     * Dónde cae este golpe dentro del partido y con qué pulso.
     *
     * Lo pone el recorder y no el detector a propósito: el detector es una función pura
     * de la señal —los mismos milisegundos dan siempre lo mismo, que es lo que permite
     * reclasificar una tanda mañana con otro modelo— y el marcador no forma parte de la
     * señal. Ver [ShotContext].
     *
     * Devuelve null cuando no hay nada que contar: sin marcador ni pulso, un contexto
     * con los cuatro campos vacíos solo ocuparía sitio en el fichero.
     */
    private fun contextoDeJuego(): ShotContext? {
        val marcador = score
        val pulso = lastHeartRateBpm
        if (marcador == null && pulso == null) return null
        return ShotContext(
            pointIndex = if (marcador == null) null else pointsPlayed + 1,
            gameIndex = marcador?.let {
                it.gamesWon(Side.US) + it.gamesWon(Side.THEM) + 1
            },
            setIndex = marcador?.let { it.completedSets.size + 1 },
            heartRateBpm = pulso,
        )
    }

    /**
     * Cada lectura de FC cierra el intervalo anterior: el tiempo transcurrido desde la
     * lectura previa se atribuye a la zona de **esa** lectura previa, que es la que
     * estuvo vigente durante el intervalo.
     */
    fun onHeartRate(bpm: Int, monotonicMs: Long) {
        if (bpm <= 0) return
        val previousBpm = lastHeartRateBpm
        val previousAt = lastHeartRateAtMs
        if (previousBpm != null && previousAt != null) {
            val elapsed = ((monotonicMs - previousAt) / 1000.0).coerceIn(0.0, 60.0)
            if (elapsed > 0.0) {
                val zone = HeartRateZones.zoneFor(previousBpm, maxHeartRate)
                zoneSeconds[zone] = (zoneSeconds[zone] ?: 0.0) + elapsed
                weightedBpmSum += previousBpm * elapsed
                weightedSeconds += elapsed
            }
        }
        lastHeartRateBpm = bpm
        lastHeartRateAtMs = monotonicMs
        if (bpm > maxObservedBpm) maxObservedBpm = bpm

        // Una lectura por minuto para la serie: suficiente para cruzar pulso con
        // rendimiento y dos órdenes de magnitud menos de datos que guardarlas todas.
        val offset = (monotonicMs - startedAtMonotonicMs).coerceAtLeast(0)
        val last = heartRateSeries.lastOrNull()
        if (last == null || offset - last.offsetMs >= HR_SERIES_INTERVAL_MS) {
            heartRateSeries.add(HeartRateSample(offsetMs = offset, bpm = bpm))
        }
    }

    /** Valores acumulados del workout; se sustituyen, no se suman. */
    fun onEnergy(activeKcal: Float?, totalKcal: Float? = null) {
        activeKcal?.let { activeEnergyKcal = it }
        totalKcal?.let { totalEnergyKcal = it }
    }

    fun onSteps(count: Int) {
        steps = count
    }

    fun onDistance(meters: Float) {
        distanceMeters = meters
    }

    /**
     * Cierra la sesión. [shareHealth] es el consentimiento del usuario: si es false, la
     * sesión sale sin ningún dato de salud (no se recorta después, no se construye).
     */
    fun finish(endedAtEpochMs: Long, monotonicMs: Long, shareHealth: Boolean): PadelSession {
        val id = requireNotNull(sessionId) { "finish() sin start()" }
        detector.flush()?.let { collectedShots.add(it) }
        // Cierra el último intervalo de FC con el instante de fin.
        lastHeartRateBpm?.let { onHeartRate(it, monotonicMs) }

        val session = PadelSession(
            sessionId = id,
            source = source,
            startedAtEpochMs = startedAtEpochMs,
            endedAtEpochMs = endedAtEpochMs,
            profile = profile,
            shots = collectedShots.toList(),
            health = if (shareHealth) buildHealth() else HealthMetrics.EMPTY,
            score = score,
            esPartido = esPartido,
            games = gameRecords.toList(),
            matchRef = matchRef,
            // Lo que se le escapó. Se guarda aunque sea cero: un cero es información
            // ("no se dejó nada") y un nulo es "esta sesión es de antes de medirlo".
            descartes = detector.descartes,
        )
        sessionId = null
        return session
    }

    /** Métricas parciales para la pantalla del reloj mientras se juega. */
    fun liveSnapshot(monotonicMs: Long): LiveStats {
        val elapsedSeconds = ((monotonicMs - startedAtMonotonicMs) / 1000).coerceAtLeast(0)
        return LiveStats(
            elapsedSeconds = elapsedSeconds,
            shotCount = collectedShots.size,
            currentHeartRate = lastHeartRateBpm,
            activeEnergyKcal = activeEnergyKcal,
            lastShot = collectedShots.lastOrNull(),
        )
    }

    private fun buildHealth(): HealthMetrics {
        val heartRate = if (maxObservedBpm > 0) {
            HeartRateSummary(
                meanBpm = if (weightedSeconds > 0) (weightedBpmSum / weightedSeconds).roundToInt()
                else maxObservedBpm,
                maxBpm = maxObservedBpm,
                restingBpm = profile.restingHeartRate,
            )
        } else {
            null
        }
        return HealthMetrics(
            heartRate = heartRate,
            activeEnergyKcal = activeEnergyKcal,
            totalEnergyKcal = totalEnergyKcal,
            steps = steps,
            distanceMeters = distanceMeters,
            zones = HeartRateZones(zoneSeconds.mapValues { it.value.roundToInt() }),
            heartRateSeries = heartRateSeries.toList(),
        )
    }

    private companion object {
        const val HR_SERIES_INTERVAL_MS = 60_000L
    }
}

data class LiveStats(
    val elapsedSeconds: Long,
    val shotCount: Int,
    val currentHeartRate: Int?,
    val activeEnergyKcal: Float?,
    val lastShot: Shot?,
)
