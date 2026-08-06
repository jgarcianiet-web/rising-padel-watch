package com.risingpadel.wear.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.lifecycle.LifecycleService
import androidx.lifecycle.lifecycleScope
import com.risingpadel.core.detection.DetectorConfig
import com.risingpadel.core.level.SessionLevel
import com.risingpadel.core.model.Platform
import com.risingpadel.core.model.ShotType
import com.risingpadel.core.model.SourceInfo
import com.risingpadel.core.score.MatchScore
import com.risingpadel.core.score.ScoreRules
import com.risingpadel.core.score.Side
import com.risingpadel.core.session.SessionRecorder
import com.risingpadel.core.sync.LiveScorePayload
import com.risingpadel.core.sync.toPayload
import java.time.Instant
import com.risingpadel.wear.PadelWearApp
import com.risingpadel.wear.R
import com.risingpadel.wear.ui.MainActivity
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.util.UUID

enum class SessionStatus { IDLE, PREPARING, RECORDING, SAVING, SAVED, ERROR }

data class SessionUiState(
    val status: SessionStatus = SessionStatus.IDLE,
    val elapsedSeconds: Long = 0,
    val shotCount: Int = 0,
    val heartRateBpm: Int? = null,
    val activeEnergyKcal: Float? = null,
    val lastShotType: ShotType? = null,
    val wrongWristWarning: Boolean = false,
    /** Nivel técnico de la sesión. Solo al terminar: en vivo no aporta y distrae. */
    val level: SessionLevel? = null,
    val errorMessage: String? = null,
)

/**
 * Lleva la sesión de principio a fin: workout de Health Services + muestreo de sensores
 * + detección + envío al móvil.
 *
 * Es un servicio en primer plano porque el jugador apaga la pantalla entre puntos y
 * guarda el brazo: si esto viviera en la Activity, Android mataría la medición a los
 * pocos segundos.
 */
class PadelExerciseService : LifecycleService() {

    /** Una sesión normal y una tanda de datos usan los mismos sensores pero no se mezclan. */
    private enum class Mode { SESSION, TRAINING }

    private var mode = Mode.SESSION
    private var recorder: SessionRecorder? = null
    private var motionJob: Job? = null
    private var metricsJob: Job? = null
    private var tickerJob: Job? = null
    private var shareHealth = false

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        super.onStartCommand(intent, flags, startId)
        when (intent?.action) {
            ACTION_START -> startSession()
            ACTION_START_TRAINING -> startTraining()
            ACTION_STOP -> if (mode == Mode.TRAINING) stopTraining() else stopSession()
            else -> stopSelf()
        }
        return START_NOT_STICKY
    }

    /**
     * Graba una tanda de golpeos etiquetados. Comparte el servicio en primer plano con
     * la sesión normal porque el problema es el mismo: sin él, Android corta los
     * sensores en cuanto se apaga la pantalla, y grabar treinta golpes lleva minutos.
     */
    private fun startTraining() {
        if (_state.value.status == SessionStatus.RECORDING) return
        mode = Mode.TRAINING
        _state.value = SessionUiState(status = SessionStatus.PREPARING)
        if (!goForeground()) return

        lifecycleScope.launch {
            val container = (application as PadelWearApp).container
            val preferences = container.settings.preferences.first()

            if (!container.motionCollector.isSupported) {
                fail("Este reloj no tiene los sensores necesarios")
                return@launch
            }

            container.trainingSession.start(
                source = SourceInfo(
                    platform = Platform.WEAROS,
                    device = "${Build.MANUFACTURER} ${Build.MODEL}",
                    appVersion = container.appVersion,
                ),
                profile = preferences.profile,
                config = DetectorConfig.DEFAULT.withSensitivity(preferences.sensitivity),
                playerAlias = preferences.playerAlias,
                playerLevel = preferences.playerLevel,
                monotonicMs = SystemClock.elapsedRealtime(),
            )

            motionJob = launch {
                container.motionCollector.samples(DetectorConfig.DEFAULT.sampleRateHz)
                    .catch { fail("Fallo leyendo sensores: ${it.message}") }
                    .collect { container.trainingSession.onMotion(it) }
            }

            _state.value = _state.value.copy(status = SessionStatus.RECORDING)
        }
    }

    private fun stopTraining() {
        motionJob?.cancel()
        (application as PadelWearApp).container.trainingSession.stop()
        mode = Mode.SESSION
        _state.value = SessionUiState()
        stopForegroundAndSelf()
    }

    private fun startSession() {
        if (_state.value.status == SessionStatus.RECORDING) return
        mode = Mode.SESSION
        _state.value = SessionUiState(status = SessionStatus.PREPARING)
        if (!goForeground()) return

        lifecycleScope.launch {
            val container = (application as PadelWearApp).container
            val preferences = container.settings.preferences.first()
            shareHealth = preferences.shareHealth

            if (!container.motionCollector.isSupported) {
                fail("Este reloj no tiene los sensores necesarios")
                return@launch
            }

            val newRecorder = SessionRecorder(
                source = SourceInfo(
                    platform = Platform.WEAROS,
                    device = "${Build.MANUFACTURER} ${Build.MODEL}",
                    appVersion = container.appVersion,
                ),
                profile = preferences.profile,
                config = DetectorConfig.DEFAULT.withSensitivity(preferences.sensitivity),
                sessionIdProvider = { UUID.randomUUID().toString() },
            )
            recorder = newRecorder

            val startedAtEpochMs = System.currentTimeMillis()
            newRecorder.start(startedAtEpochMs, SystemClock.elapsedRealtime())

            if (preferences.trackScore) {
                container.scoreSession.start(
                    rules = ScoreRules(
                        deuceFormat = preferences.deuceFormat,
                        setsToWin = preferences.setsToWin,
                    ),
                    firstServer = Side.US,
                )
            }

            // Los datos de salud son opcionales: si el usuario no ha dado permiso o el
            // reloj no los soporta, la sesión sigue midiendo golpeos.
            if (shareHealth) startExerciseTracking(container)

            motionJob = launch {
                container.motionCollector.samples(DetectorConfig.DEFAULT.sampleRateHz)
                    .catch { fail("Fallo leyendo sensores: ${it.message}") }
                    .collect { sample ->
                        newRecorder.onMotion(sample)?.let { shot ->
                            _state.value = _state.value.copy(lastShotType = shot.type)
                        }
                    }
            }

            tickerJob = launch {
                container.liveStateSender.reset()
                while (isActive) {
                    publishSnapshot(preferences.profile.watchOnRacketArm)
                    // El estado en vivo viaja al móvil, que lo republica al servidor
                    // con su token. Deduplicado en el emisor: solo va lo que cambió.
                    publishLive(container, completed = false)
                    delay(1_000)
                }
            }

            _state.value = _state.value.copy(
                status = SessionStatus.RECORDING,
                wrongWristWarning = !preferences.profile.watchOnRacketArm,
            )
        }
    }

    private suspend fun startExerciseTracking(container: com.risingpadel.wear.WearContainer) {
        val tracker = container.exerciseTracker
        val dataTypes = runCatching { tracker.supportedDataTypes() }.getOrDefault(emptySet())
        if (dataTypes.isEmpty()) return

        runCatching {
            tracker.warmUp(dataTypes)
            tracker.start(dataTypes)
        }.onFailure { return }

        metricsJob = lifecycleScope.launch {
            tracker.metrics()
                .catch { /* la sesión sigue sin métricas de salud */ }
                .collect { metrics ->
                    val current = recorder ?: return@collect
                    metrics.heartRateBpm?.let { current.onHeartRate(it, SystemClock.elapsedRealtime()) }
                    current.onEnergy(activeKcal = metrics.activeEnergyKcal)
                    metrics.steps?.let { current.onSteps(it) }
                    metrics.distanceMeters?.let { current.onDistance(it) }
                }
        }
    }

    private fun stopSession() {
        val current = recorder
        if (current == null || !current.isRecording) {
            stopForegroundAndSelf()
            return
        }
        _state.value = _state.value.copy(status = SessionStatus.SAVING)

        lifecycleScope.launch {
            motionJob?.cancel()
            tickerJob?.cancel()
            metricsJob?.cancel()

            val container = (application as PadelWearApp).container
            runCatching { container.exerciseTracker.end() }

            // El último estado en vivo sale ANTES de cerrar el marcador, con
            // completed=true: es lo que apunta el resultado al ranking y saca al
            // jugador de "está jugando ahora".
            publishLive(container, completed = true)

            // El marcador se cierra antes que la sesión para que el resultado viaje
            // dentro de ella y no en un mensaje aparte que pueda perderse.
            current.score = container.scoreSession.finish()

            val session = current.finish(
                endedAtEpochMs = System.currentTimeMillis(),
                monotonicMs = SystemClock.elapsedRealtime(),
                shareHealth = shareHealth,
            )
            recorder = null

            val sent = runCatching { container.phoneSender.send(session) }.isSuccess
            _state.value = _state.value.copy(
                status = SessionStatus.SAVED,
                shotCount = session.totalShots,
                elapsedSeconds = session.durationSeconds,
                level = session.level.takeIf { it.gradedShots > 0 },
                errorMessage = if (sent) null else "Guardada en el reloj; se enviará al móvil al reconectar",
            )
            stopForegroundAndSelf()
        }
    }

    /// El estado en vivo del partido, con el mismo shape que publica el Apple Watch.
    private suspend fun publishLive(
        container: com.risingpadel.wear.WearContainer,
        completed: Boolean,
    ) {
        val current = recorder ?: return
        val sessionId = current.currentSessionId ?: return
        val score: MatchScore? = container.scoreSession.state.value
        val ui = _state.value
        container.liveStateSender.sendIfChanged(
            LiveScorePayload(
                sessionId = sessionId,
                updatedAt = Instant.now().toString(),
                completed = completed || score?.isFinished == true,
                score = score?.toPayload(),
                pointsUs = score?.takeIf { !it.isFinished }?.pointsLabel(Side.US),
                pointsThem = score?.takeIf { !it.isFinished }?.pointsLabel(Side.THEM),
                serving = score?.takeIf { !it.isFinished }?.server?.wireName,
                shotCount = ui.shotCount,
                heartRateBpm = if (shareHealth) ui.heartRateBpm else null,
                elapsedSeconds = ui.elapsedSeconds,
            )
        )
    }

    private fun publishSnapshot(watchOnRacketArm: Boolean) {
        val snapshot = recorder?.liveSnapshot(SystemClock.elapsedRealtime()) ?: return
        _state.value = _state.value.copy(
            status = SessionStatus.RECORDING,
            elapsedSeconds = snapshot.elapsedSeconds,
            shotCount = snapshot.shotCount,
            heartRateBpm = snapshot.currentHeartRate,
            activeEnergyKcal = snapshot.activeEnergyKcal,
            lastShotType = snapshot.lastShot?.type,
            wrongWristWarning = !watchOnRacketArm,
        )
        updateNotification(snapshot.shotCount, snapshot.elapsedSeconds)
    }

    private fun fail(message: String) {
        _state.value = _state.value.copy(status = SessionStatus.ERROR, errorMessage = message)
        stopForegroundAndSelf()
    }

    private fun stopForegroundAndSelf() {
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    /**
     * @return false si el sistema no deja arrancar en primer plano, en cuyo caso no se
     *   puede medir: sin servicio en primer plano Android corta los sensores en cuanto
     *   se apaga la pantalla, y una sesión que se para sola a los diez segundos es peor
     *   que no empezarla.
     */
    private fun goForeground(): Boolean {
        createChannel()
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH
        } else {
            0
        }
        return try {
            ServiceCompat.startForeground(this, NOTIFICATION_ID, buildNotification(0, 0), type)
            true
        } catch (e: Exception) {
            // Desde Android 14 un servicio de tipo `health` exige tener concedido alguno
            // de los permisos de salud; sin ellos esto lanza SecurityException.
            _state.value = SessionUiState(
                status = SessionStatus.ERROR,
                errorMessage = "Concede el permiso de sensores para poder medir con la pantalla apagada",
            )
            stopSelf()
            false
        }
    }

    private fun updateNotification(shots: Int, elapsedSeconds: Long) {
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, buildNotification(shots, elapsedSeconds))
    }

    private fun buildNotification(shots: Int, elapsedSeconds: Long): Notification {
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val minutes = elapsedSeconds / 60
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.session_in_progress))
            .setContentText(getString(R.string.session_progress_format, shots, minutes))
            .setSmallIcon(R.drawable.ic_padel_notification)
            .setOngoing(true)
            .setContentIntent(open)
            .setCategory(NotificationCompat.CATEGORY_WORKOUT)
            .build()
    }

    private fun createChannel() {
        val manager = getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                getString(R.string.session_channel_name),
                NotificationManager.IMPORTANCE_LOW,
            )
        )
    }

    companion object {
        private const val CHANNEL_ID = "padel_session"
        private const val NOTIFICATION_ID = 1001
        const val ACTION_START = "com.risingpadel.wear.START"
        const val ACTION_START_TRAINING = "com.risingpadel.wear.START_TRAINING"
        const val ACTION_STOP = "com.risingpadel.wear.STOP"

        private val _state = MutableStateFlow(SessionUiState())
        val state: StateFlow<SessionUiState> = _state.asStateFlow()

        fun start(context: Context) {
            context.startForegroundService(
                Intent(context, PadelExerciseService::class.java).setAction(ACTION_START)
            )
        }

        fun startTraining(context: Context) {
            context.startForegroundService(
                Intent(context, PadelExerciseService::class.java).setAction(ACTION_START_TRAINING)
            )
        }

        fun stop(context: Context) {
            context.startService(
                Intent(context, PadelExerciseService::class.java).setAction(ACTION_STOP)
            )
        }

        /** Devuelve la UI al estado inicial tras enseñar el resumen. */
        fun acknowledge() {
            _state.value = SessionUiState()
        }
    }
}
