package com.risingpadel.wear.transport

import android.content.Context
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import com.risingpadel.core.model.PadelSession
import kotlinx.coroutines.tasks.await
import kotlinx.serialization.json.Json

/**
 * Envía la sesión terminada al móvil por el Data Layer.
 *
 * Se usa `DataClient` y no `MessageClient` porque los items de datos se **encolan**: si
 * el móvil está apagado o fuera de alcance al acabar el partido, Google Play Services
 * entrega la sesión cuando vuelva a haber conexión. Un mensaje se perdería.
 *
 * La ruta lleva el `sessionId`, así que dos sesiones distintas no se pisan y reenviar la
 * misma sesión es idempotente.
 */
class PhoneSessionSender(context: Context) {

    private val dataClient = Wearable.getDataClient(context)
    private val json = Json { encodeDefaults = true; ignoreUnknownKeys = true }

    suspend fun send(session: PadelSession) {
        val request = PutDataMapRequest.create("$PATH_PREFIX/${session.sessionId}").apply {
            dataMap.putString(KEY_SESSION_JSON, json.encodeToString(PadelSession.serializer(), session))
            // El Data Layer descarta un item idéntico al anterior; el timestamp fuerza
            // la entrega cuando se reenvía una sesión ya conocida.
            dataMap.putLong(KEY_SENT_AT, session.endedAtEpochMs)
        }.asPutDataRequest().setUrgent()

        dataClient.putDataItem(request).await()
    }

    companion object {
        const val PATH_PREFIX = "/padel/session"
        const val KEY_SESSION_JSON = "session_json"
        const val KEY_SENT_AT = "sent_at"
    }
}
