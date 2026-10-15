package com.risingpadel.core.band

import com.risingpadel.core.model.GolpeVisible
import kotlin.math.abs

/**
 * Leer los números de una **captura de pantalla** de otra app de pádel.
 *
 * ## Por qué esto existe
 *
 * La Padel Band mide el nivel de cada golpe y cuántos hubo, y su app no tiene exportación
 * ni API: lo que el jugador ve en pantalla es todo lo que hay. Pero es **su** dato, de su
 * pulsera, en su móvil, y el único camino que queda para meterlo en su propia liga es
 * leerlo de la imagen. El iPhone sabe reconocer texto en una foto sin salir del
 * dispositivo; este fichero es lo que pasa de ese montón de trozos de texto a números con
 * nombre.
 *
 * ## La regla que gobierna todo el fichero: **nada se da por bueno en silencio**
 *
 * Un número mal leído de una captura es peor que no tener el dato, porque entra en la liga
 * con la misma pinta que uno medido. Un 3,5 que era un 8,5 produce una curva de evolución
 * falsa que nadie va a cuestionar meses después.
 *
 * Así que esto **no devuelve una sesión**: devuelve [CapturaLeida], candidatos donde cada
 * número viene con **el texto exacto del que salió**. La pantalla los enseña al lado de la
 * imagen y el jugador confirma o corrige antes de que nada se guarde. Lo que no se deja
 * leer no se rellena con un cero: se queda fuera.
 *
 * ## Por qué hace falta saber DÓNDE está cada texto
 *
 * La primera versión trabajaba con una lista de líneas, y contra las capturas de verdad no
 * valía. Una app de móvil no apila rótulo y valor en una columna: los pone en rejilla.
 *
 * - `Num. golpes` y `Calidad` van **uno al lado del otro**, y debajo, en otra fila, `11` y
 *   `2.99`. Leído como líneas sueltas no hay forma de saber cuál es de cuál.
 * - En la tarjeta de actividad el número va **encima** de su rótulo: `898` y debajo
 *   `K Cal`.
 * - En el radar de calidad pasa lo mismo: `3.61` encima de `VOLEA`.
 *
 * Por eso la entrada es [Trozo], con su posición. Los trozos se agrupan en filas y el
 * valor de un rótulo se busca **a su derecha en la misma fila, debajo en su columna, o
 * encima en su columna** — en ese orden. Sigue existiendo [leer] con líneas sueltas para
 * una captura de una sola columna.
 *
 * ## Y lo que no se puede arreglar leyendo mejor
 *
 * **El nivel de la Band y el del reloj no son la misma escala**, aunque los dos vayan de
 * 1 a 7. Por eso cada partido guarda de dónde salió su nivel (`LigaMatch.fuente`) y las
 * curvas no mezclan fuentes. Leer la captura con precisión perfecta no haría comparables
 * los dos números.
 */
object LecturaDeCaptura {

    /**
     * Un trozo de texto reconocido, con dónde está.
     *
     * [x] e [y] son el centro del trozo en coordenadas normalizadas 0-1 de la imagen, con
     * **el origen arriba a la izquierda**: `y = 0` es el borde de arriba. Ojo al portarlo,
     * porque Vision las da con el origen abajo y hay que voltearlas una sola vez, al
     * reconocer — tener dos convenios de `y` dando vueltas es el fallo que deja la lectura
     * del revés y nadie sabe dónde.
     */
    data class Trozo(val texto: String, val x: Double, val y: Double)

    /** Un número leído, con el texto del que salió para poder enseñarlo. */
    data class Dato(val valor: Double, val origen: String)

    /**
     * Un golpe de la captura.
     *
     * El [nombre] es lo que ponía en pantalla y es lo que se guarda, porque la liga guarda
     * los golpes **por nombre** y no por enum. El [golpe] es la correspondencia con
     * nuestro repertorio cuando la hay, y sirve para ordenar y para poder comparar con lo
     * que mide el reloj.
     *
     * [golpe] es null cuando la captura da el golpe **sin lado**: la pantalla de volumen
     * dice "Volea 175" sin separar derecha de revés, y partir ese 175 por la mitad sería
     * inventarse dos números. Se guarda como "Volea" y ya está.
     */
    data class GolpeLeido(
        val nombre: String,
        val golpe: GolpeVisible?,
        val nota: Dato? = null,
        val cantidad: Dato? = null,
    )

    /**
     * Todo lo que se pudo leer. **Todos los campos son opcionales**: la pantalla de
     * resumen no trae lo mismo que la de un golpe, y rellenar lo que falta sería inventar.
     */
    data class CapturaLeida(
        val nivelSesion: Dato? = null,
        /** La "Calidad Media Jugador" de la gráfica de progreso. */
        val mediaDelJugador: Dato? = null,
        val totalGolpes: Dato? = null,
        val duracionMin: Dato? = null,
        val pulsoMedio: Dato? = null,
        val pulsoMax: Dato? = null,
        val calorias: Dato? = null,
        val pasos: Dato? = null,
        /** El golpe que la app destaca como mejor ("Mejor golpe: REMATE"). */
        val mejorGolpe: String? = null,
        /** El lado de la pista en el que jugó, si la captura lo dice. */
        val posicion: String? = null,
        val golpes: List<GolpeLeido> = emptyList(),
        /** Los textos que no se entendieron, para poder enseñarlos: si falta un dato que
         * el jugador sí ve en su captura, aquí está por qué. */
        val sinEntender: List<String> = emptyList(),
    ) {
        val vacia: Boolean
            get() = nivelSesion == null && mediaDelJugador == null && totalGolpes == null &&
                duracionMin == null && pulsoMedio == null && pulsoMax == null &&
                calorias == null && pasos == null && mejorGolpe == null && golpes.isEmpty()
    }

    // ─── Rótulos ───
    //
    // Los de la Padel Band están sacados de capturas reales (oct 2026); los demás son
    // variantes razonables de otras apps. Cuando aparezca una nueva se añade aquí.

    private val NIVEL = listOf("nivel sesion", "nivel de la sesion", "nivel", "level")
    private val MEDIA_JUGADOR = listOf("calidad media jugador", "media jugador")
    /**
     * El total de la sesión. Incluye "golpes" a secas porque la tarjeta de actividad lo
     * rotula así, pero **excluyendo** el "Num. golpes" de la tarjeta de cada golpe: sin
     * esa exclusión, el recuento de las bandejas entraría como el total del partido.
     */
    private val TOTAL = listOf("golpes totales", "total golpes", "golpeos", "shots", "golpes")
    private val DURACION = listOf("tiempo", "duracion", "duration")
    private val PULSO_MEDIO = listOf("pulso medio", "fc media", "media ppm", "pulso med")
    private val PULSO_MAX = listOf("pulso max", "fc max", "max ppm", "pulso maximo")
    private val CALORIAS = listOf("k cal", "kcal", "calorias")
    private val PASOS = listOf("pasos", "steps")
    private val MEJOR_GOLPE = listOf("mejor golpe")
    /** En la tarjeta de un golpe concreto. */
    private val NUM_GOLPES = listOf("num golpes", "numero de golpes")
    private val CALIDAD = listOf("calidad")

    /** Dos filas se consideran la misma si sus centros caen dentro de esto. */
    private const val TOLERANCIA_FILA = 0.012

    /** Cuánto se puede desviar en horizontal un valor de su rótulo, en otra fila. */
    private const val TOLERANCIA_COLUMNA = 0.30

    /** Lee una captura de una sola columna, sin posiciones. Para tests y casos simples. */
    fun leer(lineas: List<String>): CapturaLeida =
        leerTrozos(lineas.mapIndexed { i, texto -> Trozo(texto, 0.0, i.toDouble()) })

    /** Lee los trozos de texto reconocidos, con sus posiciones. */
    fun leerTrozos(trozos: List<Trozo>): CapturaLeida {
        val limpios = trozos
            .map { it.copy(texto = it.texto.trim()) }
            .filter { it.texto.isNotEmpty() }
            .sortedWith(compareBy({ it.y }, { it.x }))
        if (limpios.isEmpty()) return CapturaLeida()

        val normalizados = limpios.map { normalizar(it.texto) }
        val filas = agruparEnFilas(limpios)
        val filaDe = IntArray(limpios.size)
        for ((indiceFila, fila) in filas.withIndex()) for (i in fila) filaDe[i] = indiceFila
        val usados = mutableSetOf<Int>()

        val contexto = Contexto(limpios, normalizados, filas, filaDe, usados)

        // El orden NO es arbitrario: los rótulos más específicos primero. Buscando
        // "calidad" antes que "calidad media jugador", la línea de la media se consume
        // como si fuera la calidad de un golpe y ya no se puede recuperar. Igual con
        // "pulso" y "pulso máximo", y con "nivel sesión" y "nivel".
        val media = contexto.buscar(MEDIA_JUGADOR, maximo = 10.0)
        val nivel = contexto.buscar(NIVEL, maximo = 10.0)
        val pulsoMax = contexto.buscar(PULSO_MAX, maximo = 250.0)
        val pulsoMedio = contexto.buscar(PULSO_MEDIO, maximo = 250.0)
        val calorias = contexto.buscar(CALORIAS, maximo = 10_000.0)
        val pasos = contexto.buscar(PASOS, maximo = 100_000.0)
        val duracion = contexto.buscar(DURACION, maximo = 600.0, enMinutos = true)
        val total = contexto.buscar(TOTAL, maximo = 5_000.0, excluyendo = NUM_GOLPES)
        val mejorGolpe = contexto.buscarTexto(MEJOR_GOLPE)

        val golpes = leerGolpes(contexto)

        return CapturaLeida(
            nivelSesion = nivel,
            mediaDelJugador = media,
            totalGolpes = total,
            duracionMin = duracion,
            pulsoMedio = pulsoMedio,
            pulsoMax = pulsoMax,
            calorias = calorias,
            pasos = pasos,
            mejorGolpe = mejorGolpe,
            posicion = posicionEnPista(normalizados),
            golpes = golpes,
            sinEntender = limpios.indices.filter { it !in usados }.map { limpios[it].texto },
        )
    }

    /** Agrupa los trozos en filas por su altura, cada fila ordenada de izquierda a derecha. */
    private fun agruparEnFilas(trozos: List<Trozo>): List<List<Int>> {
        val filas = mutableListOf<MutableList<Int>>()
        var alturaActual = Double.NaN
        for (i in trozos.indices) {
            val y = trozos[i].y
            if (filas.isEmpty() || abs(y - alturaActual) > TOLERANCIA_FILA) {
                filas.add(mutableListOf(i))
                alturaActual = y
            } else {
                filas.last().add(i)
            }
        }
        return filas.map { fila -> fila.sortedBy { trozos[it].x } }
    }

    /** El estado de una lectura: lo que hay y lo que ya se ha consumido. */
    private class Contexto(
        val trozos: List<Trozo>,
        val normalizados: List<String>,
        val filas: List<List<Int>>,
        val filaDe: IntArray,
        val usados: MutableSet<Int>,
    ) {

        /** Los índices de los trozos cuyo texto contiene alguna de las claves. */
        fun etiquetas(claves: List<String>, excluyendo: List<String> = emptyList()): List<Int> =
            trozos.indices.filter { i ->
                i !in usados &&
                    claves.any { normalizados[i].contains(it) } &&
                    excluyendo.none { normalizados[i].contains(it) }
            }

        /**
         * El valor de un rótulo, buscado en este orden: dentro del propio rótulo, a su
         * derecha en la misma fila, debajo en su columna, encima en su columna.
         *
         * El orden sale de cómo se maquetan estas pantallas de verdad. Lo de mirar
         * **encima** no es simetría gratuita: en las tarjetas de actividad el número va
         * arriba y el rótulo debajo (`898` / `K Cal`), y sin eso no se lee ninguna.
         */
        fun buscar(
            claves: List<String>,
            maximo: Double? = null,
            enMinutos: Boolean = false,
            desde: Int = 0,
            hasta: Int = Int.MAX_VALUE,
            excluyendo: List<String> = emptyList(),
        ): Dato? {
            for (i in etiquetas(claves, excluyendo)) {
                val fila = filaDe[i]
                if (fila < desde || fila > hasta) continue
                val encontrado = valorPara(i, maximo, enMinutos) ?: continue
                usados.add(i)
                usados.add(encontrado.second)
                return encontrado.first
            }
            return null
        }

        /** Como [buscar] pero el valor es texto (p. ej. "Mejor golpe" → "REMATE"). */
        fun buscarTexto(claves: List<String>): String? {
            for (i in etiquetas(claves)) {
                val fila = filas[filaDe[i]]
                val derecha = fila.filter { it > i && it !in usados && numerosDe(trozos[it].texto).isEmpty() }
                val elegido = derecha.firstOrNull() ?: continue
                usados.add(i)
                usados.add(elegido)
                return trozos[elegido].texto
            }
            return null
        }

        private fun valorPara(
            etiqueta: Int, maximo: Double?, enMinutos: Boolean
        ): Pair<Dato, Int>? {
            fun leerDe(indice: Int): Dato? {
                val texto = trozos[indice].texto
                val valor = if (enMinutos) minutosDe(texto) else numeroDe(texto)
                if (valor == null) return null
                if (maximo != null && valor > maximo) return null
                return Dato(valor, texto)
            }

            // 1. El número está en el propio rótulo ("Golpes 407").
            leerDe(etiqueta)?.let { return it to etiqueta }

            val fila = filaDe[etiqueta]
            // 2. A la derecha, en la misma fila.
            for (j in filas[fila]) {
                if (j <= etiqueta || j in usados) continue
                leerDe(j)?.let { return it to j }
            }
            // 3 y 4. Debajo y encima, en la misma columna.
            for (otra in listOf(fila + 1, fila - 1)) {
                if (otra !in filas.indices) continue
                val candidato = filas[otra]
                    .filter { it !in usados && abs(trozos[it].x - trozos[etiqueta].x) <= TOLERANCIA_COLUMNA }
                    .minByOrNull { abs(trozos[it].x - trozos[etiqueta].x) }
                    ?: continue
                leerDe(candidato)?.let { return it to candidato }
            }
            return null
        }
    }

    /**
     * Los golpes de la captura.
     *
     * Tres maquetaciones, y las tres salen en las capturas de verdad:
     *
     * 1. **Tarjeta de un golpe**: el nombre arriba y debajo `Num. golpes` y `Calidad` con
     *    sus valores en otra fila.
     * 2. **Lista de volumen**: el nombre y el número a la derecha, en la misma fila.
     * 3. **Radar de calidad**: el número encima del nombre.
     *
     * **Cada nombre acota hasta dónde se busca su valor**, y eso resuelve un fallo real:
     * en la pantalla del globo el título de navegación pone "Globo" y debajo vienen las
     * dos tarjetas "Globo Rev." y "Globo Dcha."; sin acotar, el "Globo" de arriba se habría
     * quedado con los números de la primera tarjeta y el jugador habría visto un golpe que
     * no existe con los datos de otro.
     */
    private fun leerGolpes(contexto: Contexto): List<GolpeLeido> {
        val apariciones = contexto.trozos.indices
            .mapNotNull { i -> nombreDeGolpe(contexto.normalizados[i])?.let { i to it } }
        if (apariciones.isEmpty()) return emptyList()

        val encontrados = linkedMapOf<String, GolpeLeido>()
        for ((orden, aparicion) in apariciones.withIndex()) {
            val (indice, nombrado) = aparicion
            val filaInicio = contexto.filaDe[indice]
            // Hasta el siguiente nombre de golpe: cada tarjeta se queda con lo suyo.
            val filaFin = apariciones.getOrNull(orden + 1)
                ?.let { contexto.filaDe[it.first] - 1 }
                ?: (contexto.filas.size - 1)

            val cantidad = contexto.buscar(
                NUM_GOLPES, maximo = 5_000.0, desde = filaInicio, hasta = filaFin
            )
            val nota = contexto.buscar(
                CALIDAD, maximo = 10.0, desde = filaInicio, hasta = filaFin
            )
            val (notaSuelta, cantidadSuelta) = if (nota == null && cantidad == null) {
                sueltos(contexto, indice)
            } else {
                null to null
            }

            val resultado = GolpeLeido(
                nombre = nombrado.nombre,
                golpe = nombrado.golpe,
                nota = nota ?: notaSuelta,
                cantidad = cantidad ?: cantidadSuelta,
            )
            if (resultado.nota == null && resultado.cantidad == null) continue
            contexto.usados.add(indice)
            // El primero gana: una captura puede repetir el nombre en un título y en una
            // leyenda, y lo de arriba es lo que el jugador está mirando.
            encontrados.putIfAbsent(nombrado.nombre, resultado)
        }

        // En el orden del repertorio los conocidos y detrás los agregados, para que la
        // pantalla de confirmación se lea siempre igual venga la captura como venga.
        val conocidos = GolpeVisible.entries.mapNotNull { visible ->
            encontrados.values.firstOrNull { it.golpe == visible }
        }
        return conocidos + encontrados.values.filter { it.golpe == null }
    }

    /**
     * El número que acompaña a un nombre de golpe sin rótulo: a su derecha en la misma
     * fila (lista de volumen) o justo encima (radar de calidad).
     *
     * Con decimales es nota y entero es recuento, porque una calidad lleva decimales y un
     * recuento no. Es una heurística, y por eso el número viaja con su texto para que se
     * pueda corregir de un vistazo.
     */
    private fun sueltos(contexto: Contexto, indice: Int): Pair<Dato?, Dato?> {
        val fila = contexto.filaDe[indice]
        val candidatos = mutableListOf<Int>()
        contexto.filas[fila].filterTo(candidatos) { it > indice && it !in contexto.usados }
        if (fila - 1 in contexto.filas.indices) {
            contexto.filas[fila - 1]
                .filter {
                    it !in contexto.usados &&
                        abs(contexto.trozos[it].x - contexto.trozos[indice].x) <= TOLERANCIA_COLUMNA
                }
                .minByOrNull { abs(contexto.trozos[it].x - contexto.trozos[indice].x) }
                ?.let { candidatos.add(it) }
        }
        // El propio texto del nombre, por si viene "Bandeja 3,5 · 24".
        val propios = numerosDe(contexto.trozos[indice].texto)
        if (propios.size >= 2) {
            val texto = contexto.trozos[indice].texto
            return Dato(propios[0], texto) to Dato(propios[1], texto)
        }
        if (propios.size == 1) {
            val texto = contexto.trozos[indice].texto
            return if (tieneDecimales(propios[0])) Dato(propios[0], texto) to null
            else null to Dato(propios[0], texto)
        }

        for (j in candidatos) {
            val numero = numeroDe(contexto.trozos[j].texto) ?: continue
            contexto.usados.add(j)
            val dato = Dato(numero, contexto.trozos[j].texto)
            return if (tieneDecimales(numero)) dato to null else null to dato
        }
        return null to null
    }

    /** El lado de la pista, si la captura lo dice. */
    private fun posicionEnPista(normalizados: List<String>): String? {
        val hayRotulo = normalizados.any { it.contains("posicion en pista") }
        if (!hayRotulo) return null
        // No se decide por cuál de los dos aparece —aparecen los dos, es un dibujo de la
        // pista entera— así que esto solo dice que la captura lo trae; el lado lo elige el
        // jugador. Inventarlo a partir del texto sería adivinar por el color del dibujo.
        return null
    }

    private fun tieneDecimales(valor: Double): Boolean = valor != valor.toLong().toDouble()

    /**
     * Un nombre de golpe reconocido, con su correspondencia en nuestro repertorio.
     *
     * `internal` y no privado porque `nombreDeGolpe` lo devuelve y los tests lo usan: un
     * tipo privado en la firma de una función visible no compila, y esconderlo obligaría
     * a devolver un par suelto que no se entiende al leerlo.
     */
    internal data class Nombrado(val nombre: String, val golpe: GolpeVisible?)

    /**
     * Cómo puede estar escrito cada golpe, **todo en una lista y ordenado de más largo a
     * más corto**.
     *
     * Las dos cosas son necesarias y la segunda no es evidente. "Volea de revés" contiene
     * "revés", así que el patrón largo tiene que probarse antes — pero además las
     * variantes abreviadas, que son las que usa la app de verdad ("Volea Rev.", "Globo
     * Dcha."), tienen que competir **en la misma pasada**: si se dejan para un segundo
     * intento, "volea rev" ya habrá casado con "reves" y el jugador vería su volea de
     * revés contada como revés, que es otro golpe. Pasó, y lo pilló un test.
     *
     * "Volea" y "Globo" a secas son **agregados**: la pantalla de volumen no separa lados.
     * Van los últimos, así que solo ganan cuando no hay nada más específico.
     */
    private val PATRONES: List<Pair<String, Nombrado>> = buildList {
        fun añadir(texto: String, nombre: String, golpe: GolpeVisible?) {
            add(normalizar(texto) to Nombrado(nombre, golpe))
        }
        for (golpe in GolpeVisible.entries) {
            añadir(golpe.etiqueta, golpe.etiqueta, golpe)
            val sinPreposicion = golpe.etiqueta.replace(" de ", " ")
            if (sinPreposicion != golpe.etiqueta) añadir(sinPreposicion, golpe.etiqueta, golpe)
        }
        // Las abreviaturas de la Padel Band, sacadas de capturas reales.
        añadir("volea rev", "Volea de revés", GolpeVisible.VOLEA_REVES)
        añadir("volea dcha", "Volea de derecha", GolpeVisible.VOLEA_DERECHA)
        añadir("globo rev", "Globo de revés", GolpeVisible.GLOBO_REVES)
        añadir("globo dcha", "Globo de derecha", GolpeVisible.GLOBO_DERECHA)
        // Agregados sin lado.
        añadir("volea", "Volea", null)
        añadir("globo", "Globo", null)
    }.sortedByDescending { it.first.length }

    /** El golpe que nombra este texto ya normalizado, o null. */
    internal fun nombreDeGolpe(normalizado: String): Nombrado? =
        PATRONES.firstOrNull { normalizado.contains(it.first) }?.second

    /** El golpe del repertorio que nombra este texto, o null. Para los tests. */
    internal fun golpeDe(normalizado: String): GolpeVisible? = nombreDeGolpe(normalizado)?.golpe

    /**
     * Minúsculas, sin acentos, sin puntos y con un solo espacio.
     *
     * Los puntos fuera porque la app abrevia con ellos —"Rev.", "Dcha.", "Num. golpes"— y
     * un patrón con punto sería un patrón que deja de valer en cuanto otra app escriba lo
     * mismo sin él. No afecta a los números: estos se sacan siempre del texto original.
     */
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
                    '.' -> ' '
                    else -> c
                }
            )
        }
        return sb.toString().replace(Regex("\\s+"), " ").trim()
    }

    /** El primer número de un texto, o null. */
    internal fun numeroDe(texto: String): Double? = numerosDe(texto).firstOrNull()

    /**
     * Todos los números de un texto, en orden.
     *
     * **La coma es decimal**, que es como lo escribe una app en español: "3,5" es tres y
     * medio y no dos números. Un "3,5/7" da solo el 3,5 — el 7 es el máximo de la escala,
     * no un dato. Y un texto con forma de reloj ("01:39:46") no da números sueltos: eso lo
     * lee [minutosDe], porque leer el "01" como si fuera un dato daría un partido de un
     * minuto.
     */
    internal fun numerosDe(texto: String): List<Double> {
        if (RELOJ.matches(texto.trim())) return emptyList()
        val sinEscala = texto.replace(Regex("/\\s*\\d+([.,]\\d+)?"), "")
        return Regex("-?\\d+(?:[.,]\\d+)?")
            .findAll(sinEscala)
            .mapNotNull { it.value.replace(',', '.').toDoubleOrNull() }
            .filter { it >= 0 }
            .toList()
    }

    private val RELOJ = Regex("^\\d{1,2}:\\d{2}:\\d{2}$")

    /**
     * Minutos a partir de un texto de duración.
     *
     * La Padel Band escribe el tiempo como **`01:39:46`**, y eso no es un número: leído
     * con el lector normal daría "1" y el partido entraría en la liga como un minuto. Aquí
     * se convierte a 99,8 minutos. También vale "92 min" y un número suelto.
     */
    internal fun minutosDe(texto: String): Double? {
        val limpio = texto.trim()
        val reloj = RELOJ.find(limpio)
        if (reloj != null) {
            val partes = limpio.split(":").mapNotNull { it.toIntOrNull() }
            if (partes.size == 3) {
                return partes[0] * 60.0 + partes[1] + partes[2] / 60.0
            }
        }
        return numeroDe(limpio)
    }
}
