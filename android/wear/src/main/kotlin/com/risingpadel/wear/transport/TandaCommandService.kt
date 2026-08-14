package com.risingpadel.wear.transport

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.Wearable
import com.google.android.gms.wearable.WearableListenerService
import com.risingpadel.core.sync.AccionDeTanda
import com.risingpadel.core.sync.EstadoDeTanda
import com.risingpadel.core.sync.OrdenDeTanda
import com.risingpadel.wear.PadelWearApp
import com.risingpadel.wear.R
import com.risingpadel.wear.service.PadelExerciseService
import com.risingpadel.wear.service.SessionStatus
import com.risingpadel.wear.ui.MainActivity
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking

/**
 * Obedece las órdenes de tanda que manda el móvil y contesta con el estado del reloj.
 *
 * Es la mitad del reloj del mando a distancia (ver `OrdenDeTanda`). Va por
 * `MessageClient` a propósito: Play Services arranca este servicio aunque la app del
 * reloj esté cerrada, que es justo el caso normal —el reloj lo lleva otra persona con la
 * pantalla apagada mientras tú miras el móvil— y cada mensaje se entrega una sola vez, sin
 * el riesgo de reentrega que tiene el Data Layer.
 *
 * Conteste lo que conteste, **siempre contesta**: un mando que se queda mudo cuando algo
 * va mal es indistinguible de un mando roto. Si la orden no se puede obedecer, el estado
 * vuelve con el motivo escrito.
 */
class TandaCommandService : WearableListenerService() {

    override fun onMessageReceived(event: MessageEvent) {
        if (event.path != OrdenDeTanda.PATH) return
        val orden = OrdenDeTanda.decode(String(event.data)) ?: return

        // Una orden encolada puede llegar tarde: obedecer "empieza tanda de bandejas"
        // diez minutos después, con el reloj ya en otra muñeca, es peor que no hacer nada.
        // Se contesta igualmente, con el motivo, para que el móvil no parezca colgado.
        val motivo = if (!orden.vigente(System.currentTimeMillis())) {
            "La orden llegó tarde y ya no vale"
        } else {
            runBlocking { obedecer(orden) }
        }

        responder(event.sourceNodeId, motivo)
    }

    private suspend fun obedecer(orden: OrdenDeTanda): String? {
        val container = (application as PadelWearApp).container
        val sesion = container.trainingSession

        return when (orden.accion) {
            AccionDeTanda.ESTADO -> null

            AccionDeTanda.INICIAR -> {
                when {
                    sesion.state.value.recording -> "Ya había una tanda grabando"
                    partidoEnMarcha() ->
                        "Hay un partido en marcha en el reloj; párelo antes"
                    else -> {
                        orden.etiqueta?.let { sesion.setLabel(it) }
                        arrancarTanda()
                    }
                }
            }

            AccionDeTanda.PARAR -> {
                if (!sesion.state.value.recording) {
                    "No había ninguna tanda grabando"
                } else {
                    PadelExerciseService.stop(this)
                    null
                }
            }

            AccionDeTanda.ENVIAR -> {
                when {
                    sesion.state.value.recording -> "Para la tanda antes de enviarla"
                    sesion.state.value.totalStored == 0 -> "No hay nada guardado que enviar"
                    container.trainingDataSender.send(sesion.store.file) -> null
                    else -> "No se pudo enviar el fichero al móvil"
                }
            }
        }
    }

    /**
     * Arranca la tanda, o deja un aviso en el reloj si Android no deja arrancarla sola.
     *
     * Desde Android 12 una app en segundo plano no puede levantar un servicio en primer
     * plano, y este servicio se despierta en segundo plano por definición: el reloj está
     * en la muñeca de otro con la pantalla apagada. Con la app del reloj abierta el
     * arranque va directo; con la app cerrada hay que pasar por un toque del usuario, y
     * eso es una notificación con su intención pendiente — que sí está permitida.
     *
     * @return el motivo si la tanda no arrancó sola, o null si ya está grabando.
     */
    private fun arrancarTanda(): String? = try {
        PadelExerciseService.startTraining(this)
        null
    } catch (e: Exception) {
        avisarParaArrancar()
        "Android no deja arrancarla con la app del reloj cerrada: toca el aviso del reloj"
    }

    /**
     * Un aviso tocable en el reloj que arranca la tanda. El toque del usuario es lo que
     * levanta la restricción de segundo plano.
     */
    private fun avisarParaArrancar() {
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CANAL) == null) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CANAL,
                    getString(R.string.tanda_channel_name),
                    NotificationManager.IMPORTANCE_HIGH,
                )
            )
        }
        val abrir = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java)
                .setAction(MainActivity.ACTION_ARRANCAR_TANDA)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        manager.notify(
            AVISO_ID,
            NotificationCompat.Builder(this, CANAL)
                .setContentTitle(getString(R.string.tanda_aviso_titulo))
                .setContentText(getString(R.string.tanda_aviso_texto))
                .setSmallIcon(R.drawable.ic_padel_notification)
                .setContentIntent(abrir)
                .setAutoCancel(true)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .build()
        )
    }

    /**
     * ¿Está el reloj midiendo un partido normal?
     *
     * Importa porque los dos modos usan los mismos sensores y el mismo servicio en primer
     * plano: arrancar una tanda encima de un partido cortaría el partido a mitad, y el
     * partido es lo que cuenta para el historial.
     */
    private fun partidoEnMarcha(): Boolean {
        val estado = PadelExerciseService.state.value.status
        return estado == SessionStatus.RECORDING || estado == SessionStatus.PREPARING
    }

    private fun responder(nodeId: String, motivo: String?) {
        val container = (application as PadelWearApp).container
        val sesion = container.trainingSession.state.value
        val ajustes = runBlocking { container.settings.preferences.first() }

        val estado = EstadoDeTanda(
            grabando = sesion.recording,
            etiqueta = sesion.label,
            capturadosEnTanda = sesion.capturedInBatch,
            guardadosEnTotal = sesion.totalStored,
            kilobytes = (sesion.storedBytes / 1024).toInt(),
            alias = ajustes.playerAlias,
            nivel = ajustes.playerLevel,
            sensoresPuedenPararse = sensoresPuedenPararse(),
            motivo = motivo,
            descartes = container.trainingSession.descartes,
            segundosDeTanda = if (sesion.recording) sesion.segundos else null,
        )

        Wearable.getMessageClient(this)
            .sendMessage(nodeId, EstadoDeTanda.PATH, estado.encode().toByteArray())
    }

    /**
     * Desde Android 14 el servicio en primer plano de tipo `health` exige el permiso de
     * sensores corporales; sin él la tanda se corta en cuanto se apaga la pantalla. Vale
     * más avisar en el móvil que devolver diez golpes de cincuenta sin decir nada.
     */
    private fun sensoresPuedenPararse(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return false
        return checkSelfPermission(Manifest.permission.BODY_SENSORS) !=
            PackageManager.PERMISSION_GRANTED
    }

    private companion object {
        const val CANAL = "padel_tanda"
        const val AVISO_ID = 1002
    }
}
