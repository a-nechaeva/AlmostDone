package com.example.mobile_android.data.remote

import kotlinx.coroutines.test.runTest
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], application = android.app.Application::class)
class ApiClientTest {
    @Test
    fun handlesOpenApiErrorAndHeaders() = runTest {
        val client = ApiClient("https://api.example.test/api/v1/", HttpTransport { request ->
            assertEquals("https://api.example.test/api/v1/pantry?limit=2", request.url.toString())
            assertEquals(ApiMethod.PATCH, request.method)
            assertEquals("application/json", request.headers["Accept"])
            assertEquals("Bearer session-access", request.headers["Authorization"])
            assertEquals("\"state-6\"", request.headers["If-Match"])
            assertEquals("request-key", request.headers["Idempotency-Key"])
            assertEquals(1, JSONObject(request.body).getInt("quantity"))
            HttpResponse(429, """
                {"error":{"code":"rate_limited","message":"Try later","retryable":true,"request_id":"test",
                "details":[{"field":"quantity","code":"invalid","message":"Invalid amount"}]}}
            """.trimIndent(), etag = "\"state-7\"", retryAfter = "3")
        })
        val request = ApiRequest(
            "/pantry?limit=2",
            ApiMethod.PATCH,
            JSONObject().put("quantity", 1),
            ifMatch = "\"state-6\"",
            idempotencyKey = "request-key",
        )
        val failure = runCatching { client.execute(request, "session-access") }.exceptionOrNull() as ApiHttpException
        assertEquals(429, failure.status)
        assertEquals("3", failure.retryAfter)
        assertEquals("\"state-7\"", failure.etag)
        val error = requireNotNull(failure.error)
        assertEquals("rate_limited", error.code)
        assertEquals("Try later", error.message)
        assertEquals("test", error.requestId)
        assertEquals("quantity", error.details.single().field)
        assertTrue(error.retryable)
    }

    @Test
    fun successWithMissingJsonIsAProtocolError() = runTest {
        val client = ApiClient("https://api.example.test", HttpTransport { HttpResponse(200) })
        val failure = runCatching { client.execute(ApiRequest("me/state")) }.exceptionOrNull()
        assertTrue(failure is ApiProtocolException)
    }

    @Test
    fun noContentSkipsJsonAndOffApiPathsAreRejectedBeforeTransport() = runTest {
        var calls = 0
        val client = ApiClient("https://api.example.test", HttpTransport {
            calls++
            HttpResponse(204, "not JSON", etag = "\"state-7\"")
        })
        val response = client.execute(ApiRequest("auth/logout", ApiMethod.POST), "session-access")
        assertEquals(204, response.status)
        assertEquals("\"state-7\"", response.etag)
        assertNull(response.json)
        for (path in listOf("https://old.example.test/me/state", "//old.example.test/api/v1/me/state", "../health", "/%2e%2e/health")) {
            assertTrue(runCatching { client.execute(ApiRequest(path), "session-access") }.exceptionOrNull() is IllegalArgumentException)
        }
        assertEquals(1, calls)
    }

    @Test
    fun getIsRepeatedOnceAfterAStaleConnection() = runTest {
        var calls = 0
        val client = ApiClient("https://api.example.test/api/v1/", HttpTransport {
            if (++calls == 1) throw java.io.IOException("unexpected end of stream")
            HttpResponse(200, """{"ok":true}""")
        })
        assertTrue(client.execute(ApiRequest("me")).json!!.getBoolean("ok"))
        assertEquals(2, calls)
    }

    @Test
    fun mutationsAndTimeoutsAreNotRepeated() = runTest {
        var calls = 0
        val broken = ApiClient("https://api.example.test/api/v1/", HttpTransport {
            calls++
            throw java.io.IOException("reset")
        })
        val post = runCatching { broken.execute(ApiRequest("me", ApiMethod.PATCH, JSONObject())) }
        assertFalse((post.exceptionOrNull() as ApiNetworkException).timedOut)
        assertEquals(1, calls)

        calls = 0
        val slow = ApiClient("https://api.example.test/api/v1/", HttpTransport {
            calls++
            throw java.io.InterruptedIOException("timeout")
        })
        val get = runCatching { slow.execute(ApiRequest("me")) }
        assertTrue((get.exceptionOrNull() as ApiNetworkException).timedOut)
        assertEquals(1, calls)
    }
}
