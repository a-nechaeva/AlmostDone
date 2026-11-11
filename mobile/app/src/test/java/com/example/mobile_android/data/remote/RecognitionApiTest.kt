package com.example.mobile_android.data.remote

import com.example.mobile_android.domain.QuantityUnit
import java.util.ArrayDeque
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runTest
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], application = android.app.Application::class)
class RecognitionApiTest {
    private class FakeApi : AuthenticatedApi {
        val requests = mutableListOf<ApiRequest>()
        val responses = ArrayDeque<ApiResponse>()

        override suspend fun execute(request: ApiRequest): ApiResponse {
            requests += request
            return responses.poll() ?: error("Unexpected request: ${request.method} ${request.path}")
        }
    }

    private fun recognition(
        id: String = "rec-1",
        kind: String = "receipt",
        status: String,
        pollAfter: Int = 2,
        lines: JSONArray = JSONArray(),
        failure: String? = null,
    ): JSONObject =
        JSONObject()
            .put("id", id)
            .put("kind", kind)
            .put("status", status)
            .put("expires_at", "2026-11-11T15:00:00Z")
            .put("poll_after_seconds", pollAfter)
            .put("items", lines)
            .put(
                "failure",
                failure?.let { JSONObject().put("error", JSONObject().put("message", it)) }
                    ?: JSONObject.NULL,
            )

    private fun line(
        id: String,
        raw: String,
        status: String,
        candidate: String? = null,
        confidence: Double = 0.9,
        quantity: JSONObject? = null,
    ): JSONObject {
        val candidates = JSONArray()
        if (candidate != null) {
            candidates.put(
                JSONObject()
                    .put("ingredient_id", candidate)
                    .put("name", candidate)
                    .put("confidence", confidence)
            )
        }
        return JSONObject()
            .put("line_id", id)
            .put("raw_name", raw)
            .put("candidates", candidates)
            .put("suggested_quantity", quantity ?: JSONObject.NULL)
            .put("status", status)
    }

    private fun quantity(value: Double, unit: String) =
        JSONObject().put("value", value).put("unit", unit)

    @Test
    fun uploadsPollsAndMapsLines() = runTest {
        val api = FakeApi()
        api.responses += ApiResponse(202, recognition(status = "queued", pollAfter = 3), null, null)
        api.responses += ApiResponse(
            200,
            recognition(
                status = "succeeded",
                lines =
                    JSONArray()
                        .put(line("l1", "СЫР РОССИЙСКИЙ 200Г", "matched", "hard-cheese", quantity = quantity(200.0, "g")))
                        .put(line("l2", "ПАКЕТ МАЛЫЙ", "unmatched"))
                        .put(line("l3", "ХЛЕБ", "ambiguous", "bread", confidence = 0.4)),
            ),
            null,
            null,
        )
        val sleeps = mutableListOf<Long>()
        val recognition = RecognitionApi(api, sleeper = { sleeps += it })

        val result = recognition.recognize(ByteArray(16) { it.toByte() }, "receipt")

        val upload = api.requests[0]
        assertEquals("recognitions", upload.path)
        assertEquals(ApiMethod.POST, upload.method)
        assertNotNull(upload.idempotencyKey)
        assertEquals(mapOf("kind" to "receipt"), upload.upload?.fields)
        assertEquals("image/jpeg", upload.upload?.contentType)
        assertEquals(16, upload.upload?.bytes?.size)
        assertEquals(listOf(3_000L), sleeps)
        assertEquals("recognitions/rec-1", api.requests[1].path)

        assertEquals("rec-1", result.id)
        assertEquals("receipt", result.kind)
        assertEquals(3, result.lines.size)
        val first = result.lines[0]
        assertEquals("l1", first.lineId)
        assertEquals("hard-cheese", first.ingredientId)
        assertTrue(first.matched)
        assertEquals(200.0, first.quantity?.value)
        assertEquals(QuantityUnit.GRAM, first.quantity?.unit)
        assertNull(result.lines[1].ingredientId)
        assertFalse(result.lines[1].matched)
        // Неоднозначная строка подставляет лучшего кандидата для ручного подтверждения.
        assertEquals("bread", result.lines[2].ingredientId)
        assertFalse(result.lines[2].matched)
        assertNull(result.lines[2].quantity)
    }

    @Test
    fun succeededWithEmptyItemsIsAnEmptyResult() = runTest {
        val api = FakeApi()
        api.responses += ApiResponse(202, recognition(status = "succeeded"), null, null)

        val result = RecognitionApi(api, sleeper = {}).recognize(ByteArray(4), "products")

        assertTrue(result.lines.isEmpty())
        assertEquals("products", api.requests[0].upload?.fields?.get("kind"))
    }

    @Test
    fun failedRecognitionSurfacesServerMessage() = runTest {
        val api = FakeApi()
        api.responses += ApiResponse(200, recognition(status = "failed", failure = "OCR недоступен"), null, null)

        val error = assertThrows(RecognitionException::class.java) {
            kotlinx.coroutines.runBlocking { RecognitionApi(api, sleeper = {}).recognize(ByteArray(4), "receipt") }
        }
        assertEquals("OCR недоступен", error.message)
    }

    @Test
    fun endlessPollingIsBounded() = runTest {
        val api = FakeApi()
        repeat(61) { api.responses += ApiResponse(200, recognition(status = "processing", pollAfter = 1), null, null) }

        assertThrows(RecognitionException::class.java) {
            kotlinx.coroutines.runBlocking {
                RecognitionApi(api, sleeper = {}, maxPolls = 5).recognize(ByteArray(4), "receipt")
            }
        }
        // 1 загрузка + 5 опросов, дальше — ошибка ожидания.
        assertEquals(6, api.requests.size)
    }
}
