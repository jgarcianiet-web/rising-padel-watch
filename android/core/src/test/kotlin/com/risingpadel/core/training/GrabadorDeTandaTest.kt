package com.risingpadel.core.training

import com.risingpadel.core.MotionFixtures
import com.risingpadel.core.model.Platform
import com.risingpadel.core.model.ShotType
import com.risingpadel.core.model.SourceInfo
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * El contrato del grabador nuevo: **cada muestra que entra se guarda**, vea lo que vea
 * el detector.
 *
 * Nace de un fallo de pista real: la captura por ventanas solo guardaba lo que el
 * detector encontraba, y una tanda de derechas se quedó en cero sin explicación. El
 * detector pasa de portero a comentarista, y estas pruebas fijan que no pueda volver a
 * vetar nada.
 */
class GrabadorDeTandaTest {

    private fun grabador() = GrabadorDeTanda(
        source = SourceInfo(Platform.WATCHOS, "test", "1.0"),
        profile = com.risingpadel.core.model.PlayerProfile(),
        tandaIdProvider = { "t1" },
        nowEpochMs = { 1_700_000_000_000 },
    )

    @Test
    fun `guarda todas las muestras aunque el detector no vea nada`() {
        val g = grabador()
        g.start(0)
        // Reposo puro: el detector no va a ver ni un golpe. Antes esto acababa en un
        // fichero vacío; ahora es una tanda completa con cero golpes anotados.
        val muestras = MotionFixtures.rest(0, 2_000)
        muestras.forEach { g.onMotion(it) }

        assertEquals(muestras.size, g.muestras)
        assertEquals(0, g.golpes)
        val tanda = assertNotNull(g.stop())
        assertEquals(muestras.size, tanda.muestras)
        assertTrue(tanda.golpes.isEmpty())
    }

    @Test
    fun `los golpes que el detector ve quedan como metadato`() {
        val g = grabador()
        g.start(0)
        (MotionFixtures.rest(0, 400) + MotionFixtures.forehand(400) +
            MotionFixtures.rest(700, 2_000))
            .forEach { g.onMotion(it) }

        val tanda = assertNotNull(g.stop())
        assertEquals(1, tanda.golpes.size)
        assertEquals(ShotType.FOREHAND, tanda.golpes.first().tipo)
        // Y la señal está entera igualmente: metadato, no puerta.
        assertTrue(tanda.muestras > 50)
    }

    @Test
    fun `las cuatro series van alineadas`() {
        val g = grabador()
        g.start(0)
        MotionFixtures.rest(0, 1_000).forEach { g.onMotion(it) }
        val tanda = assertNotNull(g.stop())
        assertEquals(tanda.offsetsMs.size, tanda.accel.size)
        assertEquals(tanda.offsetsMs.size, tanda.gyro.size)
        assertEquals(tanda.offsetsMs.size, tanda.gravity.size)
        assertTrue(tanda.accel.all { it.size == 3 })
    }

    @Test
    fun `los offsets son relativos al arranque de la tanda`() {
        val g = grabador()
        // La tanda arranca con el reloj llevando ya un rato encendido: los offsets
        // tienen que empezar cerca de cero, no en el uptime del reloj.
        g.start(500_000)
        MotionFixtures.rest(500_000, 1_000).forEach { g.onMotion(it) }
        val tanda = assertNotNull(g.stop())
        assertEquals(0, tanda.offsetsMs.first())
        assertTrue(tanda.offsetsMs.last() < 2_000)
    }

    @Test
    fun `una tanda sin muestras no se guarda`() {
        val g = grabador()
        g.start(0)
        assertNull(g.stop())
    }

    @Test
    fun `el tope de cinco minutos frena la tanda sin tirar lo grabado`() {
        val g = grabador()
        g.start(0)
        // Muchas más muestras de las que caben: el grabador se llena y deja de anotar,
        // pero lo grabado hasta el tope sobrevive. Un "grabar" olvidado no puede
        // comerse la memoria del reloj.
        val paso = 20L
        var t = 0L
        while (t < (GrabadorDeTanda.MAX_MUESTRAS + 100) * paso) {
            g.onMotion(
                com.risingpadel.core.model.MotionSample(
                    timestampMs = t,
                    accel = com.risingpadel.core.model.Vector3(0f, 0f, 0f),
                    gyro = com.risingpadel.core.model.Vector3(0f, 0f, 0f),
                    gravity = com.risingpadel.core.model.Vector3(0f, 0f, -1f),
                )
            )
            t += paso
        }
        assertTrue(g.llena)
        assertEquals(GrabadorDeTanda.MAX_MUESTRAS, g.muestras)
    }

    @Test
    fun `la tanda va y vuelve por json con formato dos`() {
        val g = grabador()
        g.label = ShotType.BANDEJA
        g.playerAlias = "javi"
        g.playerLevel = 4
        g.start(0)
        MotionFixtures.rest(0, 500).forEach { g.onMotion(it) }
        val tanda = assertNotNull(g.stop())

        val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
        val vuelta = json.decodeFromString(
            TandaCruda.serializer(), json.encodeToString(TandaCruda.serializer(), tanda)
        )
        assertEquals(tanda, vuelta)
        assertEquals(2, vuelta.formato)
        assertEquals(ShotType.BANDEJA, vuelta.label)
    }

    @Test
    fun `el almacen mezcla formatos y saca los pares igual`() {
        val dir = kotlin.io.path.createTempDirectory().toFile()
        val store = TrainingSampleStore(java.io.File(dir, "muestras.jsonl"))

        // Una tanda nueva con un golpe visto…
        val g = grabador()
        g.label = ShotType.FOREHAND
        g.start(0)
        (MotionFixtures.rest(0, 400) + MotionFixtures.forehand(400) +
            MotionFixtures.rest(700, 2_000)).forEach { g.onMotion(it) }
        store.appendTanda(assertNotNull(g.stop()))

        // …y una línea vieja corrupta en medio, que no puede tirar el fichero.
        store.file.appendText("{esto no es json}\n")

        val pares = store.paresEtiquetados()
        assertEquals(1, pares.size)
        assertEquals(ShotType.FOREHAND, pares.first().first)
    }
}
