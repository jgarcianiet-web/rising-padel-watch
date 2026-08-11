package com.risingpadel.core.detection

import com.risingpadel.core.model.ShotFeatures
import com.risingpadel.core.model.ShotType
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ModeloDeGolpesTest {

    private fun rasgos(
        barrido: Float = 100f,
        pico: Float = 10f,
        alto: Float = 0f,
        axial: Float = 0f,
    ) = ShotFeatures(
        sweptAngleDeg = barrido,
        peakGyroRadS = pico,
        elevationDeg = alto,
        axialRotationRadS = axial,
        swingDurationMs = 300,
        peakElevationDeg = alto,
    )

    /**
     * Dos árboles de un nodo de corte y dos hojas, cortando por la elevación (rasgo 5).
     * Uno vota bien y el otro al revés, para poder comprobar los empates y los votos.
     */
    private fun bosque(arbolesDeAcuerdo: Int, arbolesEnContra: Int): ModeloDeGolpes {
        val rasgo = mutableListOf<Int>()
        val umbral = mutableListOf<Float>()
        val izq = mutableListOf<Int>()
        val der = mutableListOf<Int>()
        val hoja = mutableListOf<Int>()
        val raices = mutableListOf<Int>()

        repeat(arbolesDeAcuerdo + arbolesEnContra) { i ->
            val alReves = i >= arbolesDeAcuerdo
            val base = rasgo.size
            raices.add(base)
            // nodo de corte
            rasgo.add(5); umbral.add(14f); izq.add(base + 1); der.add(base + 2); hoja.add(-1)
            // hoja izquierda (elevación baja)
            rasgo.add(-1); umbral.add(0f); izq.add(-1); der.add(-1); hoja.add(if (alReves) 1 else 0)
            // hoja derecha (elevación alta)
            rasgo.add(-1); umbral.add(0f); izq.add(-1); der.add(-1); hoja.add(if (alReves) 0 else 1)
        }

        return ModeloDeGolpes(
            clases = listOf(ShotType.FOREHAND, ShotType.BANDEJA),
            raices = raices.toIntArray(),
            rasgo = rasgo.toIntArray(),
            umbral = umbral.toFloatArray(),
            izquierda = izq.toIntArray(),
            derecha = der.toIntArray(),
            hoja = hoja.toIntArray(),
            muestras = 100,
            aciertoFuera = 0.8f,
        )
    }

    @Test
    fun `el bosque recorre el arbol y vota`() {
        val modelo = bosque(arbolesDeAcuerdo = 5, arbolesEnContra = 0)
        assertEquals(ShotType.FOREHAND, modelo.clasificar(rasgos(alto = -30f))?.type)
        assertEquals(ShotType.BANDEJA, modelo.clasificar(rasgos(alto = 45f))?.type)
    }

    @Test
    fun `la confianza es la fraccion de arboles que votaron lo mismo`() {
        val modelo = bosque(arbolesDeAcuerdo = 3, arbolesEnContra = 1)
        val salida = assertNotNull(modelo.clasificar(rasgos(alto = 45f)))
        assertEquals(ShotType.BANDEJA, salida.type)
        assertEquals(0.75f, salida.confidence, 0.001f)
    }

    @Test
    fun `un modelo sin arboles no contesta`() {
        val vacio = ModeloDeGolpes(
            clases = emptyList(),
            raices = intArrayOf(), rasgo = intArrayOf(), umbral = floatArrayOf(),
            izquierda = intArrayOf(), derecha = intArrayOf(), hoja = intArrayOf(),
            muestras = 0, aciertoFuera = 0f,
        )
        assertNull(vacio.clasificar(rasgos()))
    }

    @Test
    fun `el orden de los rasgos es un contrato con el generador`() {
        // Si esta lista cambia y no cambia la de `tools/exportar_modelo.py`, el modelo
        // lee los números cambiados de sitio y falla en silencio — la peor forma de
        // fallar, porque los golpes se siguen clasificando, solo que mal.
        assertEquals(
            listOf(
                "sweptAngleDeg", "peakGyroRadS", "elevationDeg", "axialRotationRadS",
                "swingDurationMs", "peakElevationDeg", "prepElevationDeg",
                "peakAxialRotationRadS", "elevationDropDeg",
            ),
            ModeloDeGolpes.RASGOS,
        )
        assertEquals(ModeloDeGolpes.RASGOS.size, ModeloDeGolpes.vectorDe(rasgos()).size)
    }

    @Test
    fun `los rasgos que faltan entran como cero, no tiran el golpe`() {
        // Un golpe sin elevación de preparación hay que clasificarlo igual.
        val vector = ModeloDeGolpes.vectorDe(rasgos())
        assertEquals(0f, vector[6])
        assertEquals(0f, vector[7])
        assertEquals(0f, vector[8])
    }

    @Test
    fun `sin modelo de fabrica manda la heuristica`() {
        // Mientras no haya tandas de varias personas, la app va con la heurística. Un
        // modelo entrenado con una sola muñeca aprende esa muñeca, no el golpe.
        assertNull(ModeloEntrenado.actual)
        val classifier = ShotClassifier()
        assertEquals(
            ShotType.BANDEJA,
            classifier.classify(rasgos(barrido = 200f, pico = 11f, alto = 50f)).type,
        )
    }

    @Test
    fun `el umbral de votos deja sitio a la heuristica`() {
        // No es desconfianza gratuita: un golpe que el modelo no tiene claro es justo
        // el que hay que poder explicar, y explicar es lo que sabe hacer la heurística.
        assertTrue(ModeloEntrenado.MIN_VOTOS in 0.5f..0.9f)
    }
}
