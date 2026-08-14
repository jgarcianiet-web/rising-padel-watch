package com.risingpadel.core.detection

import com.risingpadel.core.model.ShotFeatures
import com.risingpadel.core.model.ShotType
import kotlin.test.Test
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * La tanda de pista de agosto de 2026 grabada **por bloques**: 40 golpes, ocho bloques
 * de cinco, con la etiqueta elegida antes de cada bloque. Es la primera tanda grabada
 * con el signo axial ya corregido en el reloj (las derechas miden positivo), así que
 * sus rasgos se usan tal cual, sin girar nada.
 *
 * Lo que enseñó esta tanda, y por qué existe este fichero:
 *
 * 1. **Contradice a la tanda de 42 en las dos fronteras de elevación.** Allí los altos
 *    picaban +15..+56 y aquí +4..+31; allí la bandeja iba por ENCIMA de la víbora y
 *    aquí van mezcladas (+4..+20 contra +6..+29). Ningún umbral fijo puede servir a las
 *    dos tandas a la vez: esas fronteras son del jugador y del día, y las tiene que
 *    poner el calibrador con las tandas de cada uno. Este test comprueba que lo hace.
 *
 * 2. **El saque tiene una segunda firma que sí es universal**: el brazo armado en alto
 *    (+10..+27 de preparación) con el impacto a la cintura. Con la firma vieja salía
 *    un saque de cinco; con las dos, los cinco.
 *
 * 3. **Una volea con mucho acompañamiento sigue siendo una volea**: la 27 barrió 301°
 *    con la pala quieta y el techo de 210° la convertía en revés.
 *
 * Los suelos son suelos: justo debajo de lo que hoy se consigue.
 */
class TandaEnBloquesDe40Test {

    private data class Golpe(
        val n: Int,
        val real: ShotType,
        val prep: Float,
        val alto: Float,
        val axial: Float,
        val barrido: Float,
        val pico: Float,
        val picoAxial: Float,
        val caida: Float,
    )

    private fun Golpe.rasgos(): ShotFeatures = ShotFeatures(
        sweptAngleDeg = barrido,
        peakGyroRadS = pico,
        elevationDeg = alto,
        axialRotationRadS = axial,
        swingDurationMs = 300,
        peakElevationDeg = alto,
        prepElevationDeg = prep,
        peakAxialRotationRadS = picoAxial,
        elevationDropDeg = caida,
    )

    private val tanda = listOf(
        // 1-5 bandeja — planas: axial −0,3..+2,3. Su altura (+4..+20) queda POR DEBAJO
        // de la puerta de fábrica en dos de ellas: sin calibrar salen como voleas.
        Golpe(1, ShotType.BANDEJA, 9f, 7f, 2.3f, 162f, 13.4f, 5.5f, 68f),
        Golpe(2, ShotType.BANDEJA, 7f, 18f, 0.3f, 148f, 12.5f, 4.2f, 51f),
        Golpe(3, ShotType.BANDEJA, 6f, 4f, 0.2f, 117f, 11.0f, 3.6f, 31f),
        Golpe(4, ShotType.BANDEJA, 4f, 17f, 0.7f, 134f, 10.1f, 4.1f, 42f),
        Golpe(5, ShotType.BANDEJA, 12f, 20f, -0.3f, 151f, 10.9f, 3.4f, 52f),
        // 6-10 víbora — cortadas: axial +2,8..+6,0. La altura NO las separa de las
        // bandejas de este jugador; la pronación sí, y limpio.
        Golpe(6, ShotType.VIBORA, -11f, 19f, 6.0f, 228f, 13.7f, 7.2f, 62f),
        Golpe(7, ShotType.VIBORA, 4f, 17f, 6.0f, 223f, 10.9f, 7.7f, 66f),
        Golpe(8, ShotType.VIBORA, 5f, 6f, 3.3f, 129f, 10.4f, 7.1f, 52f),
        Golpe(9, ShotType.VIBORA, 14f, 18f, 2.8f, 161f, 10.0f, 6.8f, 64f),
        Golpe(10, ShotType.VIBORA, 21f, 29f, 4.0f, 199f, 10.8f, 5.8f, 93f),
        // 11-15 remate
        Golpe(11, ShotType.SMASH, -13f, 27f, 2.5f, 241f, 17.2f, 11.5f, 59f),
        Golpe(12, ShotType.SMASH, -19f, 31f, 0.7f, 101f, 12.9f, 6.9f, 45f),
        Golpe(13, ShotType.SMASH, -34f, 10f, 0.8f, 188f, 10.7f, 6.4f, 29f),
        Golpe(14, ShotType.SMASH, -44f, 14f, 1.2f, 231f, 15.3f, 8.2f, 54f),
        Golpe(15, ShotType.SMASH, -41f, 15f, 1.3f, 304f, 16.0f, 6.3f, 60f),
        // 16-20 derecha
        Golpe(16, ShotType.FOREHAND, -41f, -31f, 2.7f, 40f, 9.1f, 7.1f, -1f),
        Golpe(17, ShotType.FOREHAND, -27f, -27f, 6.7f, 80f, 15.2f, 10.9f, 11f),
        Golpe(18, ShotType.FOREHAND, -40f, -25f, 8.0f, 182f, 19.5f, 11.6f, 33f),
        Golpe(19, ShotType.FOREHAND, -41f, -27f, 1.9f, 44f, 10.7f, 8.7f, -1f),
        Golpe(20, ShotType.FOREHAND, -37f, -54f, 8.1f, 106f, 15.6f, 7.3f, 8f),
        // 21-25 revés
        Golpe(21, ShotType.BACKHAND, -62f, -71f, -3.4f, 74f, 10.2f, -6.0f, -8f),
        Golpe(22, ShotType.BACKHAND, -61f, -48f, -7.0f, 144f, 13.6f, -9.7f, -18f),
        Golpe(23, ShotType.BACKHAND, -72f, -56f, -6.1f, 107f, 14.0f, -10.6f, -18f),
        Golpe(24, ShotType.BACKHAND, -73f, -54f, -6.8f, 124f, 12.6f, -9.8f, -17f),
        Golpe(25, ShotType.BACKHAND, -66f, -70f, -3.0f, 41f, 7.9f, -6.6f, 7f),
        // 26-30 volea de revés
        Golpe(26, ShotType.BACKHAND_VOLLEY, 1f, -14f, -1.9f, 89f, 14.7f, -4.2f, 40f),
        Golpe(27, ShotType.BACKHAND_VOLLEY, -52f, -7f, -3.1f, 301f, 16.6f, -5.5f, 33f),
        Golpe(28, ShotType.BACKHAND_VOLLEY, 6f, -9f, -1.1f, 85f, 14.7f, -3.4f, 39f),
        Golpe(29, ShotType.BACKHAND_VOLLEY, 2f, -18f, -2.9f, 101f, 15.1f, -5.9f, 42f),
        Golpe(30, ShotType.BACKHAND_VOLLEY, -7f, -24f, -1.7f, 153f, 14.9f, -2.5f, 13f),
        // 31-35 volea de derecha
        Golpe(31, ShotType.FOREHAND_VOLLEY, -12f, -36f, 2.9f, 61f, 8.8f, 7.4f, 24f),
        Golpe(32, ShotType.FOREHAND_VOLLEY, -20f, -37f, 4.9f, 98f, 10.4f, 9.8f, 34f),
        Golpe(33, ShotType.FOREHAND_VOLLEY, -27f, -41f, 3.3f, 66f, 8.4f, 7.7f, 19f),
        Golpe(34, ShotType.FOREHAND_VOLLEY, -20f, -30f, 2.8f, 79f, 9.2f, 6.8f, 33f),
        Golpe(35, ShotType.FOREHAND_VOLLEY, -29f, -46f, 3.0f, 48f, 9.5f, 8.8f, 12f),
        // 36-40 saque — la firma nueva: preparación en alto (+10..+27), impacto a la
        // cintura (−13..+3) y pronación de derecha. Con la firma vieja solo salía el 36.
        Golpe(36, ShotType.SERVE, 27f, -2f, 7.1f, 299f, 15.2f, 8.5f, 49f),
        Golpe(37, ShotType.SERVE, 24f, 3f, 5.7f, 178f, 13.9f, 9.2f, 25f),
        Golpe(38, ShotType.SERVE, 19f, -13f, 4.9f, 313f, 17.2f, 7.8f, 39f),
        Golpe(39, ShotType.SERVE, 21f, -3f, 4.4f, 107f, 9.9f, 6.2f, 56f),
        Golpe(40, ShotType.SERVE, 10f, -5f, 4.0f, 227f, 9.0f, 7.0f, 43f),
    )

    private val etiquetados = tanda.map { it.real to it.rasgos() }

    private fun aciertos(classifier: ShotClassifier, golpes: List<Golpe> = tanda): Int =
        golpes.count { classifier.classify(it.rasgos()).type == it.real }

    private fun familia(tipo: ShotType) = when (tipo) {
        ShotType.SMASH, ShotType.BANDEJA, ShotType.VIBORA -> "alto"
        ShotType.FOREHAND_VOLLEY, ShotType.BACKHAND_VOLLEY -> "volea"
        ShotType.FOREHAND, ShotType.BACKHAND -> "fondo"
        else -> "saque"
    }

    private val deFabrica = ShotClassifier()

    @Test
    fun `los cinco saques salen con los umbrales de fabrica`() {
        // La firma del brazo armado: es la aportación universal de esta tanda, no
        // depende de calibrar. Antes de ella salía un saque de cinco.
        val saques = tanda.filter { it.real == ShotType.SERVE }
        assertTrue(
            saques.all { deFabrica.classify(it.rasgos()).type == ShotType.SERVE },
            "algún saque no salió: " +
                saques.map { "${it.n}=${deFabrica.classify(it.rasgos()).type}" },
        )
    }

    @Test
    fun `una volea con mucho acompanamiento sigue siendo volea`() {
        // La 27 barrió 301° con la pala quieta (3,1 de axial): el techo viejo de 210°
        // la convertía en revés.
        val volea = tanda.first { it.n == 27 }
        assertTrue(deFabrica.classify(volea.rasgos()).type == ShotType.BACKHAND_VOLLEY)
    }

    @Test
    fun `de fabrica el suelo es 26 de 40`() {
        // Sin calibrar, las fronteras de elevación de este jugador no son las de
        // fábrica y se paga: las bandejas bajas salen como voleas o víboras. Este suelo
        // documenta el punto de partida; el de verdad es el test de calibración.
        assertTrue(aciertos(deFabrica) >= 26, "de fábrica: ${aciertos(deFabrica)}/40")
    }

    @Test
    fun `el calibrador aprende las fronteras de este jugador`() {
        val resultado = ThresholdCalibrator.calibrar(etiquetados)
        val calibracion = resultado.calibracion

        // La puerta de golpe alto baja al hueco real de esta tanda: el bajo más alto
        // impactó a +3 (un saque) y el alto más bajo a +4 (una bandeja).
        val puerta = assertNotNull(calibracion.overheadElevationDeg)
        assertTrue(puerta in 3f..4f, "puerta: $puerta")

        // Bandeja/víbora por pronación: la altura no separa a este jugador (medianas
        // 17 contra 18) y el efecto sí (0,3 contra 4,0).
        assertNull(calibracion.viboraElevationDeg)
        val axial = assertNotNull(calibracion.viboraAxialRadS)
        assertTrue(axial in 1.5f..3f, "frontera de víbora: $axial")

        // La validación por acierto tiene que tirar los umbrales que aquí estorban: la
        // preparación calibraría a +20°, que es donde este jugador arma los SAQUES, y
        // el umbral de smash a 13,1, que convertiría una víbora de pico 13,7 en remate.
        assertNull(calibracion.prepOverheadElevationDeg)
        assertNull(calibracion.smashPeakGyroRadS)
    }

    @Test
    fun `calibrado, el acierto sube de 26 a 32 de 40`() {
        val resultado = ThresholdCalibrator.calibrar(etiquetados)
        val calibrado = ShotClassifier(DetectorConfig.DEFAULT.aplicando(resultado.calibracion))

        assertTrue(
            resultado.aciertoDespues > resultado.aciertoAntes,
            "antes ${resultado.aciertoAntes}, después ${resultado.aciertoDespues}",
        )
        assertTrue(aciertos(calibrado) >= 32, "calibrado: ${aciertos(calibrado)}/40")

        // Las diez bandejas y víboras que de fábrica salían 4/10, calibradas 9/10.
        val altosDeControl = tanda.filter {
            it.real == ShotType.BANDEJA || it.real == ShotType.VIBORA
        }
        assertTrue(
            aciertos(calibrado, altosDeControl) >= 9,
            "bandejas y víboras: ${aciertos(calibrado, altosDeControl)}/10",
        )
    }

    @Test
    fun `calibrado, por familias no baja de 35 de 40`() {
        // Los cinco que quedan fuera son los honestamente ambiguos: dos derechas
        // compactas (40-44° de barrido, pala quieta) y dos reveses bajos que miden
        // EXACTAMENTE como voleas, y una volea con 4,9 de efecto que mide como derecha.
        // Eso ya no lo separa ningún umbral: es el terreno del modelo entrenado.
        val resultado = ThresholdCalibrator.calibrar(etiquetados)
        val calibrado = ShotClassifier(DetectorConfig.DEFAULT.aplicando(resultado.calibracion))
        val buenas = tanda.count {
            familia(calibrado.classify(it.rasgos()).type) == familia(it.real)
        }
        assertTrue(buenas >= 35, "por familias: $buenas/40")
    }
}
