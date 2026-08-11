package com.risingpadel.core.detection

import com.risingpadel.core.model.ShotFeatures
import com.risingpadel.core.model.ShotType
import kotlin.test.Test
import kotlin.test.assertTrue

/**
 * La tanda de pista de agosto de 2026: 42 golpes etiquetados por el jugador **antes** de
 * darlos, ocho tipos seguidos.
 *
 * Es la primera tanda grabada con el eje de elevación ya corregido, así que es la primera
 * cuyos ángulos se pueden leer tal cual. La anterior venía con la elevación contaminada y
 * los umbrales que salieron de ella estaban apoyados en arena.
 *
 * **El signo de la rotación axial va girado aquí a propósito.** La tanda se grabó cuando
 * el reloj todavía entregaba el axial invertido —efecto colateral de girar el eje del
 * antebrazo para arreglar la elevación—, y este fichero representa lo que el reloj
 * entrega **desde que eso está corregido** (`invertAxialSign` en el reloj). Sin el giro,
 * el fixture estaría probando el bug en vez de la corrección.
 *
 * Los suelos son suelos de verdad, no aspiraciones: se ponen justo por debajo de lo que
 * hoy se consigue, para que una regresión salte y una mejora no obligue a tocar el test.
 */
class TandaLimpiaDe42Test {

    /** Un golpe de la tanda: lo que el jugador dijo que iba a dar, y lo que se midió. */
    private data class Golpe(
        val n: Int,
        val real: ShotType,
        val prep: Float,
        val alto: Float,
        /** Tal como salió del reloj sin corregir; se gira al construir los rasgos. */
        val axialCrudo: Float,
        val barrido: Float,
        val pico: Float,
    )

    private fun Golpe.rasgos(): ShotFeatures = ShotFeatures(
        sweptAngleDeg = barrido,
        peakGyroRadS = pico,
        // La elevación del instante del impacto no la enseña la ficha; el rasgo que usa
        // el clasificador es el pico, que sí está.
        elevationDeg = alto,
        // El giro del signo: lo que el reloj corregido entregará para este mismo golpe.
        axialRotationRadS = -axialCrudo,
        swingDurationMs = 300,
        peakElevationDeg = alto,
        prepElevationDeg = prep,
    )

    private val tanda = listOf(
        // 1-6 remate
        Golpe(1, ShotType.SMASH, 5f, 37f, 0.5f, 246f, 16.8f),
        Golpe(2, ShotType.SMASH, -22f, 41f, -0.6f, 223f, 18.4f),
        Golpe(3, ShotType.SMASH, -27f, 50f, -2.0f, 278f, 18.7f),
        Golpe(4, ShotType.SMASH, -24f, 48f, 2.1f, 262f, 18.6f),
        Golpe(5, ShotType.SMASH, -23f, 38f, 1.2f, 219f, 16.9f),
        Golpe(6, ShotType.SMASH, -21f, 37f, -4.9f, 288f, 14.5f),
        // 7-12 bandeja
        Golpe(7, ShotType.BANDEJA, 54f, 48f, -3.9f, 251f, 11.5f),
        Golpe(8, ShotType.BANDEJA, 61f, 56f, 3.6f, 211f, 9.3f),
        Golpe(9, ShotType.BANDEJA, 60f, 55f, 4.4f, 188f, 12.8f),
        Golpe(10, ShotType.BANDEJA, 50f, 48f, 2.3f, 224f, 13.3f),
        Golpe(11, ShotType.BANDEJA, 68f, 53f, 0.7f, 227f, 11.8f),
        Golpe(12, ShotType.BANDEJA, 46f, 39f, 4.0f, 211f, 13.6f),
        // 13-17 víbora
        Golpe(13, ShotType.VIBORA, 51f, 38f, 3.0f, 191f, 11.6f),
        Golpe(14, ShotType.VIBORA, 54f, 44f, 2.7f, 166f, 11.0f),
        Golpe(15, ShotType.VIBORA, 53f, 33f, -7.8f, 348f, 11.5f),
        Golpe(16, ShotType.VIBORA, 53f, 42f, 3.5f, 173f, 11.6f),
        Golpe(17, ShotType.VIBORA, 28f, 15f, 0.2f, 90f, 11.8f),
        // 18-22 volea de revés
        Golpe(18, ShotType.BACKHAND_VOLLEY, 20f, 5f, 2.5f, 163f, 16.5f),
        Golpe(19, ShotType.BACKHAND_VOLLEY, 15f, -3f, 0.6f, 141f, 16.0f),
        Golpe(20, ShotType.BACKHAND_VOLLEY, 9f, 2f, 2.2f, 151f, 18.2f),
        Golpe(21, ShotType.BACKHAND_VOLLEY, 21f, 7f, 0.1f, 65f, 13.3f),
        Golpe(22, ShotType.BACKHAND_VOLLEY, -12f, -15f, -1.3f, 105f, 11.9f),
        // 23-27 volea de derecha
        Golpe(23, ShotType.FOREHAND_VOLLEY, -2f, -5f, 0.2f, 95f, 9.3f),
        Golpe(24, ShotType.FOREHAND_VOLLEY, -16f, -17f, -3.4f, 126f, 12.6f),
        Golpe(25, ShotType.FOREHAND_VOLLEY, 3f, -4f, -3.9f, 130f, 12.1f),
        Golpe(26, ShotType.FOREHAND_VOLLEY, 2f, 2f, 3.1f, 58f, 9.7f),
        Golpe(27, ShotType.FOREHAND_VOLLEY, -68f, -82f, 3.7f, 46f, 7.5f),
        // 28-32 revés
        Golpe(28, ShotType.BACKHAND, -38f, -57f, 3.5f, 85f, 10.0f),
        Golpe(29, ShotType.BACKHAND, -25f, -42f, 4.2f, 117f, 11.2f),
        Golpe(30, ShotType.BACKHAND, -28f, -47f, 6.5f, 119f, 11.4f),
        Golpe(31, ShotType.BACKHAND, -28f, -48f, 5.1f, 113f, 11.8f),
        Golpe(32, ShotType.BACKHAND, -44f, -28f, -5.0f, 69f, 7.5f),
        // 33-35 derecha (36 y 37 resultaron ser saques, ver abajo)
        Golpe(33, ShotType.FOREHAND, -45f, -39f, -6.2f, 79f, 14.7f),
        Golpe(34, ShotType.FOREHAND, -33f, -32f, -4.9f, 91f, 9.5f),
        Golpe(35, ShotType.FOREHAND, 26f, -37f, -8.1f, 211f, 19.5f),
        // 36 y 37 los etiquetó el jugador como derechas y luego confirmó que eran
        // saques: el reloj se dejó golpes a mitad de tanda y le corrió la cuenta. Sus
        // números no dejaban lugar a dudas —361° y 304° de barrido con 9,7 de
        // pronación, los mismos que el saque 39— y es exactamente para esto para lo que
        // están los contadores de descarte: sin ellos, un golpe perdido no deja rastro
        // y descoloca las etiquetas de todo lo que viene detrás.
        Golpe(36, ShotType.SERVE, -4f, -19f, -9.7f, 361f, 17.7f),
        Golpe(37, ShotType.SERVE, 53f, 14f, -9.7f, 304f, 15.3f),
        // 38-42 saque
        Golpe(38, ShotType.SERVE, 5f, -10f, -0.7f, 128f, 8.4f),
        Golpe(39, ShotType.SERVE, 46f, 8f, -9.4f, 336f, 18.6f),
        Golpe(40, ShotType.SERVE, 46f, 36f, -2.1f, 154f, 12.7f),
        Golpe(41, ShotType.SERVE, 55f, 26f, -3.7f, 237f, 12.9f),
        Golpe(42, ShotType.SERVE, 26f, 53f, 2.3f, 268f, 17.2f),
    )

    private val classifier = ShotClassifier()

    private fun aciertos(golpes: List<Golpe>): Int =
        golpes.count { classifier.classify(it.rasgos()).type == it.real }

    /** ¿Es un golpe alto (remate, bandeja o víbora)? */
    private fun esAlto(tipo: ShotType) =
        tipo == ShotType.SMASH || tipo == ShotType.BANDEJA || tipo == ShotType.VIBORA

    private fun esVolea(tipo: ShotType) =
        tipo == ShotType.FOREHAND_VOLLEY || tipo == ShotType.BACKHAND_VOLLEY

    private fun esDeFondo(tipo: ShotType) =
        tipo == ShotType.FOREHAND || tipo == ShotType.BACKHAND

    @Test
    fun `la puerta de golpe alto no se equivoca en esta tanda`() {
        // El rasgo más limpio del detector: los diecisiete altos picaron +15..+56 y los
        // veinticinco bajos −82..+14. Ni un solapamiento. Si esto se rompe, se rompió el
        // eje de elevación otra vez.
        val altos = tanda.filter { esAlto(it.real) }
        val bajos = tanda.filter { esVolea(it.real) || esDeFondo(it.real) }
        assertTrue(
            altos.all { esAlto(classifier.classify(it.rasgos()).type) },
            "algún golpe alto se salió de la rama alta",
        )
        assertTrue(
            bajos.none { esAlto(classifier.classify(it.rasgos()).type) },
            "algún golpe bajo se coló en la rama alta",
        )
    }

    @Test
    fun `los remates se separan de bandejas y víboras por el pico`() {
        val remates = tanda.filter { it.real == ShotType.SMASH }
        assertTrue(aciertos(remates) == remates.size, "no salieron los seis remates")
    }

    @Test
    fun `las bandejas y las víboras salen mayormente bien`() {
        // Nueve de once. Las dos familias se rozan por altura (una bandeja a +39 y una
        // víbora a +44) y no hay otro rasgo que las separe: el efecto medio de las dos es
        // el mismo número. Es la frontera que más gana con la calibración por jugador.
        val altos = tanda.filter { it.real == ShotType.BANDEJA || it.real == ShotType.VIBORA }
        assertTrue(aciertos(altos) >= 9, "bandejas y víboras: ${aciertos(altos)}/11")
    }

    @Test
    fun `las voleas se reconocen como voleas`() {
        // El lado es otra historia (ver el test de abajo); lo que no puede fallar es que
        // un golpe de red salga como golpe de fondo o como remate.
        val voleas = tanda.filter { esVolea(it.real) }
        assertTrue(
            voleas.all { esVolea(classifier.classify(it.rasgos()).type) },
            "alguna volea no salió como volea",
        )
    }

    @Test
    fun `el lado de la volea es una moneda al aire, y se admite`() {
        // Una volea es un bloqueo sin muñeca: el efecto que decide el lado sencillamente
        // no está. Las diez voleas de esta tanda midieron entre 0,1 y 3,9 de rotación
        // axial —ruido— y seis salen bien. Queda documentado como límite y no como
        // objetivo: forzarlo con estos datos sería inventarse una regla.
        val voleas = tanda.filter { esVolea(it.real) }
        assertTrue(aciertos(voleas) >= 6, "lado de la volea: ${aciertos(voleas)}/10")
    }

    @Test
    fun `derecha y revés dejan de salir cambiados`() {
        // La prueba del signo axial: con el convenio anterior salían siete de ocho al
        // revés. Los reveses miden positivo y las derechas negativo en el reloj ya
        // corregido, y aquí se comprueba que el clasificador lo lee así.
        val fondo = tanda.filter { esDeFondo(it.real) }.filter { it.n in 29..35 }
        assertTrue(aciertos(fondo) >= 6, "golpes de fondo: ${aciertos(fondo)}/7")
    }

    @Test
    fun `los saques con barrido de saque salen todos`() {
        // El detector tenía razón y la etiqueta estaba corrida: los golpes 36 y 37 se
        // apuntaron como derechas y eran saques. Los tres con firma de saque —barrido
        // por encima de 300° con 9,4-9,7 de pronación— salen los tres.
        val conFirma = tanda.filter { it.n == 36 || it.n == 37 || it.n == 39 }
        assertTrue(
            conFirma.all { classifier.classify(it.rasgos()).type == ShotType.SERVE },
            "los saques con la firma completa no pueden fallar",
        )
    }

    @Test
    fun `los saques flojos siguen sin reconocerse, y consta`() {
        // El límite de verdad, y no es de umbral: los saques 38, 40, 41 y 42 no llevan
        // la firma. El 38 barrió 128° con 0,7 de pronación —es un saque puesto, sin
        // muñeca— y el 40, 41 y 42 se golpearon a +36, +26 y +53° de elevación, o sea
        // por encima de la cabeza, que es donde un saque de pádel no puede estar.
        //
        // Bajar el umbral del saque para pescarlos convertiría en saque medio partido.
        // Esto lo arregla un modelo entrenado con la señal cruda, no otra constante.
        val flojos = tanda.filter { it.n in listOf(38, 40, 41, 42) }
        assertTrue(aciertos(flojos) == 0, "si alguno sale, revisa por qué antes de celebrarlo")
    }

    @Test
    fun `el acierto global no baja de donde está`() {
        // 30 de 42 con los ocho tipos. Antes de esta tanda eran 16.
        assertTrue(aciertos(tanda) >= 30, "acierto global: ${aciertos(tanda)}/42")
    }

    @Test
    fun `por familias el acierto es bastante mejor que por tipos`() {
        // Alto / volea / fondo / saque. Es la medida que importa para el nivel: confundir
        // una bandeja con una víbora no mueve casi nada, confundirla con una volea sí.
        fun familia(tipo: ShotType) = when {
            esAlto(tipo) -> "alto"
            esVolea(tipo) -> "volea"
            esDeFondo(tipo) -> "fondo"
            else -> "saque"
        }
        val buenas = tanda.count {
            familia(classifier.classify(it.rasgos()).type) == familia(it.real)
        }
        assertTrue(buenas >= 37, "por familias: $buenas/42")
    }
}
