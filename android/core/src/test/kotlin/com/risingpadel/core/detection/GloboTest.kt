package com.risingpadel.core.detection

import com.risingpadel.core.model.ShotFeatures
import com.risingpadel.core.model.ShotType
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * El globo: recorrido completo y sin velocidad.
 *
 * Este fichero documenta sobre todo **por qué el globo no tiene umbral de fábrica**.
 * Con las dos tandas limpias de pista parecía que sí lo tenía: ningún golpe bajo de los
 * 82 barría más de 135° picando menos de 13 rad/s, así que ahí cabía el globo sin pisar
 * a nadie. Al probarlo contra la tanda de ocho tipos —otro jugador— la región resultó
 * estar llena: sus bandejas y derechas barren 180-250° picando 10-11. "Lento" no es una
 * medida absoluta, es una medida de cada muñeca.
 *
 * Así que el globo funciona como la frontera bandeja/víbora: apagado de fábrica,
 * encendido por el calibrador con la tanda de globos del jugador.
 */
class GloboTest {

    private fun rasgos(
        barrido: Float,
        pico: Float,
        alto: Float = -30f,
        axial: Float = 1.5f,
        prep: Float = -35f,
    ) = ShotFeatures(
        sweptAngleDeg = barrido,
        peakGyroRadS = pico,
        elevationDeg = alto,
        axialRotationRadS = axial,
        swingDurationMs = 420,
        peakElevationDeg = alto,
        prepElevationDeg = prep,
    )

    /** Un jugador que ya grabó su tanda de globos: los suyos van por debajo de 12. */
    private val conGlobos = ShotClassifier(
        DetectorConfig.DEFAULT.copy(lobMaxPeakGyroRadS = 12f)
    )
    private val deFabrica = ShotClassifier()

    @Test
    fun `de fabrica el reloj no dice globo jamas`() {
        // Lo importante de todo el fichero. Sin la tanda del jugador no hay umbral
        // honesto, y un globo inventado se come golpes de fondo de medio mundo.
        assertNull(DetectorConfig.DEFAULT.lobMaxPeakGyroRadS)
        val candidatos = listOf(
            rasgos(barrido = 190f, pico = 9f),
            rasgos(barrido = 160f, pico = 11f),
            rasgos(barrido = 250f, pico = 7f),
        )
        assertTrue(candidatos.none { deFabrica.classify(it).type == ShotType.LOB })
    }

    @Test
    fun `con la tanda del jugador, un swing largo y lento sale globo`() {
        assertEquals(ShotType.LOB, conGlobos.classify(rasgos(barrido = 190f, pico = 9f)).type)
        assertEquals(ShotType.LOB, conGlobos.classify(rasgos(barrido = 160f, pico = 11f)).type)
    }

    @Test
    fun `el globo no tiene lado`() {
        // Se globea de derecha y de revés y sigue siendo el mismo golpe: la regla no
        // mira el signo del efecto, y no debe.
        assertEquals(
            ShotType.LOB, conGlobos.classify(rasgos(barrido = 175f, pico = 10f, axial = 3f)).type
        )
        assertEquals(
            ShotType.LOB, conGlobos.classify(rasgos(barrido = 175f, pico = 10f, axial = -3f)).type
        )
    }

    @Test
    fun `una derecha larga no es un globo, porque va rapida`() {
        // La derecha 18 de la tanda de 40: 182° picando 19,5.
        assertEquals(
            ShotType.FOREHAND,
            conGlobos.classify(rasgos(barrido = 182f, pico = 19.5f, axial = 8f)).type,
        )
    }

    @Test
    fun `una volea lenta no es un globo, porque es corta`() {
        // La volea de derecha 33 de la tanda de 40: 66° picando 8,4.
        assertEquals(
            ShotType.FOREHAND_VOLLEY,
            conGlobos.classify(rasgos(barrido = 66f, pico = 8.4f, axial = 3.3f)).type,
        )
    }

    @Test
    fun `un golpe alto lento sigue siendo alto`() {
        // Si el globo se preguntara antes que la puerta de altura, una bandeja de 200°
        // picando 11 se iría con él.
        val bandeja = rasgos(barrido = 200f, pico = 11f, alto = 50f, axial = 0.5f, prep = 55f)
        val tipo = conGlobos.classify(bandeja).type
        assertTrue(
            tipo == ShotType.BANDEJA || tipo == ShotType.VIBORA,
            "un golpe alto lento salió como $tipo",
        )
    }

    @Test
    fun `un saque con su firma sigue siendo saque`() {
        // El saque 40 de la tanda de 40 barrió 227° picando 9,0: largo y lento, dentro
        // de la región del globo. Lo salva que el saque se pregunta antes.
        val saque = rasgos(barrido = 227f, pico = 9.0f, alto = -5f, axial = 4.0f, prep = 10f)
        assertEquals(ShotType.SERVE, conGlobos.classify(saque).type)
    }

    @Test
    fun `el calibrador aprende el umbral de la tanda de globos`() {
        // Un jugador que globea a 8-9 rad/s y pega sus derechas y reveses a 15-17.
        val etiquetados =
            List(6) { i ->
                ShotType.LOB to rasgos(barrido = 170f + i, pico = 8f + i * 0.2f)
            } +
            List(6) { i ->
                ShotType.FOREHAND to rasgos(barrido = 120f + i, pico = 16f + i * 0.2f, axial = 8f)
            } +
            List(6) { i ->
                ShotType.BACKHAND to rasgos(barrido = 110f + i, pico = 15f + i * 0.2f, axial = -8f)
            }

        val calibracion = ThresholdCalibrator.calibrar(etiquetados).calibracion
        val umbral = assertNotNull(
            calibracion.lobMaxPeakGyroRadS,
            "con seis globos etiquetados el calibrador tiene que poder fijarlo",
        )
        assertTrue(umbral in 9f..15f, "el umbral debería caer entre las dos familias: $umbral")

        // Y con él puesto, los globos de ESE jugador salen.
        val conSuCalibracion = ShotClassifier(DetectorConfig.DEFAULT.aplicando(calibracion))
        assertEquals(
            ShotType.LOB, conSuCalibracion.classify(rasgos(barrido = 175f, pico = 8.5f)).type
        )
    }

    @Test
    fun `sin globos etiquetados el calibrador no se inventa el umbral`() {
        val sinGlobos = List(8) { ShotType.FOREHAND to rasgos(barrido = 120f, pico = 16f, axial = 8f) } +
            List(8) { ShotType.BACKHAND to rasgos(barrido = 110f, pico = 15f, axial = -8f) }
        assertNull(ThresholdCalibrator.calibrar(sinGlobos).calibracion.lobMaxPeakGyroRadS)
    }

    @Test
    fun `el globo tiene banda de nivel propia`() {
        assertNotNull(
            com.risingpadel.core.level.LevelConfig.DEFAULT_BANDS[ShotType.LOB],
            "sin banda, un globo no puntúa y desaparece del nivel",
        )
    }
}
