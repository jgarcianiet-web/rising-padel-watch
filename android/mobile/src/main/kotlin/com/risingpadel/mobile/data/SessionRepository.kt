package com.risingpadel.mobile.data

import com.risingpadel.core.model.PadelSession
import com.risingpadel.core.storage.SessionStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext

/**
 * Historial de sesiones. Envuelve el [SessionStore] del core con un [StateFlow] para
 * que la UI se refresque sola cuando el reloj entrega una sesión nueva o la cola de
 * sincronización cambia un estado.
 */
class SessionRepository(private val store: SessionStore) {

    private val _sessions = MutableStateFlow<List<PadelSession>>(emptyList())
    val sessions: StateFlow<List<PadelSession>> = _sessions.asStateFlow()

    suspend fun refresh() = withContext(Dispatchers.IO) {
        _sessions.value = store.all()
    }

    suspend fun save(session: PadelSession) = withContext(Dispatchers.IO) {
        store.upsert(session)
        _sessions.value = store.all()
    }

    suspend fun delete(sessionId: String) = withContext(Dispatchers.IO) {
        store.delete(sessionId)
        _sessions.value = store.all()
    }

    suspend fun get(sessionId: String): PadelSession? = withContext(Dispatchers.IO) {
        store.get(sessionId)
    }
}
