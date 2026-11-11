package com.example.mobile_android.data.remote

import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.Call
import okhttp3.Callback
import okhttp3.HttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okio.BufferedSink

internal class HttpRequest(
    val url: HttpUrl,
    val method: ApiMethod,
    val headers: Map<String, String>,
    val body: String?,
    val multipart: MultipartContent? = null,
)

/** Бинарная multipart/form-data часть (например, фото чека). Байты и подписи не логируются. */
internal class MultipartContent(
    val fields: Map<String, String>,
    val fileField: String,
    val filename: String,
    val contentType: String,
    val bytes: ByteArray,
) {
    override fun toString() = "MultipartContent(fields=$fields, file=$filename, $contentType, ${bytes.size} bytes)"
}

internal class HttpResponse(
    val status: Int,
    val body: String? = null,
    val etag: String? = null,
    val retryAfter: String? = null,
)

internal fun interface HttpTransport {
    suspend fun execute(request: HttpRequest): HttpResponse
}

internal class OkHttpTransport : HttpTransport {
    private val client = OkHttpClient.Builder()
        .callTimeout(20, TimeUnit.SECONDS)
        .connectTimeout(5, TimeUnit.SECONDS)
        .followRedirects(false)
        .retryOnConnectionFailure(false)
        .build()

    override suspend fun execute(request: HttpRequest): HttpResponse = suspendCancellableCoroutine { continuation ->
        val body = request.multipart?.let { part ->
            MultipartBody.Builder().setType(MultipartBody.FORM).apply {
                part.fields.forEach { (name, value) -> addFormDataPart(name, value) }
                addFormDataPart(
                    part.fileField,
                    part.filename,
                    part.bytes.toRequestBody(part.contentType.toMediaType()),
                )
            }.build()
        } ?: request.body?.toRequestBody("application/json".toMediaType()) ?: when (request.method) {
            ApiMethod.POST, ApiMethod.PATCH, ApiMethod.PUT -> ByteArray(0).toRequestBody()
            else -> null
        }
        val builder = Request.Builder().url(request.url).method(request.method.name, body?.let(::SingleSendBody))
        request.headers.forEach { (name, value) -> builder.header(name, value) }
        val call = client.newCall(builder.build())
        continuation.invokeOnCancellation { call.cancel() }
        call.enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                continuation.resumeWithException(e)
            }

            override fun onResponse(call: Call, response: Response) {
                val result = runCatching {
                    response.use {
                        HttpResponse(
                            it.code,
                            if (it.code == 204) null else it.body?.string(),
                            it.header("ETag"),
                            it.header("Retry-After"),
                        )
                    }
                }
                continuation.resumeWith(result)
            }
        })
    }

    // Some HTTP follow-ups can replay a body even with connection retries disabled.
    private class SingleSendBody(private val body: RequestBody) : RequestBody() {
        override fun contentType() = body.contentType()
        override fun contentLength() = body.contentLength()
        override fun writeTo(sink: BufferedSink) = body.writeTo(sink)
        override fun isOneShot() = true
    }
}
