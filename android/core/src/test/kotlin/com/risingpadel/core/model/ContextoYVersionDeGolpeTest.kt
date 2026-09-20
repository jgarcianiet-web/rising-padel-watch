package com.risingpadel.core.model

import com.risingpadel.core.MotionFixtures
import com.risingpadel.core.detection.ModeloEntrenado
import com.risingpadel.core.score.MatchScore
import com.risingpadel.core.score.Side
import com.risingpadel.core.session.SessionRecorder
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Lo que el §36 del documento de producto pide que esté en el dato **desde el
 * principio**, porque no se puede rellenar después: de qué versión del clasificador
 * salió cada golpe, y en qué punto del partido ocurrió.
 *
 * Hoy casi nada de la app usa estos campos. Están aquí porque el día que hagan falta
 * —la secuencia de un punto, el cruce con el vídeo, comparar el historial entre dos
 * versiones del modelo— los datos de ese día ya tendrán meses de antigüedad, y el punto
 * en el que ocurrió un golpe de hace tres meses no se recupera de ninguna parte.
 */
class ContextoYVersionDeGolpeTest {

    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    private fun recorder() = SessionRecorder(
        source = SourceInfo(Platform.WATCHOS, "test", "1.0"),
        sessionIdProvider = { "sesion-1" },
    )

    /** Un golpe suelto, con su reposo previo para que el detector arranque limpio. */
    private fun unGolpe(recorder: SessionRecorder): Shot? {
        var golpe: Shot? = null
        (MotionFixtures.rest(0, 400) + MotionFixtures.forehand(400)).forEach { muestra ->
            recorder.onMotion(muestra)?.let { golpe = it }
        }
        return golpe
    }

    // MARK: Identidad

    @Test
    fun `el id del golpe sale de la sesion y el instante, sin guardar nada`() {
        val recorder = recorder()
        recorder.start(startedAtEpochMs = 0, monotonicMs = 0)
        val golpe = assertNotNull(unGolpe(recorder))
        assertEquals("sesion-1:${golpe.offsetMs}", golpe.idEn("sesion-1"))
    }

    @Test
    fun `dos golpes de la misma sesion no comparten id`() {
        // El detector tiene 320 ms de tiempo muerto tras cada impacto, así que dos
        // golpes no caben en el mismo milisegundo. Es lo que hace innecesario guardar
        // un UUID en cada uno de los 300 golpeos de un partido.
        val recorder = recorder()
        recorder.start(startedAtEpochMs = 0, monotonicMs = 0)
        val golpes = mutableListOf<Shot>()
        val muestras = MotionFixtures.rest(0, 400) +
            MotionFixtures.forehand(400) +
            MotionFixtures.rest(1_000, 400) +
            MotionFixtures.forehand(1_400)
        muestras.forEach { muestra -> recorder.onMotion(muestra)?.let { golpes.add(it) } }

        assertTrue(golpes.size >= 2, "hacen falta dos golpes para la prueba: ${golpes.size}")
        val ids = golpes.map { it.idEn("sesion-1") }
        assertEquals(ids.size, ids.toSet().size, "ids repetidos: $ids")
    }

    // MARK: Versión del clasificador

    @Test
    fun `cada golpe apunta que version lo clasifico`() {
        val recorder = recorder()
        recorder.start(startedAtEpochMs = 0, monotonicMs = 0)
        assertEquals(ModeloEntrenado.VERSION, assertNotNull(unGolpe(recorder)).modelVersion)
    }

    @Test
    fun `la version no puede quedarse vacia`() {
        // Si alguien la borra, el historial pierde la única forma de saber con qué
        // criterio se midió cada golpe — y eso no se recupera.
        assertTrue(ModeloEntrenado.VERSION.isNotBlank())
    }

    // MARK: Contexto de juego

    @Test
    fun `sin marcador ni pulso no se guarda contexto`() {
        // Un contexto con los cuatro campos vacíos solo ocuparía sitio en el fichero,
        // en el backup y en cada subida.
        val recorder = recorder()
        recorder.start(startedAtEpochMs = 0, monotonicMs = 0)
        assertNull(assertNotNull(unGolpe(recorder)).context)
    }

    @Test
    fun `con marcador, el golpe sabe en que punto, juego y set cayo`() {
        val recorder = recorder()
        recorder.start(startedAtEpochMs = 0, monotonicMs = 0)

        var marcador = MatchScore()
        repeat(3) {
            val siguiente = marcador.pointTo(Side.US)
            recorder.onScoreChanged(marcador, siguiente, monotonicMs = 10L * it)
            marcador = siguiente
        }
        recorder.score = marcador

        val contexto = assertNotNull(assertNotNull(unGolpe(recorder)).context)
        assertEquals(4, contexto.pointIndex, "tres puntos jugados: este es el cuarto")
        assertEquals(1, contexto.gameIndex)
        assertEquals(1, contexto.setIndex)
    }

    @Test
    fun `el pulso del momento viaja con el golpe`() {
        val recorder = recorder()
        recorder.start(startedAtEpochMs = 0, monotonicMs = 0)
        recorder.onHeartRate(148, monotonicMs = 0)
        assertEquals(148, assertNotNull(assertNotNull(unGolpe(recorder)).context).heartRateBpm)
    }

    @Test
    fun `el contexto no toca los rasgos, que siguen siendo funcion pura de la senal`() {
        // Es la razón de que el contexto viva aparte de ShotFeatures: una tanda grabada
        // tiene que poder reclasificarse mañana con otro modelo y dar exactamente lo
        // mismo. Si el marcador entrara en los rasgos, el mismo movimiento daría
        // resultados distintos según el tanteo y el reentrenamiento sería
        // irreproducible.
        val sinMarcador = recorder().apply { start(0, 0) }
        val conMarcador = recorder().apply {
            start(0, 0)
            score = MatchScore().pointTo(Side.US)
        }
        val golpeA = assertNotNull(unGolpe(sinMarcador))
        val golpeB = assertNotNull(unGolpe(conMarcador))

        assertEquals(golpeA.features, golpeB.features)
        assertEquals(golpeA.type, golpeB.type)
        // Y sin embargo el contexto SÍ cambia: es lo que prueba que están separados.
        assertNull(golpeA.context)
        assertNotNull(golpeB.context)
    }

    // MARK: Compatibilidad hacia atrás

    @Test
    fun `una sesion vieja sin contexto ni version se lee igual`() {
        // El backup de quien grabó antes de que existieran estos campos no puede fallar
        // al abrirse.
        val viejo = """
            {"offsetMs":1200,"type":"FOREHAND","racketSpeedKmh":42.0,"impactG":5.1,
             "confidence":0.9,
             "features":{"sweptAngleDeg":180.0,"peakGyroRadS":15.0,"elevationDeg":-30.0,
                         "axialRotationRadS":8.0,"swingDurationMs":300}}
        """.trimIndent()
        val golpe = json.decodeFromString(Shot.serializer(), viejo)
        assertNull(golpe.context)
        assertNull(golpe.modelVersion)
        assertEquals(ShotType.FOREHAND, golpe.type)
    }

    @Test
    fun `el golpe con contexto va y vuelve por JSON`() {
        val original = Shot(
            offsetMs = 1_200,
            type = ShotType.BANDEJA,
            racketSpeedKmh = 40f,
            impactG = 5f,
            confidence = 0.8f,
            features = ShotFeatures(
                sweptAngleDeg = 200f,
                peakGyroRadS = 12f,
                elevationDeg = 40f,
                axialRotationRadS = 1f,
                swingDurationMs = 300,
            ),
            context = ShotContext(pointIndex = 27, gameIndex = 5, setIndex = 2, heartRateBpm = 148),
            modelVersion = "heuristica-2026.09",
        )
        val texto = json.encodeToString(Shot.serializer(), original)
        assertEquals(original, json.decodeFromString(Shot.serializer(), texto))
    }
}
