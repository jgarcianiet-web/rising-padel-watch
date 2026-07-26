package com.risingpadel.core.storage

import com.risingpadel.core.model.HealthMetrics
import com.risingpadel.core.model.HeartRateSummary
import com.risingpadel.core.model.PadelSession
import com.risingpadel.core.model.Platform
import com.risingpadel.core.model.PlayerProfile
import com.risingpadel.core.model.Shot
import com.risingpadel.core.model.ShotFeatures
import com.risingpadel.core.model.ShotType
import com.risingpadel.core.model.SourceInfo
import com.risingpadel.core.model.SyncState
import java.io.File
import java.nio.file.Files
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class FileSessionStoreTest {

    private val directory: File = Files.createTempDirectory("padel-sessions").toFile()

    @AfterTest
    fun cleanup() {
        directory.deleteRecursively()
    }

    private fun session(id: String, startedAtEpochMs: Long = 1_000_000) = PadelSession(
        sessionId = id,
        source = SourceInfo(Platform.WEAROS, "Pixel Watch 3", "1.0.0"),
        startedAtEpochMs = startedAtEpochMs,
        endedAtEpochMs = startedAtEpochMs + 600_000,
        profile = PlayerProfile(),
        shots = listOf(
            Shot(1_000, ShotType.FOREHAND, 47.5f, 6.4f, 0.9f, ShotFeatures(185f, 20f, 10f, 12f, 200)),
        ),
        health = HealthMetrics(heartRate = HeartRateSummary(132, 171)),
    )

    @Test
    fun `guarda y recupera una sesion completa`() {
        val store = FileSessionStore(directory)
        val original = session("s-1")
        store.upsert(original)

        assertEquals(original, store.get("s-1"))
    }

    @Test
    fun `sobrescribe al volver a guardar la misma sesion`() {
        val store = FileSessionStore(directory)
        store.upsert(session("s-1"))
        store.upsert(session("s-1").let { it.copy(sync = it.sync.copy(state = SyncState.SYNCED)) })

        assertEquals(1, store.all().size)
        assertEquals(SyncState.SYNCED, assertNotNull(store.get("s-1")).sync.state)
    }

    @Test
    fun `lista las sesiones de mas reciente a mas antigua`() {
        val store = FileSessionStore(directory)
        store.upsert(session("vieja", startedAtEpochMs = 1_000_000))
        store.upsert(session("nueva", startedAtEpochMs = 9_000_000))

        assertEquals(listOf("nueva", "vieja"), store.all().map { it.sessionId })
    }

    @Test
    fun `borra una sesion`() {
        val store = FileSessionStore(directory)
        store.upsert(session("s-1"))
        store.delete("s-1")

        assertNull(store.get("s-1"))
        assertTrue(store.all().isEmpty())
    }

    @Test
    fun `una sesion corrupta no se lleva por delante el historial`() {
        val store = FileSessionStore(directory)
        store.upsert(session("buena"))
        File(directory, "corrupta.session.json").writeText("{ esto no es JSON válido")

        val all = store.all()
        assertEquals(listOf("buena"), all.map { it.sessionId })
        assertNull(store.get("corrupta"))
    }

    @Test
    fun `un directorio inexistente se crea al vuelo`() {
        val nested = File(directory, "a/b/c")
        val store = FileSessionStore(nested)
        store.upsert(session("s-1"))

        assertTrue(nested.exists())
        assertEquals(1, store.all().size)
    }

    @Test
    fun `no escribe fuera del directorio aunque el id lleve separadores`() {
        val store = FileSessionStore(directory)
        store.upsert(session("../../fuera"))

        val written = directory.listFiles().orEmpty().filter { it.isFile }
        assertEquals(1, written.size)
        assertEquals("______fuera.session.json", written.single().name)
    }
}
