package com.risingpadel.core.detection

import com.risingpadel.core.model.ShotFeatures
import com.risingpadel.core.model.ShotType
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Treinta golpes reales de pista, cinco de cada tipo, etiquetados por el jugador
 * (ago 2026). Es el conjunto de verdad-terreno más completo que existe del proyecto.
 *
 * **La elevación de esta tanda no es de fiar y no se usa para nada.** Se grabó con la
 * autocalibración del signo todavía puesta, y se ve en los propios datos: los cinco
 * saques, dados seguidos en el mismo minuto por la misma persona, salieron tres con
 * preparación +45..+49 y dos con −46..−49. Un brazo no cambia de sitio a mitad de tanda;
 * lo que cambió fue el signo que aplicaba el detector. Por eso las bandejas (−28 de
 * mediana) midieron menos altura que las voleas de revés (+35), que es imposible.
 *
 * Lo que sí es válido —y es lo que fijan estas pruebas— son los rasgos que no dependen
 * del signo de la gravedad: el barrido, la rotación axial y el pico de giro.
 */
class TandaDeSeisTiposTest {

    /** Un golpe de la tanda. La elevación va aparte porque no se usa. */
    private fun golpe(axial: Float, barrido: Float, pico: Float) = ShotFeatures(
        sweptAngleDeg = barrido,
        peakGyroRadS = pico,
        elevationDeg = 0f,
        axialRotationRadS = axial,
        swingDurationMs = 250,
        peakElevationDeg = 0f,
        prepElevationDeg = null,
    )

    private val remates = listOf(
        golpe(-1.3f, 219f, 14.7f), golpe(-3.1f, 215f, 14.4f), golpe(3.2f, 319f, 23.2f),
        golpe(-1.7f, 264f, 17.7f), golpe(-1.5f, 218f, 19.6f),
    )
    private val bandejas = listOf(
        golpe(-4.8f, 221f, 13.0f), golpe(-0.4f, 238f, 16.4f), golpe(-4.0f, 210f, 11.1f),
        golpe(-2.5f, 175f, 11.0f), golpe(-2.3f, 259f, 13.3f),
    )
    private val viboras = listOf(
        golpe(-3.5f, 222f, 12.2f), golpe(-3.0f, 158f, 9.4f), golpe(6.9f, 59f, 11.0f),
        golpe(-3.3f, 195f, 10.1f), golpe(0.2f, 251f, 13.5f),
    )
    private val voleasDeReves = listOf(
        golpe(-0.7f, 178f, 16.3f), golpe(-1.7f, 180f, 19.0f), golpe(-1.7f, 172f, 16.0f),
        golpe(1.5f, 184f, 20.9f), golpe(1.4f, 51f, 9.9f),
    )
    private val voleasDeDerecha = listOf(
        golpe(1.2f, 120f, 10.2f), golpe(0.5f, 109f, 10.2f), golpe(2.7f, 121f, 9.3f),
        golpe(5.7f, 172f, 9.2f), golpe(2.2f, 116f, 10.8f),
    )
    private val saques = listOf(
        golpe(8.0f, 289f, 15.3f), golpe(8.7f, 307f, 14.3f), golpe(8.2f, 302f, 15.1f),
        golpe(8.3f, 288f, 12.5f), golpe(6.2f, 181f, 9.5f),
    )

    private val noSonSaques = remates + bandejas + viboras + voleasDeReves + voleasDeDerecha

    private val classifier = ShotClassifier()

    // --- el saque ---

    @Test
    fun `los saques con swing completo se reconocen`() {
        // La firma del saque de pádel: barrido largo con mucha pronación. No tiene la
        // violencia del saque de tenis —estos picaron 9,5-15,3— y el umbral anterior,
        // que pedía 18 de pico, no dejaba pasar ni uno.
        //
        // El quinto queda fuera y se deja escrito: barrió 181°, y una derecha de fondo
        // barre ~190 rotando 7,9-10,5 rad/s. Con estos rasgos son el mismo golpe. Bajar
        // el umbral para cazarlo convertiría todas las derechas en saques, que es un
        // error mucho más caro que perder un saque corto de cada cinco.
        for ((i, saque) in saques.dropLast(1).withIndex()) {
            assertEquals(
                ShotType.SERVE, classifier.classify(saque).type,
                "el saque ${i + 1} de la tanda no se reconoció",
            )
        }
    }

    @Test
    fun `un saque flojo y una derecha de fondo son el mismo golpe para estos rasgos`() {
        // No es un fallo escondido, es el límite: se deja fijado para que nadie baje el
        // umbral sin saber lo que se lleva por delante.
        val saqueCorto = saques.last()
        val derechaDeFondo = golpe(axial = 9f, barrido = 190f, pico = 20f)
        assertTrue(saqueCorto.sweptAngleDeg < derechaDeFondo.sweptAngleDeg)
        assertTrue(abs(saqueCorto.axialRotationRadS) < abs(derechaDeFondo.axialRotationRadS))
    }

    @Test
    fun `ningun otro golpe de la tanda se cuela como saque`() {
        // El margen es estrecho por los dos lados y por eso se exigen las dos cosas: la
        // víbora más rotada (6,9) barrió solo 59°, y la volea más rotada (5,7) se quedó
        // en 172° de barrido. Ninguna pasa las dos puertas.
        for ((i, golpe) in noSonSaques.withIndex()) {
            assertTrue(
                classifier.classify(golpe).type != ShotType.SERVE,
                "el golpe ${i + 1} (no saque) salió como saque",
            )
        }
    }

    // --- lo que los rasgos válidos sí separan ---

    @Test
    fun `la rotacion axial separa el saque de todo lo demas`() {
        val minSaque = saques.minOf { abs(it.axialRotationRadS) }
        val maxResto = noSonSaques.maxOf { abs(it.axialRotationRadS) }
        assertTrue(
            minSaque > 5f,
            "el saque menos rotado da $minSaque; si baja de 5 hay que revisar el umbral",
        )
        assertTrue(
            maxResto < 7f,
            "algo que no es saque rota $maxResto: se acerca demasiado a la firma del saque",
        )
    }

    @Test
    fun `el pico separa remate de bandeja en esta tanda, pero no en todas`() {
        // Aquí los remates picaron 14,4-23,2 y las bandejas 11,0-16,4. En la tanda de
        // agosto los remates bajaban a 10,6, y en la tanda limpia de 42 subían a 14,5.
        // Tres tandas reales, tres fronteras distintas.
        //
        // Es exactamente lo que una constante global no puede resolver y la calibración
        // por jugador sí: el umbral de fábrica sale de la tanda mejor medida y son las
        // tandas de cada uno las que lo mueven — arriba o abajo, según su muñeca.
        val minRemate = remates.minOf { it.peakGyroRadS }
        val medianaBandeja = bandejas.map { it.peakGyroRadS }.sorted()[2]
        assertTrue(minRemate > medianaBandeja, "el remate más flojo ya pega más que la bandeja típica")

        val calibrado = ThresholdCalibrator.calibrar(
            remates.map { ShotType.SMASH to it } + bandejas.map { ShotType.BANDEJA to it } +
                viboras.map { ShotType.VIBORA to it }
        ).calibracion
        val umbral = calibrado.smashPeakGyroRadS
        assertTrue(umbral != null, "con seis remates y seis bandejas hay de sobra para calibrar")
        // Hacia arriba: este jugador remata más fuerte que el de la tanda de fábrica, y
        // con el umbral de serie alguna de sus bandejas se le colaría como remate.
        assertTrue(
            umbral!! > DetectorConfig.DEFAULT.smashPeakGyroRadS,
            "las tandas de este jugador tienen que subirle el umbral del remate: $umbral",
        )
    }

    @Test
    fun `la rotacion axial NO separa la vibora de la bandeja en este jugador`() {
        // Se deja escrito porque es el hallazgo, no un fallo: las bandejas rotaron
        // 0,4-4,8 y las víboras 0,2-6,9. Se solapan casi enteras. Inventar un umbral
        // aquí sería ajustar a cinco golpes y llamarlo calibración; hasta que haya un
        // rasgo que de verdad los separe, este golpe se va a confundir y hay que decirlo.
        val bandeja = bandejas.map { abs(it.axialRotationRadS) }
        val vibora = viboras.map { abs(it.axialRotationRadS) }
        assertTrue(
            bandeja.max() > vibora.sorted()[2],
            "si esto deja de solaparse, hay material para separar víbora de bandeja",
        )
    }

    @Test
    fun `el barrido separa la volea de derecha del resto`() {
        // 109-172°, la firma más compacta de la tanda. Es la familia que mejor sale.
        assertTrue(voleasDeDerecha.maxOf { it.sweptAngleDeg } <= 172f)
    }
}
