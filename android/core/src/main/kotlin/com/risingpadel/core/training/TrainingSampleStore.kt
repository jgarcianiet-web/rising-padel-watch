package com.risingpadel.core.training

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
