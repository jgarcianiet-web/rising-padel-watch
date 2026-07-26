package com.risingpadel.core.sync

import com.risingpadel.core.model.Hand
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
import com.risingpadel.core.net.HttpResponse
import com.risingpadel.core.net.HttpTransport
import com.risingpadel.core.net.HttpTransportException
import com.risingpadel.core.storage.InMemorySessionStore
import kotlinx.coroutines.test.runTest
import kotlin.random.Random
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class SyncQueueTest {

    private val config = LeagueConfig(baseUrl = "https://liga.example.com/api", token = "tok_123")

    /** Transporte falso: guarda lo que se le pide y devuelve respuestas programadas. */
    private class FakeTransport(
        private val responses: MutableList<Any> = mutableListOf(),
    ) : HttpTransport {
        val requests = mutableListOf<Request>()

        data class Request(
            val method: String,
            val url: String,
            val headers: Map<String, String>,
            val body: String?,
        )

        fun enqueue(response: HttpResponse) = apply { responses.add(response) }
        fun enqueueNetworkError() = apply { responses.add(HttpTransportException("sin red")) }

        override suspend fun request(
            method: String,
            url: String,
            headers: Map<String, String>,
            body: String?,
        ): HttpResponse {
            requests.add(Request(method, url, headers, body))
            return when (val next = responses.removeFirstOrNull() ?: ok()) {
                is HttpTransportException -> throw next
                is HttpResponse -> next
                else -> error("respuesta no soportada")
            }
        }

        companion object {
            fun ok(id: String = "psession_1", code: Int = 201) =
                HttpResponse(code, """{"id":"$id","sessionId":"s"}""")
        }
    }

    private fun session(
        id: String = "s-1",
        startedAtEpochMs: Long = 1_000_000,
        endedAtEpochMs: Long = 1_600_000,
    ) = PadelSession(
        sessionId = id,
        source = SourceInfo(Platform.WEAROS, "Pixel Watch 3", "1.0.0"),
        startedAtEpochMs = startedAtEpochMs,
        endedAtEpochMs = endedAtEpochMs,
        profile = PlayerProfile(hand = Hand.RIGHT, watchWrist = Hand.RIGHT),
        shots = listOf(
            Shot(
                offsetMs = 1_000,
                type = ShotType.FOREHAND,
                racketSpeedKmh = 47.5f,
                impactG = 6.4f,
                confidence = 0.9f,
                features = ShotFeatures(185f, 20f, 10f, 12f, 200),
            ),
        ),
        health = HealthMetrics(heartRate = HeartRateSummary(meanBpm = 132, maxBpm = 171)),
    )

    private fun queue(
        store: InMemorySessionStore,
        transport: FakeTransport,
        now: Long = 2_000_000,
    ) = SyncQueue(
        store = store,
        client = LeagueApiClient(transport),
        clock = { now },
        retryPolicy = RetryPolicy(random = Random(1), jitterFraction = 0f),
    )

    @Test
    fun `sube una sesion pendiente y la marca como sincronizada`() = runTest {
        val store = InMemorySessionStore(listOf(session()))
        val transport = FakeTransport().enqueue(FakeTransport.ok())

        val report = queue(store, transport).sync(config, shareHealth = true)

        assertEquals(1, report.uploaded)
        val stored = assertNotNull(store.get("s-1"))
        assertEquals(SyncState.SYNCED, stored.sync.state)
        assertEquals("psession_1", stored.sync.remoteId)
    }

    @Test
    fun `manda la clave de idempotencia y el token`() = runTest {
        val store = InMemorySessionStore(listOf(session()))
        val transport = FakeTransport().enqueue(FakeTransport.ok())

        queue(store, transport).sync(config, shareHealth = true)

        val request = transport.requests.single()
        assertEquals("POST", request.method)
        assertEquals("https://liga.example.com/api/v1/padel-sessions", request.url)
        assertEquals("s-1", request.headers["Idempotency-Key"])
        assertEquals("Bearer tok_123", request.headers["Authorization"])
    }

    @Test
    fun `sin liga configurada no se intenta nada`() = runTest {
        val store = InMemorySessionStore(listOf(session()))
        val transport = FakeTransport()

        val report = queue(store, transport).sync(config = null, shareHealth = true)

        assertTrue(report.skipped)
        assertTrue(transport.requests.isEmpty())
        assertEquals(SyncState.PENDING, assertNotNull(store.get("s-1")).sync.state)
    }

    @Test
    fun `un fallo de red deja la sesion pendiente con reintento programado`() = runTest {
        val store = InMemorySessionStore(listOf(session()))
        val transport = FakeTransport().enqueueNetworkError()

        val report = queue(store, transport, now = 2_000_000).sync(config, shareHealth = true)

        assertEquals(1, report.retryLater)
        val stored = assertNotNull(store.get("s-1"))
        assertEquals(SyncState.PENDING, stored.sync.state)
        assertEquals(1, stored.sync.attempts)
        assertEquals(2_000_000 + 2_000, stored.sync.nextAttemptAtEpochMs)
    }

    @Test
    fun `no reintenta antes de la hora programada`() = runTest {
        val pendiente = session().let { it.copy(sync = it.sync.copy(nextAttemptAtEpochMs = 5_000_000)) }
        val store = InMemorySessionStore(listOf(pendiente))
        val transport = FakeTransport()

        val report = queue(store, transport, now = 2_000_000).sync(config, shareHealth = true)

        assertTrue(transport.requests.isEmpty())
        assertEquals(0, report.uploaded)
    }

    @Test
    fun `un 400 es fallo permanente y no se reintenta`() = runTest {
        val store = InMemorySessionStore(listOf(session()))
        val transport = FakeTransport().enqueue(
            HttpResponse(400, """{"error":{"code":"invalid_payload","message":"shots.total inválido"}}""")
        )

        val report = queue(store, transport).sync(config, shareHealth = true)

        assertEquals(1, report.failed)
        val stored = assertNotNull(store.get("s-1"))
        assertEquals(SyncState.FAILED, stored.sync.state)
        assertEquals("shots.total inválido", stored.sync.lastError)
        assertNull(stored.sync.nextAttemptAtEpochMs)
    }

    @Test
    fun `un 401 corta la cola entera y pide reautenticacion`() = runTest {
        val store = InMemorySessionStore(
            listOf(
                session("s-1", startedAtEpochMs = 1_000_000, endedAtEpochMs = 1_100_000),
                session("s-2", startedAtEpochMs = 1_500_000, endedAtEpochMs = 1_600_000),
            )
        )
        val transport = FakeTransport().enqueue(HttpResponse(401, """{"error":{"code":"unauthorized","message":"token caducado"}}"""))

        val report = queue(store, transport).sync(config, shareHealth = true)

        assertTrue(report.needsAuth)
        assertEquals(1, transport.requests.size, "no debe seguir intentando con un token roto")
        assertEquals(SyncState.NEEDS_AUTH, assertNotNull(store.get("s-1")).sync.state)
        assertEquals(SyncState.PENDING, assertNotNull(store.get("s-2")).sync.state)
    }

    @Test
    fun `un 429 respeta Retry-After`() = runTest {
        val store = InMemorySessionStore(listOf(session()))
        val transport = FakeTransport().enqueue(
            HttpResponse(429, "", mapOf("Retry-After" to listOf("120")))
        )

        queue(store, transport, now = 2_000_000).sync(config, shareHealth = true)

        val stored = assertNotNull(store.get("s-1"))
        assertEquals(SyncState.PENDING, stored.sync.state)
        assertEquals(2_000_000 + 120_000, stored.sync.nextAttemptAtEpochMs)
    }

    @Test
    fun `un 413 reintenta sin la serie de golpeos`() = runTest {
        val store = InMemorySessionStore(listOf(session()))
        val transport = FakeTransport()
            .enqueue(HttpResponse(413, ""))
            .enqueue(FakeTransport.ok())

        val report = queue(store, transport).sync(config, shareHealth = true)

        assertEquals(1, report.uploaded)
        assertEquals(2, transport.requests.size)
        assertTrue(transport.requests[0].body!!.contains("\"events\""))
        assertTrue(
            transport.requests[1].body!!.contains("\"events\":[]"),
            "el reintento debe ir sin eventos: ${transport.requests[1].body}",
        )
    }

    @Test
    fun `una sesion mas vieja que 72 horas se da por perdida`() = runTest {
        val vieja = session(endedAtEpochMs = 0)
        val store = InMemorySessionStore(listOf(vieja))
        val transport = FakeTransport()

        val report = queue(store, transport, now = 80 * 60 * 60 * 1000L).sync(config, shareHealth = true)

        assertEquals(1, report.failed)
        assertTrue(transport.requests.isEmpty())
        assertEquals(SyncState.FAILED, assertNotNull(store.get("s-1")).sync.state)
    }

    @Test
    fun `sube las sesiones mas antiguas primero`() = runTest {
        val store = InMemorySessionStore(
            listOf(
                session("nueva", startedAtEpochMs = 1_900_000, endedAtEpochMs = 1_950_000),
                session("vieja", startedAtEpochMs = 1_000_000, endedAtEpochMs = 1_100_000),
            )
        )
        val transport = FakeTransport().enqueue(FakeTransport.ok()).enqueue(FakeTransport.ok())

        queue(store, transport).sync(config, shareHealth = true)

        assertEquals(2, transport.requests.size)
        assertEquals("vieja", transport.requests[0].headers["Idempotency-Key"])
        assertEquals("nueva", transport.requests[1].headers["Idempotency-Key"])
    }

    @Test
    fun `requeue devuelve a la cola una sesion fallada`() = runTest {
        val store = InMemorySessionStore(listOf(session()))
        val transport = FakeTransport().enqueue(HttpResponse(400, ""))
        val queue = queue(store, transport)

        queue.sync(config, shareHealth = true)
        assertEquals(SyncState.FAILED, assertNotNull(store.get("s-1")).sync.state)

        queue.requeue("s-1")
        val stored = assertNotNull(store.get("s-1"))
        assertEquals(SyncState.PENDING, stored.sync.state)
        assertNull(stored.sync.nextAttemptAtEpochMs)
    }

    @Test
    fun `requeue no toca una sesion ya sincronizada`() = runTest {
        val store = InMemorySessionStore(listOf(session()))
        val transport = FakeTransport().enqueue(FakeTransport.ok())
        val queue = queue(store, transport)

        queue.sync(config, shareHealth = true)
        queue.requeue("s-1")

        assertEquals(SyncState.SYNCED, assertNotNull(store.get("s-1")).sync.state)
    }

    @Test
    fun `el backoff crece con los intentos`() {
        val policy = RetryPolicy(random = Random(0), jitterFraction = 0f)
        assertEquals(2_000, policy.delayMs(1))
        assertEquals(4_000, policy.delayMs(2))
        assertEquals(8_000, policy.delayMs(3))
        assertEquals(60_000, policy.delayMs(6))
        assertEquals(15 * 60_000L, policy.delayMs(7))
        assertEquals(15 * 60_000L, policy.delayMs(30))
    }
}
