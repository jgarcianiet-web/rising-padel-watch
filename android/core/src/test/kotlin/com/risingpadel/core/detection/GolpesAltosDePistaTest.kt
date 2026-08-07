package com.risingpadel.core.detection

import com.risingpadel.core.MotionFixtures
import com.risingpadel.core.model.ShotFeatures
import com.risingpadel.core.model.ShotType
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Verdad-terreno de pista (ago 2026): 4 remates y 4 víboras reales que salieron TODOS
 * clasificados como golpes de fondo. La causa: durante un swing violento el filtro de
 * gravedad se corrompe y el pico de elevación medido salía a +3° o −41° — ningún
 * umbral sobre ese canal podía funcionar. El testigo honesto es la elevación de la
 * PREPARACIÓN (brazo calmado): nadie arma una derecha con el antebrazo al cielo.
 */
class GolpesAltosDePistaTest {

    private val classifier = ShotClassifier()

    /** Los vectores medidos, tal cual, más la preparación en alto que el rasgo nuevo
     *  habría capturado (el diagnóstico de entonces aún no la medía). */
    private fun rasgos(
        elev: Float, alto: Float, axial: Float, barrido: Float, pico: Float
    ) = ShotFeatures(
        sweptAngleDeg = barrido,
        peakGyroRadS = pico,
        elevationDeg = elev,
        axialRotationRadS = axial,
        swingDurationMs = 250,
        peakElevationDeg = alto,
        prepElevationDeg = 65f,
    )

    private val remates = listOf(
        rasgos(-11f, 3f, 5.2f, 291f, 21.4f),
        rasgos(-45f, -41f, -3.4f, 185f, 16.4f),
        rasgos(-19f, 4f, 0.6f, 189f, 17.9f),
        rasgos(-11f, 12f, 1.6f, 150f, 10.6f),
    )

    private val viboras = listOf(
        rasgos(-21f, -6f, -4.1f, 177f, 13.4f),
        rasgos(-29f, -10f, -4.9f, 178f, 13.2f),
        rasgos(-26f, 2f, -0.9f, 166f, 9.2f),
        rasgos(-34f, -5f, -4.4f, 214f, 14.3f),
    )

    @Test
    fun `con la preparacion en alto ningun golpe alto cae como golpe de fondo`() {
        val tipos = (remates + viboras).map { classifier.classify(it).type }
        assertTrue(
            tipos.none {
                it == ShotType.FOREHAND || it == ShotType.BACKHAND ||
                    it == ShotType.FOREHAND_VOLLEY || it == ShotType.BACKHAND_VOLLEY
            },
            "un remate clasificado de fondo engaña más que un 'sin clasificar': $tipos",
        )
    }

    @Test
    fun `los remates con violencia de remate salen como smash`() {
        // Con el umbral recalibrado a 16 (los reales picaron 10.6-21.4), los tres de
        // pico alto son smash; el de 10.6 no puede distinguirse de una bandeja con lo
        // que medimos hoy — fallo honesto.
        val tipos = remates.map { classifier.classify(it).type }
        assertTrue(tipos.count { it == ShotType.SMASH } >= 3, "tipos: $tipos")
    }

    @Test
    fun `las viboras con efecto claro salen como vibora`() {
        // Umbral recalibrado a 4 (las reales promediaron |4.1-5.4|; el 9 anterior era
        // inalcanzable). La de axial 0.9 cae a bandeja: sin efecto no hay víbora.
        val tipos = viboras.map { classifier.classify(it).type }
        assertTrue(tipos.count { it == ShotType.VIBORA } >= 3, "tipos: $tipos")
    }

    @Test
    fun `el detector mide la preparacion y esta enruta el golpe alto`() {
        // Sesión sintética del caso real: brazo armado en alto (65°) y calmado antes
        // del swing, y gravedad corrupta DURANTE el swing (elevación medida ~0°). Sin
        // el rasgo de preparación esto caía como golpe de fondo.
        val detector = ShotDetector()
        val samples = MotionFixtures.rest(0, 1_000, elevationDeg = 65f) +
            MotionFixtures.swing(
                startMs = 1_000,
                peakGyroRadS = 20f,
                swingDurationMs = 220,
                impactG = 8f,
                axialFraction = 0.2f,
                elevationDeg = 0f, // lo que "ve" el filtro corrupto en pleno swing
            )
        detector.reset(0)
        val shots = samples.mapNotNull { detector.process(it) }.toMutableList()
        detector.flush()?.let { shots.add(it) }

        assertEquals(1, shots.size)
        val features = shots.first().features
        assertTrue(
            (features.prepElevationDeg ?: -90f) > 45f,
            "la preparación debía medirse en alto: $features",
        )
        assertEquals(ShotType.SMASH, shots.first().type)
    }
}
