package com.risingpadel.core.training

import com.risingpadel.core.model.ShotType
import kotlinx.serialization.json.Json
import java.io.File

/**
 * Almacén de muestras de entrenamiento en JSONL: una muestra por línea.
 *
 * JSONL y no un JSON único porque grabar es **añadir**: cada golpeo se escribe en cuanto
 * está listo, sin releer ni reescribir lo anterior. Si el reloj se queda sin batería a
 * mitad de una tanda, se pierde como mucho la última línea; con un array JSON se
 * perdería el fichero entero.
 *
 * También es el formato que espera `tools/train_classifier.py`, y el que digieren pandas
 * y jq sin ceremonia.
 */
class TrainingSampleStore(
    val file: File,
    private val json: Json = defaultJson,
) {
    init {
        file.parentFile?.mkdirs()
    }

    val exists: Boolean get() = file.exists()

    val sizeBytes: Long get() = if (file.exists()) file.length() else 0L

    fun append(sample: TrainingSample) {
        file.appendText(json.encodeToString(TrainingSample.serializer(), sample) + "\n")
    }

    fun appendAll(samples: List<TrainingSample>) {
        if (samples.isEmpty()) return
        val text = samples.joinToString("") {
            json.encodeToString(TrainingSample.serializer(), it) + "\n"
        }
        file.appendText(text)
    }

    /**
     * Añade una tanda cruda (formato 2) al mismo fichero.
     *
     * Mismo fichero a propósito: las tandas viejas (una línea por golpe) y las nuevas
     * (una línea por tanda) conviven, se exportan juntas y se suben juntas. Quien lee
     * distingue el formato por línea.
     */
    fun appendTanda(tanda: TandaCruda) {
        file.appendText(json.encodeToString(TandaCruda.serializer(), tanda) + "\n")
    }

    /**
     * Los pares (etiqueta, rasgos del golpe) de todo el fichero, vengan del formato que
     * vengan. Es lo que comen la calibración y el panel de precisión.
     */
    fun paresEtiquetados(): List<Pair<ShotType, com.risingpadel.core.model.ShotFeatures>> {
        if (!file.exists()) return emptyList()
        return file.useLines { lines ->
            lines.filter { it.isNotBlank() }.flatMap { linea ->
                // Primero el formato nuevo; si no cuela, el viejo. Una línea corrupta
                // no tira el fichero.
                runCatching { json.decodeFromString(TandaCruda.serializer(), linea) }
                    .getOrNull()
                    ?.takeIf { it.formato >= 2 }
                    ?.let { tanda -> return@flatMap tanda.golpes.map { tanda.label to it.features }.asSequence() }
                runCatching { json.decodeFromString(TrainingSample.serializer(), linea) }
                    .getOrNull()
                    ?.let { sequenceOf(it.label to it.heuristicFeatures) }
                    ?: emptySequence()
            }.toList()
        }
    }

    /** Cuenta líneas sin parsear: es lo que se enseña en la UI mientras se graba. */
    fun count(): Int {
        if (!file.exists()) return 0
        return file.useLines { lines -> lines.count { it.isNotBlank() } }
    }

    /** Una línea corrupta se salta; el resto del fichero sigue sirviendo. */
    fun readAll(): List<TrainingSample> {
        if (!file.exists()) return emptyList()
        return file.useLines { lines ->
            lines.filter { it.isNotBlank() }
                .mapNotNull {
                    runCatching { json.decodeFromString(TrainingSample.serializer(), it) }.getOrNull()
                }
                .toList()
        }
    }

    /** Cuántas muestras hay de cada tipo. Sirve para saber qué falta por grabar. */
    fun countsByLabel(): Map<String, Int> =
        readAll().groupingBy { it.label.wireName }.eachCount()

    fun clear() {
        file.delete()
    }

    companion object {
        val defaultJson = Json {
            ignoreUnknownKeys = true
            encodeDefaults = true
        }
    }
}
