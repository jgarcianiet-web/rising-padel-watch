package com.risingpadel.core.analytics

import com.risingpadel.core.model.PadelSession
import com.risingpadel.core.model.Platform
import com.risingpadel.core.model.Shot
import com.risingpadel.core.model.ShotFeatures
import com.risingpadel.core.model.ShotType
import com.risingpadel.core.model.SessionReview
import com.risingpadel.core.model.SourceInfo
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class DetectorAccuracyTest {

    private fun shot(type: ShotType) = Shot(
        offsetMs = 0,
        type = type,
        racketSpeedKmh = 50f,
        impactG = 5f,
        confidence = 0.9f,
        features = ShotFeatures(
            sweptAngleDeg = 200f,
            peakGyroRadS = 20f,
            elevationDeg = 20f,
            axialRotationRadS = 3f,
            swingDurationMs = 300,
        ),
    )

    private fun sesion(
        detectados: Map<ShotType, Int>,
        corregidos: Map<ShotType, Int>? = null,
    ) = PadelSession(
        sessionId = "s-${detectados.hashCode()}-${corregidos.hashCode()}",
        source = SourceInfo(Platform.WATCHOS, "Watch", "1.0"),
        startedAtEpochMs = 0,
        endedAtEpochMs = 60_000,
        profile = com.risingpadel.core.model.PlayerProfile(),
        shots = detectados.flatMap { (tipo, n) -> List(n) { shot(tipo) } },
        review = corregidos?.let {
            SessionReview(
                correctedCounts = it.mapKeys { (tipo, _) -> tipo.wireName },
                reviewedAtEpochMs = 1,
            )
        },
    )

    /** Un par (lo que era, lo que dijo el reloj), repetido [veces]. */
    private fun pares(real: ShotType, dicho: ShotType, veces: Int) =
        List(veces) { real to dicho }

    @Test
    fun `sin nada que mirar el informe lo dice en vez de inventar un cero`() {
        val informe = InformeDePrecision.de(emptyList(), emptyList())
        assertTrue(!informe.hayDatos)
        assertNull(informe.aciertoGlobal)
        assertNull(informe.sinClasificar)
    }

    @Test
    fun `el acierto global sale de las tandas, golpe a golpe`() {
        val tandas = pares(ShotType.FOREHAND, ShotType.FOREHAND, 18) +
            pares(ShotType.FOREHAND, ShotType.BACKHAND, 2)

        val informe = InformeDePrecision.de(emptyList(), tandas)

        assertEquals(0.9f, informe.aciertoGlobal!!, 0.01f)
        assertEquals(20, informe.golpesEnTandas)
    }

    @Test
    fun `cada golpe dice con cual se le confunde`() {
        // Las víboras del reloj salen casi siempre como smash: el fallo real de pista.
        val tandas = pares(ShotType.VIBORA, ShotType.SMASH, 14) +
            pares(ShotType.VIBORA, ShotType.BANDEJA, 2) +
            pares(ShotType.VIBORA, ShotType.VIBORA, 4)

        val vibora = InformeDePrecision.de(emptyList(), tandas)
            .golpes.first { it.type == ShotType.VIBORA }

        assertEquals(ShotType.SMASH, vibora.seConfundeCon)
        assertEquals(14, vibora.vecesConfundido)
        assertEquals(0.2f, vibora.aciertoEnTandas!!, 0.01f)
    }

    @Test
    fun `un golpe que no falla nunca no tiene con quien confundirse`() {
        val derecha = InformeDePrecision.de(
            emptyList(),
            pares(ShotType.FOREHAND, ShotType.FOREHAND, 20),
        ).golpes.first { it.type == ShotType.FOREHAND }

        assertNull(derecha.seConfundeCon)
        assertEquals(0, derecha.vecesConfundido)
        assertEquals(1f, derecha.aciertoEnTandas!!, 0.001f)
    }

    @Test
    fun `los sin clasificar se cuentan aparte, no como confusion`() {
        val tandas = pares(ShotType.SMASH, ShotType.UNKNOWN, 5) +
            pares(ShotType.SMASH, ShotType.SMASH, 15)

        val informe = InformeDePrecision.de(emptyList(), tandas)
        val smash = informe.golpes.first { it.type == ShotType.SMASH }

        assertEquals(0.25f, informe.sinClasificar!!, 0.01f)
        assertNull(smash.seConfundeCon, "rendirse no es confundirse con otro golpe")
        assertEquals(0.75f, smash.aciertoEnTandas!!, 0.01f)
    }

    @Test
    fun `el desvio de recuento sale de los partidos que el jugador corrigio`() {
        // El reloj contó 14 bandejas donde hubo 12: se pasa un 16,7%.
        val informe = InformeDePrecision.de(
            listOf(sesion(mapOf(ShotType.BANDEJA to 14), mapOf(ShotType.BANDEJA to 12))),
            emptyList(),
        )
        val bandeja = informe.golpes.first { it.type == ShotType.BANDEJA }

        assertEquals(1, informe.sesionesRevisadas)
        assertEquals(14, bandeja.contadosEnPartidos)
        assertEquals(12, bandeja.realesEnPartidos)
        assertEquals(2f / 12f, bandeja.desvioEnPartidos!!, 0.01f)
        assertNull(bandeja.aciertoEnTandas, "sin tandas de bandeja no hay acierto que dar")
    }

    @Test
    fun `una sesion sin revisar no cuenta como verdad`() {
        val informe = InformeDePrecision.de(
            listOf(sesion(mapOf(ShotType.FOREHAND to 30))),
            emptyList(),
        )
        assertEquals(0, informe.sesionesRevisadas)
        assertTrue(!informe.hayDatos, "contar los golpeos del reloj contra sí mismos no mide nada")
    }

    @Test
    fun `el peor golpe es el que hay que arreglar, y solo si se puede juzgar`() {
        val tandas = pares(ShotType.FOREHAND, ShotType.FOREHAND, 20) +
            pares(ShotType.VIBORA, ShotType.SMASH, 16) +
            pares(ShotType.VIBORA, ShotType.VIBORA, 4) +
            // Solo tres bandejas y todas mal: 0% de acierto, pero es una anécdota.
            pares(ShotType.BANDEJA, ShotType.SMASH, 3)

        val informe = InformeDePrecision.de(emptyList(), tandas)

        assertEquals(ShotType.VIBORA, informe.peorGolpe?.type)
        assertTrue(
            informe.golpes.first { it.type == ShotType.BANDEJA }.faltanTandas,
            "con tres golpes no se juzga a nadie",
        )
    }

    @Test
    fun `los golpes sin tandas suficientes son la lista de lo que hay que grabar`() {
        val informe = InformeDePrecision.de(
            emptyList(),
            pares(ShotType.FOREHAND, ShotType.FOREHAND, 20),
        )

        assertTrue(ShotType.FOREHAND !in informe.golpesSinTandas)
        assertTrue(ShotType.SMASH in informe.golpesSinTandas)
        assertTrue(ShotType.UNKNOWN !in informe.golpesSinTandas, "sin clasificar no se graba")
    }

    @Test
    fun `el orden pone delante lo que peor va y se puede juzgar`() {
        val tandas = pares(ShotType.FOREHAND, ShotType.FOREHAND, 20) +
            pares(ShotType.VIBORA, ShotType.SMASH, 16) +
            pares(ShotType.VIBORA, ShotType.VIBORA, 4) +
            pares(ShotType.BANDEJA, ShotType.BANDEJA, 3)

        val orden = InformeDePrecision.de(emptyList(), tandas).golpes.map { it.type }

        assertEquals(ShotType.VIBORA, orden.first())
        assertEquals(ShotType.BANDEJA, orden.last(), "lo que no se puede juzgar va al final")
    }
}
