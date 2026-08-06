package com.risingpadel.mobile.sync

import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.WearableListenerService
import com.risingpadel.mobile.data.ComunidadApi
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * Recibe el estado en vivo del reloj Wear y lo republica al servidor.
 *
 * El reloj no tiene red propia garantizada; el móvil sí, y además tiene el token de la
 * cuenta. Es el mismo papel que hace el iPhone con el Apple Watch: el reloj emite, el
 * móvil firma y publica. Sin cuenta de comunidad no se publica nada — el marcador se
 * queda en la muñeca.
 *
 * Fuego y olvido, sin cola: el estado en vivo caduca en segundos y la siguiente
 * actualización corrige sola cualquier fallo puntual de red.
 */
class LiveStateListenerService : WearableListenerService() {

    private val json = Json { ignoreUnknownKeys = true }

    override fun onDataChanged(dataEvents: DataEventBuffer) {
        val api = ComunidadApi(applicationContext) { ComunidadApi.SERVIDOR_OFICIAL }

        runBlocking {
            dataEvents.forEach { event ->
                if (event.type != DataEvent.TYPE_CHANGED) return@forEach
                if (event.dataItem.uri.path != PATH) return@forEach

                val estadoJson = DataMapItem.fromDataItem(event.dataItem)
                    .dataMap
                    .getString(KEY_LIVE_JSON)
                    ?: return@forEach

                val sessionId = runCatching {
                    json.parseToJsonElement(estadoJson)
                        .jsonObject["sessionId"]?.jsonPrimitive?.content
                }.getOrNull() ?: return@forEach

                api.publicarEnVivo(sessionId, estadoJson)
            }
        }
        dataEvents.release()
    }

    private companion object {
        const val PATH = "/padel/live"
        const val KEY_LIVE_JSON = "live_json"
    }
}
