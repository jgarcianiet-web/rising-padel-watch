package com.risingpadel.mobile.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.risingpadel.core.detection.Sensitivity
import com.risingpadel.core.model.Hand
import com.risingpadel.core.model.MatchRef
import com.risingpadel.core.model.PadelSession
import com.risingpadel.core.model.PlayerProfile
import com.risingpadel.mobile.PadelMobileApp
import com.risingpadel.mobile.data.AppPreferences
import com.risingpadel.mobile.sync.SyncScheduler
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class PadelViewModel(application: Application) : AndroidViewModel(application) {

    private val container = (application as PadelMobileApp).container

    val sessions: StateFlow<List<PadelSession>> = container.sessions.sessions

    val preferences: StateFlow<AppPreferences> = container.settings.preferences
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), AppPreferences())

    private val _message = MutableStateFlow<String?>(null)
    val message: StateFlow<String?> = _message.asStateFlow()

    init {
        viewModelScope.launch { container.sessions.refresh() }
        replicateSettingsToWatch()
    }

    /**
     * Manda al reloj cada cambio de ajustes.
     *
     * Se observa el flujo entero en vez de llamar al emisor en cada setter: así un ajuste
     * nuevo se replica solo, sin que haya que acordarse de añadir la llamada. El
     * `distinctUntilChanged` evita reenviar cuando cambia algo que el reloj no usa.
     */
    private fun replicateSettingsToWatch() {
        viewModelScope.launch {
            container.settings.preferences
                .map { it.toDeviceSettings() }
                .distinctUntilChanged()
                // Sin ninguna edición todavía no hay nada que replicar, y mandarlo
                // pisaría con valores por defecto lo que el reloj pudiera tener.
                .filter { it.updatedAtEpochMs > 0 }
                .collect { container.watchSettingsSender.send(it) }
        }
    }

    fun refresh() {
        viewModelScope.launch { container.sessions.refresh() }
    }

    fun syncNow() {
        val app = getApplication<Application>()
        viewModelScope.launch {
            val current = preferences.value
            if (container.settings.leagueConfig(current.leagueBaseUrl) == null) {
                _message.value = "Configura la URL de la liga y el token en Ajustes"
                return@launch
            }
            SyncScheduler.requestSyncNow(app)
            _message.value = "Sincronizando…"
        }
    }

    fun retrySession(sessionId: String) {
        viewModelScope.launch {
            container.syncQueue.requeue(sessionId)
            container.sessions.refresh()
            SyncScheduler.requestSyncNow(getApplication())
        }
    }

    fun deleteSession(sessionId: String) {
        viewModelScope.launch { container.sessions.delete(sessionId) }
    }

    /** Vincula la sesión con un partido de la liga y la devuelve a la cola de subida. */
    fun linkToMatch(sessionId: String, matchId: String, leagueId: String?) {
        viewModelScope.launch {
            val session = container.sessions.get(sessionId) ?: return@launch
            val trimmed = matchId.trim()
            val updated = session.copy(
                matchRef = if (trimmed.isEmpty()) null
                else MatchRef(matchId = trimmed, leagueId = leagueId?.trim()?.takeIf { it.isNotEmpty() }),
            )
            container.sessions.save(updated)
            container.syncQueue.requeue(sessionId)
            container.sessions.refresh()
        }
    }

    fun setLeagueBaseUrl(url: String) = viewModelScope.launch {
        container.settings.setLeagueBaseUrl(url)
    }

    fun setToken(token: String) {
        container.settings.setToken(token)
        viewModelScope.launch {
            // Un token nuevo desbloquea todo lo que se quedó esperando autenticación.
            container.syncQueue.requeueAllNeedingAuth()
            container.sessions.refresh()
            _message.value = if (token.isBlank()) "Token borrado" else "Token guardado"
        }
    }

    fun setShareHealth(share: Boolean) = viewModelScope.launch {
        container.settings.setShareHealth(share)
    }

    fun setShareShotEvents(share: Boolean) = viewModelScope.launch {
        container.settings.setShareShotEvents(share)
    }

    fun setSensitivity(sensitivity: Sensitivity) = viewModelScope.launch {
        container.settings.setSensitivity(sensitivity)
    }

    fun setHand(hand: Hand) = viewModelScope.launch {
        val current = preferences.value.profile
        // El reloj tiene que ir en el brazo de la pala para poder medir, así que al
        // cambiar la mano se mueve también la muñeca.
        container.settings.setProfile(current.copy(hand = hand, watchWrist = hand))
    }

    fun setWatchWrist(wrist: Hand) = viewModelScope.launch {
        container.settings.setProfile(preferences.value.profile.copy(watchWrist = wrist))
    }

    fun setCollectTrainingData(collect: Boolean) = viewModelScope.launch {
        container.settings.setCollectTrainingData(collect)
    }

    fun setPlayerAlias(alias: String) = viewModelScope.launch {
        container.settings.setPlayerAlias(alias)
        _message.value = "Alias guardado"
    }

    fun deleteTrainingData() = viewModelScope.launch {
        container.settings.trainingDataFile.delete()
        _message.value = "Datos de entrenamiento borrados"
    }

    /** Devuelve el fichero para compartirlo, o null si todavía no ha llegado nada. */
    fun trainingDataFile(): java.io.File? =
        container.settings.trainingDataFile.takeIf { it.exists() && it.length() > 0 }

    fun setProfile(profile: PlayerProfile) = viewModelScope.launch {
        container.settings.setProfile(profile)
    }

    fun consumeMessage() {
        _message.value = null
    }
}
