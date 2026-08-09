package com.risingpadel.mobile.sync

import android.content.Context
import android.util.Log
import com.google.android.gms.wearable.Wearable
import com.risingpadel.core.sync.AccionDeTanda
import com.risingpadel.core.sync.EstadoDeTanda
import com.risingpadel.core.sync.OrdenDeTanda
import com.risingpadel.core.model.ShotType
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.tasks.await

/** Si el móvil puede mandar órdenes al reloj ahora mismo, y por qué no si no puede. */
enum class ConexionDelMando { BUSCANDO, CONECTADO, SIN_RELOJ }

/**
 * El lado del móvil del mando a distancia de tandas.
 *
 * Manda la orden a **todos** los nodos conectados y no solo al primero: un móvil puede
 * tener emparejados un reloj y un emulador, y adivinar cuál es el bueno saldría mal justo
 * el día que hay dos. El que no esté en modo tanda contesta que no había nada grabando,
 * que es información y no un error.
 *
 * El estado no vuelve por aquí: vuelve por su propio mensaje, que recoge
 * [TandaEstadoListenerService]. Así el móvil se entera también de lo que pasa en el reloj
 * sin haber preguntado — por ejemplo, si alguien para la tanda desde la muñeca.
 */
class TandaRemote(private val context: Context) {

    private val messageClient = Wearable.getMessageClient(context)
    private val nodeClient = Wearable.getNodeClient(context)

    private val _conexion = MutableStateFlow(ConexionDelMando.BUSCANDO)
    val conexion: StateFlow<ConexionDelMando> = _conexion.asStateFlow()

    /**
     * @return true si la orden llegó a algún reloj. False significa "no hay reloj a
     *   tiro", no "el reloj dijo que no": eso último viene en el estado, con su motivo.
     */
    suspend fun ordenar(accion: AccionDeTanda, etiqueta: ShotType? = null): Boolean {
        val orden = OrdenDeTanda(
            accion = accion,
            etiqueta = etiqueta,
            creadoEpochMs = System.currentTimeMillis(),
        )
        val nodos = runCatching { nodeClient.connectedNodes.await() }.getOrNull().orEmpty()
        if (nodos.isEmpty()) {
            _conexion.value = ConexionDelMando.SIN_RELOJ
            return false
        }

        var entregada = false
        for (nodo in nodos) {
            val ok = runCatching {
                messageClient.sendMessage(nodo.id, OrdenDeTanda.PATH, orden.encode().toByteArray())
                    .await()
            }.onFailure {
                Log.i(TAG, "Orden no entregada a ${nodo.displayName}: ${it.message}")
            }.isSuccess
            entregada = entregada || ok
        }
        _conexion.value =
            if (entregada) ConexionDelMando.CONECTADO else ConexionDelMando.SIN_RELOJ
        return entregada
    }

    private companion object {
        const val TAG = "TandaRemote"
    }
}

/**
 * El buzón donde aterriza el estado que devuelve el reloj.
 *
 * Es un objeto compartido y no un callback porque quien recibe el mensaje es un servicio
 * del sistema, que no conoce ni a la pantalla ni al ViewModel: Play Services lo arranca
 * cuando le llega el mensaje y lo mata al volver.
 */
object BuzonDeTanda {
    private val _estado = MutableStateFlow<EstadoDeTanda?>(null)
    val estado: StateFlow<EstadoDeTanda?> = _estado.asStateFlow()

    fun publicar(estado: EstadoDeTanda) {
        _estado.value = estado
    }
}
