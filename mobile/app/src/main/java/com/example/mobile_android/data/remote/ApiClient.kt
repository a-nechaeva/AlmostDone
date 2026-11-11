package com.example.mobile_android.data.remote

import java.io.IOException
import java.io.InterruptedIOException
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import org.json.JSONObject

enum class ApiMethod { GET, POST, PATCH, PUT, DELETE }

class ApiRequest(
    val path: String,
    val method: ApiMethod = ApiMethod.GET,
    json: JSONObject? = null,
    val ifMatch: String? = null,
    val idempotencyKey: String? = null,
) {
    internal val jsonBody = json?.toString()
}

class ApiResponse internal constructor(
    val status: Int,
    val json: JSONObject?,
    val etag: String?,
    val retryAfter: String?,
)

class ApiError(
    val code: String,
    val message: String,
    val retryable: Boolean,
    val requestId: String,
    val details: List<Detail>,
) {
    class Detail(val field: String, val code: String, val message: String)
}

class ApiHttpException internal constructor(
    val status: Int,
    val error: ApiError?,
    val etag: String?,
    val retryAfter: String?,
) : IOException("HTTP $status")

class ApiNetworkException internal constructor(val timedOut: Boolean) : IOException()
class ApiProtocolException internal constructor() : IOException()
class ApiConfigurationException internal constructor() : IllegalStateException()

interface AuthenticatedApi {
    suspend fun execute(request: ApiRequest): ApiResponse
}

internal class ApiClient(
    baseUrl: String,
    private val transport: HttpTransport,
    allowLoopbackHttp: Boolean = false,
) {
    private val base = baseUrl.trim().toHttpUrlOrNull()?.takeIf {
        val secure = it.isHttps || (allowLoopbackHttp && it.host in setOf("127.0.0.1", "10.0.2.2"))
        secure && it.username.isEmpty() && it.password.isEmpty() &&
            it.query == null && it.fragment == null && it.encodedPath in setOf("/", "/api/v1", "/api/v1/")
    }?.newBuilder()?.encodedPath("/api/v1/")?.build()

    val serverKey: String = base?.toString().orEmpty()

    suspend fun execute(request: ApiRequest, accessToken: String? = null): ApiResponse {
        val server = base ?: throw ApiConfigurationException()
        val path = request.path.removePrefix("/")
        val url = requireNotNull(server.resolve(path))
        require(path.isNotBlank() && !path.startsWith('/') && url.host == server.host &&
            url.port == server.port && url.scheme == server.scheme && url.username.isEmpty() &&
            url.password.isEmpty() && url.encodedPath.startsWith(server.encodedPath) && url.fragment == null) {
            "Expected a path under /api/v1/"
        }
        val headers = buildMap {
            put("Accept", "application/json")
            accessToken?.let { put("Authorization", "Bearer $it") }
            request.ifMatch?.let { put("If-Match", it) }
            request.idempotencyKey?.let { put("Idempotency-Key", it) }
        }
        val response = try {
            transport.execute(HttpRequest(url, request.method, headers, request.jsonBody))
        } catch (e: InterruptedIOException) {
            throw ApiNetworkException(timedOut = true)
        } catch (e: IOException) {
            throw ApiNetworkException(timedOut = false)
        }
        if (response.status !in 200..299) {
            val error = runCatching { parseError(JSONObject(response.body.orEmpty())) }.getOrNull()
            throw ApiHttpException(response.status, error, response.etag, response.retryAfter)
        }
        val json = if (response.status == 204) null
            else runCatching { JSONObject(response.body.orEmpty()) }.getOrElse { throw ApiProtocolException() }
        return ApiResponse(response.status, json, response.etag, response.retryAfter)
    }

    private fun parseError(json: JSONObject): ApiError {
        val error = json.getJSONObject("error")
        val details = error.getJSONArray("details")
        return ApiError(
            error.getString("code"),
            error.getString("message"),
            error.getBoolean("retryable"),
            error.getString("request_id"),
            List(details.length()) { index ->
                val detail = details.getJSONObject(index)
                ApiError.Detail(detail.getString("field"), detail.getString("code"), detail.getString("message"))
            },
        )
    }
}
