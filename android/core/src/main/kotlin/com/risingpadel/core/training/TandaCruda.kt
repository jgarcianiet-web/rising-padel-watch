package com.risingpadel.core.training

import com.risingpadel.core.detection.DescartesDelDetector
import com.risingpadel.core.model.Hand
import com.risingpadel.core.model.Platform
import com.risingpadel.core.model.ShotFeatures
import com.risingpadel.core.model.ShotType
import kotlinx.serialization.Serializable

/**
 * Un golpe que el detector creyó ver durante la tanda, como metadato.
 *
 * Es información, no puerta: la tanda se graba entera aunque el detector no vea ni uno.
 * Sus rasgos alimentan la calibración y el panel de precisión igual que antes.
 */
@Serializable
data class GolpeDeTanda(
    /** Milisegundos desde el arranque de la tanda. */
    val offsetMs: Long,
    val tipo: ShotType,
    val confidence: Float,
    val features: ShotFeatures,
)

/**
 * Una tanda de entrenamiento grabada **entera y en crudo**: del "grabar" al "parar",
 * toda la señal, con una sola etiqueta.
 *
 * Sustituye a la captura por ventanas y es la respuesta a un fallo de diseño que salió
 * en pista: antes solo se guardaba una ventana alrededor de cada impacto que el detector
 * encontraba, así que si el detector no veía impactos —golpe suave, umbral alto, probar
 * sin bola— la tanda entera se quedaba en **cero** sin explicación posible. Grabar en
 * crudo lo invierte: el tiempo y los bytes siempre avanzan, no hay forma de "no recoger
 * nada", y los golpes que el detector se dejó siguen estando en la señal para
 * segmentarlos después con calma.
 *
 * Y arregla otra cosa de paso: un golpe perdido ya no descoloca las etiquetas de los
 * demás (pasó con una tanda real: dos saques acabaron etiquetados como derechas porque
 * el reloj se dejó golpes y corrió la cuenta). Aquí la etiqueta es del bloque entero.
 */
@Serializable
data class TandaCruda(
    val tandaId: String,
    /** El tipo de golpe de la tanda entera. Se fija ANTES de empezar a pegar. */
    val label: ShotType,
    val playerAlias: String = "anon",
    val playerLevel: Int? = null,
    val hand: Hand = Hand.RIGHT,
    val watchWrist: Hand = Hand.RIGHT,
    val platform: Platform,
    val device: String = "",
    val appVersion: String = "",
    val startedAtEpochMs: Long,
    val sampleRateHz: Int,
    /** Milisegundos desde el arranque, una entrada por muestra. */
    val offsetsMs: List<Long>,
    /** Cada muestra como [x, y, z], alineada con [offsetsMs]. */
    val accel: List<List<Float>>,
    val gyro: List<List<Float>>,
    val gravity: List<List<Float>>,
    /** Lo que el detector creyó ver, como metadato. Vacío no invalida nada. */
    val golpes: List<GolpeDeTanda> = emptyList(),
    val descartes: DescartesDelDetector? = null,
    /** Versión del formato: 2 = tanda cruda. Las líneas viejas (por golpe) no lo llevan. */
    val formato: Int = 2,
) {
    val muestras: Int get() = offsetsMs.size

    val duracionSegundos: Int
        get() = if (offsetsMs.isEmpty()) 0 else (offsetsMs.last() / 1000).toInt()
}
