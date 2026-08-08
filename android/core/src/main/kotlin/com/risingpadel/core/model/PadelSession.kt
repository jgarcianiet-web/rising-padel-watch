package com.risingpadel.core.model

import com.risingpadel.core.level.LevelConfig
import com.risingpadel.core.level.LevelEstimator
import com.risingpadel.core.level.SessionLevel
import com.risingpadel.core.score.MatchScore
import kotlinx.serialization.Serializable

@Serializable
enum class Platform(val wireName: String) {
    WATCHOS("watchos"),
    WEAROS("wearos"),
}

@Serializable
data class SourceInfo(
    val platform: Platform,
    val device: String,
    val appVersion: String,
)

@Serializable
data class MatchRef(
    val matchId: String,
    val leagueId: String? = null,
)

/**
 * Un juego terminado: cuándo acabó, quién sacaba y quién lo ganó.
 *
 * Es lo que permite separar el rendimiento **al saque** del rendimiento **al resto**, que
 * en pádel son dos juegos distintos: con el saque en la mano subes a la red desde el
 * primer golpe, y restando tienes que ganártela. Sin esta lista, un golpeo es solo un
 * golpeo y no se puede decir en cuál de las dos situaciones juegas mejor.
 */
@Serializable
data class GameRecord(
    /** Milisegundos desde el inicio de la sesión hasta el final del juego. */
    val offsetMs: Long,
    val server: com.risingpadel.core.score.Side,
    val winner: com.risingpadel.core.score.Side,
)

@Serializable
data class ShotIntensity(
    val meanRacketSpeedKmh: Float,
    val maxRacketSpeedKmh: Float,
    val meanImpactG: Float,
    val maxImpactG: Float,
) {
    companion object {
        val EMPTY = ShotIntensity(0f, 0f, 0f, 0f)

        fun from(shots: List<Shot>): ShotIntensity {
            if (shots.isEmpty()) return EMPTY
            return ShotIntensity(
                meanRacketSpeedKmh = shots.map { it.racketSpeedKmh }.average().toFloat(),
                maxRacketSpeedKmh = shots.maxOf { it.racketSpeedKmh },
                meanImpactG = shots.map { it.impactG }.average().toFloat(),
                maxImpactG = shots.maxOf { it.impactG },
            )
        }
    }
}

/** Zonas de frecuencia cardiaca como % de la FC máxima: z1 <60, z2 60-70, z3 70-80, z4 80-90, z5 >=90. */
@Serializable
data class HeartRateZones(val secondsPerZone: Map<String, Int>) {
    companion object {
        val EMPTY = HeartRateZones(emptyMap())
        val ZONE_KEYS = listOf("z1", "z2", "z3", "z4", "z5")

        fun zoneFor(bpm: Int, maxHeartRate: Int): String {
            val pct = bpm.toFloat() / maxHeartRate
            return when {
                pct < 0.60f -> "z1"
                pct < 0.70f -> "z2"
                pct < 0.80f -> "z3"
                pct < 0.90f -> "z4"
                else -> "z5"
            }
        }
    }
}

@Serializable
data class HeartRateSummary(
    val meanBpm: Int,
    val maxBpm: Int,
    val restingBpm: Int? = null,
)

/**
 * Una lectura de pulso dentro de la sesión, con su minuto.
 *
 * Se guarda una por minuto, no todas: con una por minuto ya se puede cruzar el pulso con
 * el rendimiento —que es lo que hace útil la serie— y una sesión de dos horas ocupa 120
 * números en vez de siete mil.
 */
@Serializable
data class HeartRateSample(val offsetMs: Long, val bpm: Int)

/**
 * Métricas de salud del entrenamiento. Se omiten por completo del payload si el
 * usuario no ha dado el consentimiento de compartir datos de salud.
 */
@Serializable
data class HealthMetrics(
    val heartRate: HeartRateSummary? = null,
    val activeEnergyKcal: Float? = null,
    val totalEnergyKcal: Float? = null,
    val steps: Int? = null,
    val distanceMeters: Float? = null,
    val zones: HeartRateZones = HeartRateZones.EMPTY,
    /** Pulso a lo largo de la sesión, una lectura por minuto. */
    val heartRateSeries: List<HeartRateSample> = emptyList(),
) {
    val isEmpty: Boolean
        get() = heartRate == null && activeEnergyKcal == null && totalEnergyKcal == null &&
            steps == null && distanceMeters == null && zones.secondsPerZone.isEmpty()

    companion object {
        val EMPTY = HealthMetrics()
    }
}

/**
 * Lo que costó de batería medir esta sesión.
 *
 * Es la pregunta que hace todo el mundo antes de comprar un reloj deportivo y la única
 * que no se puede contestar mirando código: depende del reloj, de su edad, del frío y de
 * si había pulso encendido. Se apunta el nivel al empezar y al acabar, y con unas cuantas
 * sesiones la app da un número real en vez de una promesa.
 *
 * Los porcentajes son 0-100 tal y como los da el sistema.
 */
@Serializable
data class BatteryUse(
    val startPercent: Int,
    val endPercent: Int,
) {
    /**
     * Puntos de batería gastados. Negativo imposible: si el reloj estuvo cargando durante
     * la sesión, el dato no vale y se descarta arriba, no se convierte en un cero que
     * parecería "no gastó nada".
     */
    val consumido: Int get() = startPercent - endPercent
}

/** Estado de sincronización de una sesión con la app de liga. */
@Serializable
enum class SyncState {
    /** Aún no se ha intentado, o se reintentará. */
    PENDING,

    /** Confirmada por el servidor. */
    SYNCED,

    /** Fallo permanente (400/409/versión de esquema): no se reintenta solo. */
    FAILED,

    /** El token no vale: hace falta que el usuario vuelva a conectar la liga. */
    NEEDS_AUTH,
}

/**
 * La revisión del jugador tras la sesión: "el reloj contó 14 bandejas, fueron 12".
 *
 * Es la verdad-terreno de la detección. Los recuentos corregidos mandan sobre los del
 * reloj en la liga y en los objetivos, y la comparación entre ambos es la medida real
 * de la precisión del detector — el dato que ninguna prueba de laboratorio puede dar.
 * Las claves son los `wireName` del contrato, para que la revisión sobreviva a
 * renombrar los casos del enum.
 */
@Serializable
data class SessionReview(
    /** Recuento corregido por tipo de golpe. Solo los tipos que el jugador tocó. */
    val correctedCounts: Map<String, Int>,
    val reviewedAtEpochMs: Long,
)

@Serializable
data class SyncStatus(
    val state: SyncState = SyncState.PENDING,
    val attempts: Int = 0,
    val lastAttemptAtEpochMs: Long? = null,
    val nextAttemptAtEpochMs: Long? = null,
    val lastError: String? = null,
    val remoteId: String? = null,
)

/** Una sesión de pádel completa, tal y como la construye el reloj. */
@Serializable
data class PadelSession(
    val sessionId: String,
    val source: SourceInfo,
    val startedAtEpochMs: Long,
    val endedAtEpochMs: Long,
    val profile: PlayerProfile,
    val shots: List<Shot>,
    val health: HealthMetrics = HealthMetrics.EMPTY,
    /** Marcador del partido. Null si se jugó sin llevarlo (entreno suelto). */
    val score: MatchScore? = null,
    /** Juegos terminados, en orden. Vacío si se jugó sin marcador. */
    val games: List<GameRecord> = emptyList(),
    val matchRef: MatchRef? = null,
    val sync: SyncStatus = SyncStatus(),
    /** Corrección del jugador tras revisar los recuentos. Null sin revisar. */
    val review: SessionReview? = null,
    /** Batería del reloj al empezar y al acabar. Null si el reloj no supo decirla. */
    val battery: BatteryUse? = null,
) {
    val durationSeconds: Long get() = ((endedAtEpochMs - startedAtEpochMs) / 1000).coerceAtLeast(0)

    val totalShots: Int get() = shots.size

    val shotsByType: Map<ShotType, Int>
        get() = shots.groupingBy { it.type }.eachCount()

    /**
     * Recuentos con la corrección del jugador aplicada; sin revisión, los del reloj.
     *
     * Es lo que deben leer la liga y los objetivos: si el jugador dijo que fueron 12
     * bandejas, fueron 12. Los recuentos del reloj quedan intactos en `shotsByType`
     * para poder medir siempre cuánto se equivocó.
     */
    val effectiveShotsByType: Map<ShotType, Int>
        get() {
            val revision = review ?: return shotsByType
            val counts = shotsByType.toMutableMap()
            for ((wire, corrected) in revision.correctedCounts) {
                counts[ShotType.fromWire(wire)] = corrected
            }
            return counts.filterValues { it > 0 }
        }

    val effectiveTotalShots: Int
        get() = if (review == null) totalShots else effectiveShotsByType.values.sum()

    /**
     * Precisión del reloj según la revisión, de 0 a 1. Null sin revisar.
     *
     * Se compara tipo a tipo: contar 14 bandejas cuando fueron 12 y 4 víboras cuando
     * fueron 6 son cuatro fallos, aunque el total (18) coincida.
     */
    val reviewAccuracy: Float?
        get() {
            if (review == null) return null
            val detected = shotsByType
            val effective = effectiveShotsByType
            val types = detected.keys + effective.keys
            var errores = 0
            var reales = 0
            for (type in types) {
                errores += kotlin.math.abs((detected[type] ?: 0) - (effective[type] ?: 0))
                reales += effective[type] ?: 0
            }
            if (reales == 0) return if (errores == 0) 1f else 0f
            return (1f - errores.toFloat() / reales).coerceAtLeast(0f)
        }

    val intensity: ShotIntensity get() = ShotIntensity.from(shots)

    /**
     * Nivel técnico estimado, de 1 a 7.
     *
     * Es una propiedad **derivada** y no un campo guardado: se recalcula de los golpeos
     * cada vez. Así no puede quedar desincronizada, y afinar las bandas de
     * [com.risingpadel.core.level.LevelConfig] cambia el nivel de las sesiones ya
     * grabadas sin migrar nada — que es justo lo que hace falta mientras el modelo esté
     * sin calibrar.
     */
    val level: SessionLevel get() = LevelEstimator(LevelConfig.current).estimate(shots)

    /** Golpeos por minuto, la métrica más comparable entre sesiones de distinta duración. */
    val shotsPerMinute: Float
        get() = if (durationSeconds <= 0) 0f else totalShots * 60f / durationSeconds

    /**
     * Versión del esquema que se declara al subir **esta** sesión.
     *
     * Solo sube a 2 cuando la sesión lleva marcador. Así una liga que todavía solo
     * entiende v1 sigue aceptando los entrenos sin marcador, y en cambio rechaza de
     * forma visible las sesiones con resultado en vez de tragárselas ignorando el
     * marcador en silencio: perder el resultado sin avisar sería peor que fallar.
     */
    val schemaVersion: Int
        get() = if (score != null) SCHEMA_VERSION_WITH_SCORE else SCHEMA_VERSION_BASE

    companion object {
        const val SCHEMA_VERSION_BASE = 1
        const val SCHEMA_VERSION_WITH_SCORE = 2
    }
}
