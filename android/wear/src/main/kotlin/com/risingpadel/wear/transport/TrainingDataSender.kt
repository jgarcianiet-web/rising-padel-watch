package com.risingpadel.wear.transport

import android.content.Context
import com.google.android.gms.wearable.ChannelClient
import com.google.android.gms.wearable.Wearable
import kotlinx.coroutines.tasks.await
import java.io.File

/**
 * Envía el fichero de datos de entrenamiento al móvil.
 *
 * Usa `ChannelClient` y no `DataClient` porque el fichero puede pesar decenas de megas:
 * la señal cruda de miles de golpeos. El Data Layer está pensado para items pequeños y
 * tiene un límite de 100 KB por item; un canal es un flujo y no lo tiene.
 *
 * Es una acción explícita del usuario, nunca automática.
 */
class TrainingDataSender(context: Context) {

    private val channelClient: ChannelClient = Wearable.getChannelClient(context)
    private val nodeClient = Wearable.getNodeClient(context)

    /** @return true si se ha entregado a algún nodo conectado. */
    suspend fun send(file: File): Boolean {
        if (!file.exists() || file.length() == 0L) return false

        val nodes = runCatching { nodeClient.connectedNodes.await() }.getOrNull().orEmpty()
        if (nodes.isEmpty()) return false

        var delivered = false
        for (node in nodes) {
            val channel = runCatching {
                channelClient.openChannel(node.id, PATH).await()
            }.getOrNull() ?: continue

            val sent = runCatching { channelClient.sendFile(channel, file.toUri()).await() }.isSuccess
            runCatching { channelClient.close(channel).await() }
            delivered = delivered || sent
        }
        return delivered
    }

    private fun File.toUri() = android.net.Uri.fromFile(this)

    companion object {
        const val PATH = "/padel/training-data"
    }
}
