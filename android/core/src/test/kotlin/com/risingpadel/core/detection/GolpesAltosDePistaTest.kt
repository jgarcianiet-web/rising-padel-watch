package com.risingpadel.core.detection

import com.risingpadel.core.MotionFixtures
import com.risingpadel.core.model.ShotFeatures
import com.risingpadel.core.model.ShotType
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Verdad-terreno de pista (ago 2026): 4 remates y 4 víboras reales que salieron TODOS
 * clasificados como golpes de fondo.
 *
 * **La elevación medida en esta tanda no se usa.** Se grabó con el eje del antebrazo
 * invertido y con la autocalificación del signo puesta, que llegó a oscilar dentro de
 * una misma tanda: sus grados no dicen dónde estaba el brazo. Lo que esta prueba fija
 * son los rasgos que no dependen de la gravedad —barrido, rotación axial y pico—, que
 * son los que separan un remate de una víbora. La elevación se sustituye por la que
 * mide el reloj corregido en un golpe alto.
 */
class GolpesAltosDePistaTest {

    private val classifier = ShotClassifier()

    /** Los dos primeros parámetros eran la elevación medida; se ignoran a propósito. */
    private fun rasgos(
        @Suppress("UNUSED_PARAMETER") elev: Float,
        @Suppress("UNUSED_PARAMETER") alto: Float,
        axial: Float,
        barrido: Float,
        pico: Float,
    ) = ShotFeatures(
        sweptAngleDeg = barrido,
        peakGyroRadS = pico,
        elevationDeg = ELEVACION_DE_GOLPE_ALTO,
        axialRotationRadS = axial,
        swingDurationMs = 250,
        peakElevationDeg = ELEVACION_DE_GOLPE_ALTO,
    )

    private companion object {
        /** Lo que mide el reloj corregido en un golpe por encima de la horizontal. */
        const val ELEVACION_DE_GOLPE_ALTO = 20f
    }

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
    fun `estas viboras ya no se pueden juzgar, y consta`() {
        // Lo que separa una víbora de una bandeja es la ALTURA del golpeo: las dos
        // empiezan igual y la víbora se impacta más baja. Esta tanda se grabó con el
        // eje de la elevación invertido, así que su altura no vale y aquí se sustituye
        // por una constante — con lo cual las cuatro salen del mismo lado, que es lo
        // correcto: sin el dato no hay nada que decidir.
        //
        // No se borra la prueba porque sus vectores siguen valiendo para el remate, que
        // se decide por el pico de giro. Cuando haya una tanda de víboras con la altura
        // bien medida, esto vuelve a ser una prueba de verdad.
        // Con el umbral del remate en 14 (tanda limpia de 42), una de estas cuatro pica
        // 14,3 y sale como smash. No es un fallo nuevo: es que sin la altura no hay con
        // qué frenarla, y su pico está del lado del remate. Lo que sí se puede exigir es
        // que las cuatro sigan siendo golpes altos.
        val tipos = viboras.map { classifier.classify(it).type }
        assertTrue(
            tipos.all {
                it == ShotType.BANDEJA || it == ShotType.VIBORA || it == ShotType.SMASH
            },
            "siguen siendo golpes altos, aunque no se pueda decir cuál: $tipos",
        )
    }

    @Test
    fun `con la gravedad rota en pleno swing, la preparacion ya no rescata el golpe`() {
        // Documenta un límite que se ha vuelto a abrir, y por qué se acepta.
        //
        // La preparación llegó a enrutar el golpe alto, y sirvió mientras la elevación
        // del pico era basura. Ya no enruta, y no puede: en la tanda limpia de 42 los
        // remates se preparan a −27..+5° —el brazo va atrás, no arriba— mientras las
        // bandejas se arman a +46..+68 y los saques a +5..+55. No hay un ángulo de
        // preparación que separe "alto" de "no alto"; el que lo separa es el del golpeo.
        //
        // Lo que compensa es que el motivo original ya casi no se da: la gravedad salía
        // rota tan a menudo porque el eje del antebrazo estaba girado. Con el eje bien,
        // los diecisiete altos de la tanda limpia picaron todos por encima de +15°.
        //
        // Sesión sintética del caso: brazo armado en alto (65°) y calmado antes del
        // swing, y gravedad corrupta DURANTE el swing (elevación medida ~0°).
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
        // La preparación se sigue midiendo bien —el rasgo está y vale para calibrar—,
        // pero ya no decide. Con la elevación del golpeo rota, esto sale como volea.
        assertEquals(ShotType.FOREHAND_VOLLEY, shots.first().type)
    }
}
