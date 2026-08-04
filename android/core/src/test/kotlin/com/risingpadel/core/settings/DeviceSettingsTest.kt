package com.risingpadel.core.settings

import com.risingpadel.core.detection.Sensitivity
import com.risingpadel.core.model.Hand
import com.risingpadel.core.model.PlayerProfile
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class DeviceSettingsTest {

    @Test
    fun `aplica los ajustes entrantes si son mas recientes`() {
        val local = DeviceSettings(playerAlias = "viejo", updatedAtEpochMs = 1_000)
        val incoming = DeviceSettings(playerAlias = "nuevo", updatedAtEpochMs = 2_000)

        assertEquals("nuevo", local.mergedWith(incoming).playerAlias)
    }

    @Test
    fun `ignora los ajustes entrantes si son mas viejos`() {
        val local = DeviceSettings(playerAlias = "reloj", updatedAtEpochMs = 5_000)
        val incoming = DeviceSettings(playerAlias = "movil", updatedAtEpochMs = 4_999)

        assertEquals("reloj", local.mergedWith(incoming).playerAlias)
    }

    @Test
    fun `con la misma marca de tiempo gana lo local`() {
        val local = DeviceSettings(playerAlias = "reloj", updatedAtEpochMs = 7_000)
        val incoming = DeviceSettings(playerAlias = "movil", updatedAtEpochMs = 7_000)

        assertEquals("reloj", local.mergedWith(incoming).playerAlias)
    }

    /**
     * El caso que motiva la marca de tiempo: el Data Layer reentrega el último item al
     * reconectar, así que sin ella una reconexión revive ajustes ya sustituidos.
     */
    @Test
    fun `una reentrega del mismo payload no revierte un cambio posterior`() {
        val replicado = DeviceSettings(collectTrainingData = true, updatedAtEpochMs = 1_000)
        val local = DeviceSettings().mergedWith(replicado)
        val editadoDespues = local.copy(collectTrainingData = false, updatedAtEpochMs = 2_000)

        // El sistema vuelve a entregar el payload viejo al reconectar.
        val tras = editadoDespues.mergedWith(replicado)

        assertEquals(false, tras.collectTrainingData)
        assertEquals(2_000, tras.updatedAtEpochMs)
    }

    @Test
    fun `el alias se normaliza a minusculas y sin espacios`() {
        assertEquals("marta-g", DeviceSettings.sanitizeAlias("  Marta G  "))
        assertEquals("juan", DeviceSettings.sanitizeAlias("JUAN"))
    }

    @Test
    fun `un alias vacio cae al valor por defecto`() {
        assertEquals(DeviceSettings.DEFAULT_ALIAS, DeviceSettings.sanitizeAlias(""))
        assertEquals(DeviceSettings.DEFAULT_ALIAS, DeviceSettings.sanitizeAlias("   "))
    }

    @Test
    fun `el alias se acota`() {
        val alias = DeviceSettings.sanitizeAlias("a".repeat(100))
        assertEquals(DeviceSettings.MAX_ALIAS_LENGTH, alias.length)
    }

    @Test
    fun `el payload sobrevive a la ida y vuelta`() {
        val original = DeviceSettings(
            profile = PlayerProfile(hand = Hand.LEFT, watchWrist = Hand.LEFT, birthYear = 1990),
            sensitivity = Sensitivity.HIGH,
            shareHealth = true,
            collectTrainingData = true,
            playerAlias = "marta",
            playerLevel = 6,
            updatedAtEpochMs = 1_785_002_652_000,
        )

        assertEquals(original, DeviceSettings.decode(DeviceSettings.encode(original)))
    }

    @Test
    fun `un payload ilegible devuelve null en vez de romper`() {
        assertNull(DeviceSettings.decode("{no es json"))
        assertNull(DeviceSettings.decode(""))
    }

    /** Un móvil con una versión más nueva no puede tumbar la replicación en el reloj. */
    @Test
    fun `tolera campos desconocidos de una version posterior`() {
        val conExtra = """{"playerAlias":"marta","updatedAtEpochMs":10,"campoFuturo":42}"""
        val decoded = DeviceSettings.decode(conExtra)

        assertEquals("marta", decoded?.playerAlias)
    }

    /** Los ajustes de partido son del reloj: replicarlos pisaría lo que acaba de elegir. */
    @Test
    fun `el payload no lleva ajustes de marcador`() {
        val encoded = DeviceSettings.encode(DeviceSettings())

        assertTrue("trackScore" !in encoded)
        assertTrue("deuceFormat" !in encoded)
        assertTrue("setsToWin" !in encoded)
    }

    /** Un token nunca puede viajar en este payload. */
    @Test
    fun `el payload no lleva credenciales`() {
        val encoded = DeviceSettings.encode(DeviceSettings())

        assertTrue("token" !in encoded)
        assertTrue("baseUrl" !in encoded, "la URL de la liga no la necesita el reloj")
    }
}
