package com.risingpadel.core.band

import com.risingpadel.core.model.GolpeVisible

/**
 * Leer los números de una **captura de pantalla** de otra app de pádel.
 *
 * ## Por qué esto existe
 *
 * La Padel Band mide el nivel de cada golpe y cuántos hubo, y su app no tiene
 * exportación ni API: lo que el jugador ve en pantalla es todo lo que hay. Pero es **su**
 * dato, de su pulsera, en su móvil, y el único camino que queda para meterlo en su propia
 * liga es leerlo de la imagen. El iPhone sabe reconocer texto en una foto sin salir del
 * dispositivo (`VNRecognizeTextRequest`); este fichero es lo que pasa de ese montón de
 * líneas de texto a números con nombre.
 *
 * ## La regla que gobierna todo el fichero: **nada se da por bueno en silencio**
 *
 * Un número mal leído de una captura es peor que no tener el dato, porque entra en la
 * liga con la misma pinta que uno medido. Un 3,5 que era un 8,5, un "128 golpes" que era
 * "12,8 golpes/min", y de ahí sale una curva de evolución falsa que nadie va a
 * cuestionar meses después.
 *
 * Así que esto **no devuelve una sesión**: devuelve [CapturaLeida], una lista de
 * candidatos donde cada número viene con **la línea de texto exacta de la que salió**.
 * La pantalla los enseña al lado de la imagen y el jugador confirma o corrige antes de
 * que nada se guarde. Lo que no se deja leer no se rellena con un cero: se queda fuera.
 *
 * ## Y lo que no se puede arreglar leyendo mejor
 *
 * **El nivel de la Band y el del reloj no son la misma escala.** Las dos pueden decir
 * "3,5" sobre el mismo partido y no significar lo mismo. Por eso cada partido guarda de
 * dónde salió su nivel (`LigaMatch.fuente`), y las curvas no mezclan fuentes sin decirlo.
 * Leer la captura con precisión perfecta no haría comparables los dos números.
 */
object LecturaDeCaptura {

    /** Un número leído, con la línea de la que salió para poder enseñarla. */
    data class Dato(
        val valor: Double,
        /** La línea de texto reconocida tal cual. Es lo que se le enseña al jugador. */
        val origen: String,
    )

    /** La nota y/o el recuento de un golpe concreto. */
    data class GolpeLeido(
        val golpe: GolpeVisible,
        val nota: Dato? = null,
        val cantidad: Dato? = null,
    )

    /**
     * Todo lo que se pudo leer de una captura. **Todos los campos son opcionales**: una
     * captura de la pantalla de resumen no trae lo mismo que una del detalle por golpe, y
     * rellenar lo que falta sería inventar.
     */
    data class CapturaLeida(
        val nivelSesion: Dato? = null,
        val totalGolpes: Dato? = null,
        val duracionMin: Dato? = null,
        val pulsoMedio: Dato? = null,
        val pulsoMax: Dato? = null,
        val calorias: Dato? = null,
        val golpes: List<GolpeLeido> = emptyList(),
        /** Las líneas que no se entendieron. Se guardan para poder enseñarlas: si falta
         * algo que el jugador sí ve en su captura, aquí está por qué. */
        val sinEntender: List<String> = emptyList(),
    ) {
        /** Si no se ha podido leer ni un solo número, no hay nada que confirmar. */
        val vacia: Boolean
            get() = nivelSesion == null && totalGolpes == null && duracionMin == null &&
                pulsoMedio == null && pulsoMax == null && calorias == null && golpes.isEmpty()
    }

    // ─── Palabras que buscamos ───
    //
    // Varias por campo y en singular y plural porque no se sabe cómo lo escribe cada app,
    // ni cómo lo escribirá la siguiente versión. Son las etiquetas que de verdad aparecen
    // en una app de pádel; cuando aparezca otra se añade aquí y nada más.

    private val NIVEL = listOf("nivel", "level", "valoracion", "puntuacion", "score")
    private val TOTAL = listOf("golpes", "golpeos", "shots", "impactos", "total")
    private val DURACION = listOf("duracion", "tiempo", "duration")
    private val PULSO_MEDIO = listOf("pulso medio", "fc media", "media ppm", "pulso med")
    private val PULSO_MAX = listOf("pulso max", "fc max", "max ppm", "pulso maximo")
    private val CALORIAS = listOf("calorias", "kcal", "cal")

    /**
     * Lee las líneas que devolvió el reconocedor de texto.
     *
     * Las líneas llegan **en orden de lectura** (arriba abajo) y ese orden importa: en
     * casi todas las apps el rótulo y su número no están en la misma línea, sino uno
     * encima del otro. Por eso se busca el número en la propia línea y, si no está, en la
     * siguiente y en la anterior — y nunca más lejos, porque a dos líneas de distancia ya
     * no se sabe de quién es el número.
     */
    fun leer(lineas: List<String>): CapturaLeida {
        val limpias = lineas.map { it.trim() }.filter { it.isNotEmpty() }
        val normalizadas = limpias.map(::normalizar)
        val usadas = mutableSetOf<Int>()

        fun buscar(claves: List<String>, maximo: Double? = null): Dato? {
            for (i in limpias.indices) {
                if (i in usadas) continue
                val linea = normalizadas[i]
                if (claves.none { linea.contains(it) }) continue
                // En la línea del rótulo, en la de abajo, y en la de arriba. Ese orden:
                // el número suele ir después del rótulo o justo debajo.
                for (j in listOf(i, i + 1, i - 1)) {
                    if (j !in limpias.indices || j in usadas) continue
                    val numero = numeroDe(limpias[j]) ?: continue
                    if (maximo != null && numero > maximo) continue
                    usadas.add(i)
                    usadas.add(j)
                    return Dato(numero, limpias[j])
                }
            }
            return null
        }

        // El orden de búsqueda NO es arbitrario: los rótulos más específicos primero. Si
        // se buscara "pulso" antes que "pulso máximo", la línea del máximo se consumiría
        // como si fuera la media — y una vez consumida ya no se puede recuperar.
        val pulsoMax = buscar(PULSO_MAX, maximo = 250.0)
        val pulsoMedio = buscar(PULSO_MEDIO, maximo = 250.0)
        val calorias = buscar(CALORIAS, maximo = 5_000.0)
        val duracion = buscar(DURACION, maximo = 600.0)
        // El nivel va limitado a 10: en estas apps es 1-7 o 1-10, así que un "3500" en la
        // línea del nivel es que se leyó otra cosa. Mejor no traer el dato que traerlo mal.
        val nivel = buscar(NIVEL, maximo = 10.0)
        val total = buscar(TOTAL, maximo = 2_000.0)

        val golpes = leerGolpes(limpias, normalizadas, usadas)

        return CapturaLeida(
            nivelSesion = nivel,
            totalGolpes = total,
            duracionMin = duracion,
            pulsoMedio = pulsoMedio,
            pulsoMax = pulsoMax,
            calorias = calorias,
            golpes = golpes,
            sinEntender = limpias.indices.filter { it !in usadas }.map { limpias[it] },
        )
    }

    /**
     * Las líneas que nombran un golpe del repertorio, con los números que las acompañan.
     *
     * Cuando una línea trae **dos** números —"Bandeja 3,5 · 24"— se interpreta que el
     * primero es la nota y el segundo el recuento, porque una nota lleva decimales y un
     * recuento no. Si solo hay uno, decide la forma: con decimales es nota; entero es
     * recuento. Es una heurística y por eso el número viaja con su línea: si acierta, el
     * jugador confirma de un toque, y si no, lo ve y lo corrige.
     */
    private fun leerGolpes(
        limpias: List<String>,
        normalizadas: List<String>,
        usadas: MutableSet<Int>,
    ): List<GolpeLeido> {
        val encontrados = mutableMapOf<GolpeVisible, GolpeLeido>()
        for (i in limpias.indices) {
            if (i in usadas) continue
            val golpe = golpeDe(normalizadas[i]) ?: continue
            // La propia línea y la de abajo: el nombre del golpe y su número a veces van
            // en dos líneas, como los rótulos.
            val numeros = numerosDe(limpias[i]).ifEmpty {
                if (i + 1 in limpias.indices && i + 1 !in usadas) {
                    numerosDe(limpias[i + 1]).also { if (it.isNotEmpty()) usadas.add(i + 1) }
                } else {
                    emptyList()
                }
            }
            if (numeros.isEmpty()) continue
            usadas.add(i)

            val nota: Dato?
            val cantidad: Dato?
            if (numeros.size >= 2) {
                nota = Dato(numeros[0], limpias[i])
                cantidad = Dato(numeros[1], limpias[i])
            } else if (tieneDecimales(numeros[0])) {
                nota = Dato(numeros[0], limpias[i])
                cantidad = null
            } else {
                nota = null
                cantidad = Dato(numeros[0], limpias[i])
            }
            // El primero gana: una captura larga puede repetir el nombre del golpe en una
            // leyenda o en un pie, y lo de arriba es lo que el jugador está mirando.
            encontrados.putIfAbsent(golpe, GolpeLeido(golpe, nota, cantidad))
        }
        // En el orden del repertorio y no en el de la captura: así la pantalla de
        // confirmación se lee siempre igual, venga la captura como venga.
        return GolpeVisible.entries.mapNotNull { encontrados[it] }
    }

    /** Un nivel plausible tiene decimales; un recuento de golpes, no. */
    private fun tieneDecimales(valor: Double): Boolean = valor != valor.toLong().toDouble()

    /**
     * Cómo puede estar escrito cada golpe, **todo en una lista y ordenado de más largo a
     * más corto**.
     *
     * Las dos cosas son necesarias y la segunda no es evidente. "Volea de revés" contiene
     * "revés", así que el patrón largo tiene que probarse antes — pero además la variante
     * sin preposición ("volea revés", que es como lo escribe media aplicación) tiene que
     * competir **en la misma pasada**: si se deja para un segundo intento, "volea revés"
     * ya habrá casado con "revés" y el jugador verá su volea de revés contada como revés,
     * que es otro golpe. Pasó, y lo pilló un test.
     */
    private val PATRONES: List<Pair<String, GolpeVisible>> =
        GolpeVisible.entries.flatMap { golpe ->
            val completo = normalizar(golpe.etiqueta)
            val sinPreposicion = completo.replace(" de ", " ")
            if (sinPreposicion == completo) {
                listOf(completo to golpe)
            } else {
                listOf(completo to golpe, sinPreposicion to golpe)
            }
        }.sortedByDescending { it.first.length }

    /** El golpe del repertorio que nombra esta línea, o null. */
    internal fun golpeDe(lineaNormalizada: String): GolpeVisible? =
        PATRONES.firstOrNull { lineaNormalizada.contains(it.first) }?.second

    /** Minúsculas, sin acentos y con un solo espacio: así "Revés" y "REVES" son lo mismo. */
    internal fun normalizar(texto: String): String {
        val sb = StringBuilder(texto.length)
        for (c in texto.lowercase()) {
            sb.append(
                when (c) {
                    'á', 'à', 'ä', 'â' -> 'a'
                    'é', 'è', 'ë', 'ê' -> 'e'
                    'í', 'ì', 'ï', 'î' -> 'i'
                    'ó', 'ò', 'ö', 'ô' -> 'o'
                    'ú', 'ù', 'ü', 'û' -> 'u'
                    'ñ' -> 'n'
                    else -> c
                }
            )
        }
        return sb.toString().replace(Regex("\\s+"), " ").trim()
    }

    /** El primer número de una línea, o null. */
    internal fun numeroDe(linea: String): Double? = numerosDe(linea).firstOrNull()

    /**
     * Todos los números de una línea, en orden.
     *
     * **La coma es decimal**, que es como lo escribe una app en español: "3,5" es tres y
     * medio y no dos números. Y un "3,5/7" da solo el 3,5 — el 7 es el máximo de la
     * escala, no un dato del jugador; por eso se descarta lo que vaya detrás de una barra.
     */
    internal fun numerosDe(linea: String): List<Double> {
        val sinEscala = linea.replace(Regex("/\\s*\\d+([.,]\\d+)?"), "")
        return Regex("-?\\d+(?:[.,]\\d+)?")
            .findAll(sinEscala)
            .mapNotNull { it.value.replace(',', '.').toDoubleOrNull() }
            .filter { it >= 0 }
            .toList()
    }
}
