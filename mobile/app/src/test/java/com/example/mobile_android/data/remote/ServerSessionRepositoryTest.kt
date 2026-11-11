package com.example.mobile_android.data.remote

import java.io.EOFException
import java.net.SocketTimeoutException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], application = android.app.Application::class)
class ServerSessionRepositoryTest {
    @Test
    fun exchangesOAuthTokenChecksBearerAndRestoresSavedPair() = runTest {
        val store = MemorySessionStore()
        val seen = mutableListOf<HttpRequest>()
        val transport = HttpTransport { request ->
            seen += request
            when (request.url.encodedPath) {
                "/api/v1/auth/yandex" -> {
                    assertEquals(ApiMethod.POST, request.method)
                    assertEquals("provider", JSONObject(request.body).getString("oauth_token"))
                    assertNull(request.headers["Authorization"])
                    session("first")
                }
                "/api/v1/me/state" -> {
                    assertEquals(ApiMethod.GET, request.method)
                    assertEquals("Bearer access-first", request.headers["Authorization"])
                    state()
                }
                else -> error("Unexpected request")
            }
        }
        val repository = repository(store, transport)
        assertNull(repository.sessionKey.first())
        repository.signInWithToken("provider")
        assertNotNull(repository.sessionKey.first())
        assertEquals("access-first", store.saved?.access)
        assertEquals("refresh-first", store.saved?.refresh)
        assertEquals(901_000L, store.saved!!.accessUntil)
        assertEquals(1_801_000L, store.saved!!.refreshUntil)

        assertNotNull(repository(store, transport).sessionKey.first())
        assertEquals(listOf("/api/v1/auth/yandex", "/api/v1/me/state", "/api/v1/me/state"), seen.map { it.url.encodedPath })
    }

    @Test
    fun expiresAccessBeforeCallingMeAndHonorsRefreshDeadline() = runTest {
        var clock = 11L
        val store = MemorySessionStore(SessionTokens("user", "old-access", "old-refresh", 10, 100, "test-session"))
        var refreshCalls = 0
        val transport = HttpTransport { request ->
            when (request.url.encodedPath) {
                "/api/v1/auth/refresh" -> {
                    refreshCalls++
                    assertNull(store.saved)
                    assertEquals("old-refresh", JSONObject(request.body).getString("refresh_token"))
                    session("rotated")
                }
                "/api/v1/me/state" -> {
                    assertEquals("Bearer access-rotated", request.headers["Authorization"])
                    state()
                }
                else -> error("Unexpected request")
            }
        }
        assertNotNull(repository(store, transport) { clock }.sessionKey.first())
        assertEquals(1, refreshCalls)
        assertEquals("refresh-rotated", store.saved!!.refresh)
        clock = store.saved!!.refreshUntil
        assertNull(repository(store, transport) { clock }.sessionKey.first())
        assertEquals(1, refreshCalls)
        assertNull(store.saved)
    }

    @Test
    fun simultaneous401sShareOneRotationAndRetryWithItsAccessToken() = runTest {
        val store = MemorySessionStore(oldTokens())
        val bothRejected = CompletableDeferred<Unit>()
        val finishRotation = CompletableDeferred<Unit>()
        var rejections = 0
        var refreshCalls = 0
        val repository = repository(store, HttpTransport { request ->
            when (request.url.encodedPath) {
                "/api/v1/me/state" -> state()
                "/api/v1/auth/refresh" -> {
                    refreshCalls++
                    assertEquals("old-refresh", JSONObject(request.body).getString("refresh_token"))
                    assertNull(request.headers["Authorization"])
                    assertNull(store.saved)
                    finishRotation.await()
                    session("rotated")
                }
                "/api/v1/pantry" -> {
                    assertEquals("\"state-2\"", request.headers["If-Match"])
                    assertEquals("change-1", request.headers["Idempotency-Key"])
                    assertEquals("example", JSONObject(request.body).getString("item"))
                    when (request.headers["Authorization"]) {
                        "Bearer old-access" -> {
                            if (++rejections == 2) bothRejected.complete(Unit)
                            HttpResponse(401)
                        }
                        "Bearer access-rotated" -> HttpResponse(204, etag = "\"state-3\"")
                        else -> error("Unexpected Authorization")
                    }
                }
                else -> error("Unexpected request")
            }
        })
        assertNotNull(repository.sessionKey.first())
        val request = ApiRequest(
            "pantry", ApiMethod.POST, JSONObject().put("item", "example"),
            ifMatch = "\"state-2\"", idempotencyKey = "change-1",
        )
        val first = async { repository.execute(request) }
        val second = async { repository.execute(request) }
        bothRejected.await()
        finishRotation.complete(Unit)
        assertEquals("\"state-3\"", first.await().etag)
        assertNull(second.await().json)
        assertEquals(1, refreshCalls)
        assertEquals("access-rotated", store.saved!!.access)
    }

    @Test
    fun rateLimitedRefreshSharesRejectionAndHonorsRetryAfter() = runTest {
        val store = MemorySessionStore(oldTokens(accessUntil = 2_000L))
        val bothRejected = CompletableDeferred<Unit>()
        val finishRejection = CompletableDeferred<Unit>()
        var clock = 1_000L
        var rejections = 0
        var refreshCalls = 0
        val transport = HttpTransport { request ->
            when (request.url.encodedPath) {
                "/api/v1/me/state" -> state()
                "/api/v1/pantry" ->
                    if (request.headers["Authorization"] == "Bearer old-access") {
                        if (++rejections == 2) bothRejected.complete(Unit)
                        HttpResponse(401)
                    } else HttpResponse(204)
                "/api/v1/auth/refresh" -> {
                    if (++refreshCalls == 1) {
                        finishRejection.await()
                        HttpResponse(429, """{"error":{"code":"rate_limited","message":"Try later",
                            "retryable":true,"request_id":"test","details":[]}}""", retryAfter = "3")
                    } else session("rotated")
                }
                else -> error("Unexpected request")
            }
        }
        val repository = repository(store, transport) { clock }
        assertEquals("test-session", repository.sessionKey.first())
        val request = ApiRequest("pantry")
        val first = async { runCatching { repository.execute(request) } }
        val second = async { runCatching { repository.execute(request) } }
        bothRejected.await()
        finishRejection.complete(Unit)
        val error = first.await().exceptionOrNull() as ApiHttpException
        assertEquals("3", error.retryAfter)
        assertSame(error, second.await().exceptionOrNull())
        assertEquals("old-refresh", store.saved!!.refresh)
        assertEquals("test-session", repository.sessionKey.first())
        clock += 2_999
        assertSame(error, runCatching { repository.execute(request) }.exceptionOrNull())
        assertEquals(1, refreshCalls)
        val restarted = repository(store, transport) { clock }
        val recoveredError = runCatching { restarted.sessionKey.first() }.exceptionOrNull() as ApiHttpException
        assertEquals(429, recoveredError.status)
        assertEquals("1", recoveredError.retryAfter)
        assertEquals(1, refreshCalls)
        clock++
        assertEquals(204, repository.execute(request).status)
        assertEquals(2, refreshCalls)
        assertEquals("test-session", store.saved!!.navigationKey)
        assertEquals("refresh-rotated", store.saved!!.refresh)
    }

    @Test
    fun logoutWithExpiredAccessRotatesOnceAndDoesNotRestoreLocalSession() = runTest {
        val store = MemorySessionStore(oldTokens())
        var clock = 1_000L
        val paths = mutableListOf<String>()
        val repository = repository(store, HttpTransport { request ->
            val path = request.url.encodedPath
            paths += path
            when (path) {
                "/api/v1/me/state" -> state()
                "/api/v1/auth/refresh" -> {
                    assertNull(store.saved)
                    assertEquals("old-refresh", JSONObject(request.body).getString("refresh_token"))
                    session("logout")
                }
                "/api/v1/auth/logout" -> {
                    assertNull(store.saved)
                    assertEquals("Bearer access-logout", request.headers["Authorization"])
                    HttpResponse(204)
                }
                else -> error("Unexpected request")
            }
        }) { clock }
        assertEquals("test-session", repository.sessionKey.first())
        clock = 10_000L
        repository.signOut()
        assertNull(repository.sessionKey.first())
        assertNull(store.saved)
        assertEquals(listOf("/api/v1/me/state", "/api/v1/auth/refresh", "/api/v1/auth/logout"), paths)
    }

    @Test
    fun logoutRetriesOnceWhenTheIdleConnectionCloses() = runTest {
        val store = MemorySessionStore(oldTokens())
        var revokeCalls = 0
        val repository = repository(store, HttpTransport { request ->
            when (request.url.encodedPath) {
                "/api/v1/me/state" -> state()
                "/api/v1/auth/logout" -> {
                    assertNull(store.saved)
                    assertEquals("Bearer old-access", request.headers["Authorization"])
                    if (++revokeCalls == 1) throw EOFException()
                    HttpResponse(204)
                }
                else -> error("Unexpected request")
            }
        })
        assertEquals("test-session", repository.sessionKey.first())
        repository.signOut()
        assertEquals(2, revokeCalls)
        assertNull(repository.sessionKey.first())
    }

    @Test
    fun logoutRefreshesOnceIfAccessExpiresBetweenSendingAndServerValidation() = runTest {
        val store = MemorySessionStore(oldTokens())
        var clock = 9_999L
        var refreshCalls = 0
        val revokedWith = mutableListOf<String?>()
        val repository = repository(store, HttpTransport { request ->
            when (request.url.encodedPath) {
                "/api/v1/me/state" -> state()
                "/api/v1/auth/refresh" -> {
                    refreshCalls++
                    assertNull(store.saved)
                    session("logout")
                }
                "/api/v1/auth/logout" -> {
                    val access = request.headers["Authorization"]
                    revokedWith += access
                    if (access == "Bearer old-access") {
                        clock = 10_000L
                        HttpResponse(401)
                    } else HttpResponse(204)
                }
                else -> error("Unexpected request")
            }
        }) { clock }
        assertEquals("test-session", repository.sessionKey.first())
        repository.signOut()
        assertEquals(listOf("Bearer old-access", "Bearer access-logout"), revokedWith)
        assertEquals(1, refreshCalls)
        assertNull(repository.sessionKey.first())
        assertNull(store.saved)
    }

    @Test
    fun timeoutRetiresRefreshTokenForCurrentAndRestartedRepository() = runTest {
        val store = MemorySessionStore(oldTokens())
        var calls = 0
        val transport = HttpTransport { request ->
            when (request.url.encodedPath) {
                "/api/v1/me/state" -> HttpResponse(401)
                "/api/v1/auth/refresh" -> {
                    calls++
                    assertNull(store.saved)
                    throw SocketTimeoutException()
                }
                else -> error("Unexpected request")
            }
        }
        val repository = repository(store, transport)
        assertNull(repository.sessionKey.first())
        assertTrue(runCatching { repository.execute(ApiRequest("me/state")) }.exceptionOrNull() is SessionExpiredException)
        assertNull(repository(store, transport).sessionKey.first())
        assertEquals(1, calls)
    }

    @Test
    fun cancellationWhileRefreshIsInFlightRetiresToken() = runTest {
        val store = MemorySessionStore(oldTokens())
        val started = CompletableDeferred<Unit>()
        val neverReturns = CompletableDeferred<HttpResponse>()
        val transport = HttpTransport { request ->
            when (request.url.encodedPath) {
                "/api/v1/me/state" -> HttpResponse(401)
                "/api/v1/auth/refresh" -> {
                    started.complete(Unit)
                    neverReturns.await()
                }
                else -> error("Unexpected request")
            }
        }
        val repository = repository(store, transport)
        val restoration = async { repository.sessionKey.first() }
        started.await()
        restoration.cancelAndJoin()
        assertNull(store.saved)
        assertNull(repository.sessionKey.first())
        assertNull(repository(store, transport).sessionKey.first())
    }

    @Test
    fun logoutClearsLocallyThenRevokesTheRotatedFamilyWithoutAffectingNewAccount() = runTest {
        val store = MemorySessionStore(oldTokens())
        val rotationStarted = CompletableDeferred<Unit>()
        val finishRotation = CompletableDeferred<Unit>()
        val signedOut = CompletableDeferred<Unit>()
        store.onWrite = { if (it == null && rotationStarted.isCompleted) signedOut.complete(Unit) }
        val seenLogout = mutableListOf<String?>()
        val repository = repository(store, HttpTransport { request ->
            when (request.url.encodedPath) {
                "/api/v1/me/state" -> state(
                    if (request.headers["Authorization"] == "Bearer access-new") "new-user" else "user"
                )
                "/api/v1/pantry" -> HttpResponse(401)
                "/api/v1/auth/refresh" -> {
                    rotationStarted.complete(Unit)
                    finishRotation.await()
                    session("rotated")
                }
                "/api/v1/auth/logout" -> {
                    seenLogout += request.headers["Authorization"]
                    HttpResponse(204)
                }
                "/api/v1/auth/yandex" -> session("new", "new-user")
                else -> error("Unexpected request")
            }
        })
        assertNotNull(repository.sessionKey.first())
        val oldRequest = async { runCatching { repository.execute(ApiRequest("pantry")) } }
        rotationStarted.await()
        val logout = async { repository.signOut() }
        signedOut.await()
        assertNull(repository.sessionKey.first())
        repository.signInWithToken("new-oauth")
        finishRotation.complete(Unit)
        logout.await()
        assertTrue(oldRequest.await().exceptionOrNull() is SessionExpiredException)
        assertEquals(listOf("Bearer access-rotated"), seenLogout)
        assertNotNull(repository.sessionKey.first())
        assertEquals("new-user", store.saved!!.userId)
        assertEquals("refresh-new", store.saved!!.refresh)
    }

    @Test
    fun successfulOldResponseIsDiscardedAfterSwitchingAccounts() = runTest {
        val store = MemorySessionStore(oldTokens())
        val requestStarted = CompletableDeferred<Unit>()
        val finishRequest = CompletableDeferred<Unit>()
        val repository = repository(store, HttpTransport { request ->
            when (request.url.encodedPath) {
                "/api/v1/me/state" -> state(
                    if (request.headers["Authorization"] == "Bearer access-new") "new-user" else "user"
                )
                "/api/v1/pantry" -> {
                    requestStarted.complete(Unit)
                    finishRequest.await()
                    HttpResponse(200, "{\"private_old_data\":true}")
                }
                "/api/v1/auth/logout", "/api/v1/auth/refresh" -> HttpResponse(401)
                "/api/v1/auth/yandex" -> session("new", "new-user")
                else -> error("Unexpected request")
            }
        })
        assertNotNull(repository.sessionKey.first())
        val oldRequest = async { runCatching { repository.execute(ApiRequest("pantry")) } }
        requestStarted.await()
        repository.signOut()
        assertNull(repository.sessionKey.first())
        repository.signInWithToken("new-oauth")
        finishRequest.complete(Unit)
        assertTrue(oldRequest.await().exceptionOrNull() is SessionExpiredException)
        assertEquals("new-user", store.saved!!.userId)
    }

    @Test
    fun wrongUserInStatePreventsSignIn() = runTest {
        val store = MemorySessionStore()
        val repository = repository(store, HttpTransport { request ->
            when (request.url.encodedPath) {
                "/api/v1/auth/yandex" -> session("first")
                "/api/v1/me/state" -> state("other-user")
                else -> error("Unexpected request")
            }
        })
        assertTrue(runCatching { repository.signInWithToken("provider") }.exceptionOrNull() is ApiProtocolException)
        assertNull(repository.sessionKey.first())
        assertNull(store.saved)
    }

    private fun repository(
        store: SessionStore,
        transport: HttpTransport,
        now: () -> Long = { 1_000L },
    ) = ServerSessionRepository(ApiClient("https://api.example.test", transport), store, now)

    private fun oldTokens(accessUntil: Long = 10_000L) =
        SessionTokens("user", "old-access", "old-refresh", accessUntil, 20_000L, "test-session")
}

internal class MemorySessionStore(var saved: SessionTokens? = null) : SessionStore {
    var onWrite: (SessionTokens?) -> Unit = {}

    override suspend fun read() = saved
    override suspend fun write(tokens: SessionTokens?) {
        saved = tokens
        onWrite(tokens)
    }
}

internal fun session(suffix: String, userId: String = "user"): HttpResponse = HttpResponse(
    200, JSONObject()
        .put("user_id", userId)
        .put("access_token", "access-$suffix")
        .put("refresh_token", "refresh-$suffix")
        .put("token_type", "Bearer")
        .put("expires_in", 900)
        .put("refresh_expires_in", 1800)
        .toString(),
)

internal fun state(userId: String = "user"): HttpResponse = HttpResponse(
    200, JSONObject().put("state_version", 1).put("catalog_version", "catalog").put("user_id", userId).toString(),
    etag = "\"state-1\"",
)
