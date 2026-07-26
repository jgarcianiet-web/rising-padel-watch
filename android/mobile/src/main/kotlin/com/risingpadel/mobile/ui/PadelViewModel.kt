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
    }

    fun refresh() {
        viewModelScope.launch { container.sessions.refresh() }
    }

    fun syncNow() {
        val app = getApplication<Application>()
        viewModelScope.launch {
            val preferences = preferences.value
            if (container.settings.leagueConfig(preferences.leagueBaseUrl) == null) {
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

    fun setProfile(profile: PlayerProfile) = viewModelScope.launch {
        container.settings.setProfile(profile)
    }

    fun consumeMessage() {
        _message.value = null
    }
}
