package com.risingpadel.core.detection

import com.risingpadel.core.model.ShotFeatures
import com.risingpadel.core.model.ShotType
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Verdad-terreno de pista (ago 2026): una tanda de 8 voleas de revés reales. Con la
 * regla vieja, tres caían como golpes de fondo (barridos de 147-170°) y otras tres
 * se ejecutaban por confianza baja (la fórmula castigaba el axial bajo, que es justo
 * lo que define una volea). Los vectores son los medidos, tal cual salieron del
 * diagnóstico del reloj.
 */
class VoleasDePistaTest {

    private val classifier = ShotClassifier()

    private fun rasgos(
        elev: Float, alto: Float, axial: Float, barrido: Float, pico: Float
    ) = ShotFeatures(
        sweptAngleDeg = barrido,
        peakGyroRadS = pico,
        elevationDeg = elev,
        axialRotationRadS = axial,
        swingDurationMs = 250,
        peakElevationDeg = alto,
    )

    private val voleasReales = listOf(
        rasgos(-6f, -2f, -0.7f, 62f, 11.9f),
        rasgos(-7f, -3f, -1.0f, 54f, 10.0f),
        rasgos(13f, 16f, -1.2f, 61f, 10.0f),
        rasgos(21f, 41f, -3.8f, 147f, 15.7f),
        rasgos(7f, 14f, -0.3f, 47f, 10.1f),
        rasgos(-5f, 3f, -0.4f, 65f, 10.9f),
        rasgos(-31f, -24f, 1.9f, 165f, 10.2f),
        rasgos(-6f, 7f, -0.3f, 170f, 14.7f),
    )

    @Test
    fun `ninguna volea real cae como golpe de fondo`() {
        val tipos = voleasReales.map { classifier.classify(it).type }
        assertTrue(
            tipos.none { it == ShotType.FOREHAND || it == ShotType.BACKHAND },
            "una volea clasificada de fondo engaña más que un 'sin clasificar': $tipos",
        )
    }

    @Test
    fun `la gran mayoria se reconoce como volea con confianza suficiente`() {
        val clasificaciones = voleasReales.map { classifier.classify(it) }
        val voleas = clasificaciones.count {
            it.type == ShotType.FOREHAND_VOLLEY || it.type == ShotType.BACKHAND_VOLLEY
        }
        // 7 de 8 como mínimo: la nº 4 (axial 3.8, al borde del umbral) puede quedar
        // en unknown, que es un fallo honesto — antes en silencio que inventado.
        assertTrue(voleas >= 7, "solo $voleas de 8 voleas reconocidas: $clasificaciones")
    }

    @Test
    fun `las de axial claramente negativo salen de reves`() {
        // Las de axial cerca de cero pueden errar el lado; las claras, no.
        for (rasgo in voleasReales.filter { it.axialRotationRadS <= -0.7f }) {
            val tipo = classifier.classify(rasgo).type
            if (tipo != ShotType.UNKNOWN) {
                assertEquals(ShotType.BACKHAND_VOLLEY, tipo, "rasgos: $rasgo")
            }
        }
    }

    @Test
    fun `una derecha de fondo real sigue siendo derecha`() {
        // De la misma pista: barrido 116 con axial 7.9 — efecto de sobra, nada de volea.
        val derecha = rasgos(elev = -46f, alto = -40f, axial = 7.9f, barrido = 116f, pico = 12.7f)
        assertEquals(ShotType.FOREHAND, classifier.classify(derecha).type)
    }
}
