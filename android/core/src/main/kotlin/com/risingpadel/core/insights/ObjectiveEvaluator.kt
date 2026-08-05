package com.risingpadel.core.insights

import com.risingpadel.core.model.ShotType

/**
 * Resultado de medir un objetivo contra los golpeos de la sesión.
 *
 * @property target el número que pide el objetivo.
 * @property actual lo que el reloj contó.
 * @property met si se cumplió, respetando la dirección (mínimo/máximo).
 */
data class ObjectiveMeasurement(
    val target: Int,
    val actual: Int,
    val met: Boolean,
)

/** Un objetivo medible con su progreso, para pintarlo en vivo. */
data class ObjectiveProgress(
    val text: String,
    val measurement: ObjectiveMeasurement,
) {
    /** Etiqueta corta para la muñeca: "11/15". */
    val label: String get() = "${measurement.actual}/${measurement.target}"
}

/**
 * Mide objetivos de partido escritos en texto libre contra lo que el reloj contó.
 *
 * "Hacer 15 bandejas" es medible: el reloj sabe cuántas bandejas hubo. "Ganar 2 puntos
 * con bandeja" no lo es: el reloj cuenta golpeos, no sabe quién ganó el punto. La regla
 * que gobierna el evaluador es la de los insights — **antes en silencio que inventado**:
 * un objetivo solo se mide si habla de una cantidad de golpeos de un tipo que el reloj
 * detecta y no menciona nada que el reloj no ve (puntos, fallos, colocación, juegos).
 * Todo lo demás devuelve null y se marca a mano, como siempre.
 */
object ObjectiveEvaluator {

    /**
     * Palabras que delatan que el objetivo habla de algo que el reloj no ve. Con una de
     * estas, mejor no medir: "ganar 2 puntos con bandeja" contarían bandejas y mentiría.
     */
    private val FUERA_DE_ALCANCE = listOf(
        "punto", "fallo", "error", "gan", "pierd", "perder", "red", "blanco",
        "juego", "set", "pared", "dejada", "chiquita", "globo", "resto",
        "a la t", "%", "racha", "calent", "molestia", "protest", "comunic",
    )

    /** Palabras de cada tipo de golpe que el reloj sabe contar. */
    private val GOLPES: List<Pair<String, List<ShotType>>> = listOf(
        "bandeja" to listOf(ShotType.BANDEJA),
        "vibora" to listOf(ShotType.VIBORA),
        "remate" to listOf(ShotType.SMASH),
        "smash" to listOf(ShotType.SMASH),
        "saque" to listOf(ShotType.SERVE),
        "derecha" to listOf(ShotType.FOREHAND),
        "reves" to listOf(ShotType.BACKHAND),
        "volea" to listOf(ShotType.FOREHAND_VOLLEY, ShotType.BACKHAND_VOLLEY),
    )

    // Se compara contra el texto ya normalizado (sin tildes).
    private val MAXIMO = listOf("menos de", "maximo", "como mucho", "no mas de")

    private val NUMERO = Regex("\\d+")

    /**
     * Mide un objetivo contra los recuentos de la sesión, o null si no es medible.
     *
     * @param shotsByType recuento por tipo, como lo da la sesión.
     * @param totalShots total de golpeos, para objetivos de "N golpes/golpeos".
     */
    fun evaluate(
        objetivo: String,
        shotsByType: Map<ShotType, Int>,
        totalShots: Int,
    ): ObjectiveMeasurement? {
        val texto = normaliza(objetivo)
        if (FUERA_DE_ALCANCE.any { it in texto }) return null

        val target = NUMERO.find(texto)?.value?.toIntOrNull() ?: return null

        val tipos = GOLPES.firstOrNull { (palabra, _) -> palabra in texto }?.second
        val actual = when {
            tipos != null -> tipos.sumOf { shotsByType[it] ?: 0 }
            "golpe" in texto -> totalShots
            else -> return null
        }

        // Sin señal de tope, un objetivo de cantidad pide llegar: "hacer 15 bandejas"
        // es un mínimo aunque no diga "mínimo".
        val esMaximo = MAXIMO.any { it in texto }
        return ObjectiveMeasurement(
            target = target,
            actual = actual,
            met = if (esMaximo) actual <= target else actual >= target,
        )
    }

    /**
     * Los objetivos que el reloj puede seguir en vivo, con su progreso.
     *
     * Es lo mismo que [evaluate] pero sobre los golpeos que llevas hasta ahora: el reloj
     * lo llama en cada golpe para enseñar "bandejas 11/15". Los no medibles no salen —
     * en una pantalla de 45 mm, una lista de objetivos que no se mueven es ruido.
     */
    fun progress(
        objetivos: List<String>,
        shotsByType: Map<ShotType, Int>,
        totalShots: Int,
    ): List<ObjectiveProgress> = objetivos.mapNotNull { objetivo ->
        evaluate(objetivo, shotsByType, totalShots)?.let {
            ObjectiveProgress(text = objetivo, measurement = it)
        }
    }

    private fun normaliza(texto: String): String =
        texto.lowercase()
            .replace('á', 'a').replace('é', 'e').replace('í', 'i')
            .replace('ó', 'o').replace('ú', 'u')
}
