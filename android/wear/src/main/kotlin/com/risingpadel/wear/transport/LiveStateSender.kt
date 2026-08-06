package com.risingpadel.wear.transport

import android.content.Context
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import com.risingpadel.core.sync.LiveScorePayload
import kotlinx.coroutines.tasks.await
import kotlinx.serialization.json.Json

/**
 * Publica el estado en vivo del partido hacia el móvil por el Data Layer.
 *
 * Una sola ruta y no una por sesión: el estado en vivo es **estado completo, no
 * eventos** — cada actualización sustituye del todo a la anterior, así que solo
 * interesa la última. El móvil la republica al servidor con su token, y de ahí la ven
 * los seguidores y la página del espectador.
 *
 * Se deduplica aquí: el Data Layer cobra por entrega, y reenviar un marcador idéntico
 * cada segundo no aporta nada. Solo viaja cuando algo cambió.
 */
class LiveStateSender(context: Context) {

    private val dataClient = Wearable.getDataClient(context)
    private val json = Json { encodeDefaults = true }
    private var lastSent: String? = null

    suspend fun sendIfChanged(payload: LiveScorePayload) {
        val encoded = json.encodeToString(LiveScorePayload.serializer(), payload)
        // El campo updatedAt cambia en cada tick; se compara sin él para no reenviar
        // marcadores idénticos solo porque el reloj avanza.
        val huella = encoded.replace(Regex("\"updatedAt\":\"[^\"]*\""), "")
        if (huella == lastSent) return
        lastSent = huella

        val request = PutDataMapRequest.create(PATH).apply {
            dataMap.putString(KEY_LIVE_JSON, encoded)
        }.asPutDataRequest().setUrgent()
        runCatching { dataClient.putDataItem(request).await() }
    }

    fun reset() {
        lastSent = null
    }

    companion object {
        const val PATH = "/padel/live"
        const val KEY_LIVE_JSON = "live_json"
    }
}
