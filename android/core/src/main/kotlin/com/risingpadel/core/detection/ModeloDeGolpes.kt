package com.risingpadel.core.detection

import com.risingpadel.core.model.ShotFeatures
import com.risingpadel.core.model.ShotType

/**
 * Un bosque de decisión pequeño, escrito como tablas de números.
 *
 * Es el sustituto de la heurística cuando haya datos para entrenarlo. Se guarda como
 * **código generado** y no como Core ML o TFLite, y esa es la decisión de diseño que más
 * importa aquí:
 *
 * - Con dos runtimes distintos, watchOS y Wear pueden dar respuestas distintas al mismo
 *   golpe, y eso es imposible de depurar sin los dos relojes delante. Con tablas, la
 *   aritmética son cuatro líneas por lenguaje y los números son literalmente los mismos.
 * - Se prueba en Kotlin como todo lo demás, con las tandas de pista de fixture.
 * - No añade dependencias ni peso de runtime a dos apps que ya pesan.
 *
 * **Come exactamente [ShotFeatures]**, los mismos nueve rasgos que ya calcula el reloj
 * para cada golpe. Podría comer la ventana cruda y sacar más señal, pero entonces habría
 * que reimplementar la extracción de rasgos en Kotlin, en Swift y en Python **sin poder
 * comprobar que las tres dan lo mismo** — y una discrepancia ahí no se ve, solo empeora
 * los números sin decir por qué. Se empieza por lo que no puede desincronizarse.
 */
data class ModeloDeGolpes(
    /** Los tipos que el modelo sabe decir, en el orden en que se entrenó. */
    val clases: List<ShotType>,
    /** Índice del nodo raíz de cada árbol dentro de las tablas. */
    val raices: IntArray,
    /** Rasgo por el que corta cada nodo, o -1 si es una hoja. */
    val rasgo: IntArray,
    /** Umbral del corte: se va a la izquierda si el valor es <= umbral. */
    val umbral: FloatArray,
    val izquierda: IntArray,
    val derecha: IntArray,
    /** Clase que vota cada hoja (índice en [clases]). -1 en los nodos internos. */
    val hoja: IntArray,
    /** Cuántos golpeos etiquetados lo sostienen, para poder enseñarlo. */
    val muestras: Int,
    /** Acierto dejando fuera a un jugador entero, 0 a 1. La única cifra que predice. */
    val aciertoFuera: Float,
) {
    val arboles: Int get() = raices.size

    /**
     * El voto del bosque: la clase más votada y qué fracción de árboles la votó.
     *
     * La confianza es la fracción de votos y no una probabilidad calibrada, a propósito:
     * es lo que se puede explicar en una frase ("18 de 25 árboles dicen bandeja") y lo
     * que se puede comparar con el `minConfidence` que ya usa la heurística.
     */
    fun clasificar(features: ShotFeatures): Classification? {
        if (clases.isEmpty() || raices.isEmpty()) return null
        val valores = vectorDe(features)
        val votos = IntArray(clases.size)
        for (raiz in raices) {
            var nodo = raiz
            while (rasgo[nodo] >= 0) {
                nodo = if (valores[rasgo[nodo]] <= umbral[nodo]) izquierda[nodo] else derecha[nodo]
            }
            val clase = hoja[nodo]
            if (clase in votos.indices) votos[clase]++
        }
        var mejor = 0
        for (i in votos.indices) if (votos[i] > votos[mejor]) mejor = i
        if (votos[mejor] == 0) return null
        return Classification(clases[mejor], votos[mejor].toFloat() / raices.size)
    }

    companion object {
        /**
         * El orden de los rasgos. Es un contrato con `tools/exportar_modelo.py`: si
         * cambia aquí y no allí, el modelo lee los números cambiados de sitio y falla en
         * silencio — que es la peor forma de fallar. Por eso hay un test que lo fija.
         */
        val RASGOS = listOf(
            "sweptAngleDeg",
            "peakGyroRadS",
            "elevationDeg",
            "axialRotationRadS",
            "swingDurationMs",
            "peakElevationDeg",
            "prepElevationDeg",
            "peakAxialRotationRadS",
            "elevationDropDeg",
        )

        /**
         * Los nulos se rellenan con 0 y no se descartan: un golpe sin elevación de
         * preparación es un golpe que hay que clasificar igual, y el árbol aprende a
         * tratar el 0 como "no se midió" porque en el entrenamiento le llega igual.
         */
        fun vectorDe(features: ShotFeatures): FloatArray = floatArrayOf(
            features.sweptAngleDeg,
            features.peakGyroRadS,
            features.elevationDeg,
            features.axialRotationRadS,
            features.swingDurationMs.toFloat(),
            features.peakElevationDeg,
            features.prepElevationDeg ?: 0f,
            features.peakAxialRotationRadS ?: 0f,
            features.elevationDropDeg ?: 0f,
        )
    }

    // Las tablas son arrays y un data class compara arrays por identidad. Se escriben a
    // mano para que dos modelos con los mismos números sean el mismo modelo.
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is ModeloDeGolpes) return false
        return clases == other.clases && raices.contentEquals(other.raices) &&
            rasgo.contentEquals(other.rasgo) && umbral.contentEquals(other.umbral) &&
            izquierda.contentEquals(other.izquierda) && derecha.contentEquals(other.derecha) &&
            hoja.contentEquals(other.hoja) && muestras == other.muestras
    }

    override fun hashCode(): Int = clases.hashCode() * 31 + raices.contentHashCode()
}
