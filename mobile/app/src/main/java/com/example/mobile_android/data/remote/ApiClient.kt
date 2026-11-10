package com.example.mobile_android.data.remote

import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID
import org.json.JSONObject

/** Ошибка сервера или сети с текстом для пользователя. */
class ApiException(message: String) : Exception(message)

/**
 * Минимальный HTTP-клиент к серверу «Почти готово» (backend/, префикс /api/v1).
 *
 * Без сторонних библиотек: HttpURLConnection + org.json из Android SDK. Вызывать только из
 * фонового потока (Dispatchers.IO).
 */
class ApiClient(private val baseUrl: String) {
    fun getJson(path: String, timeoutMs: Int = 20_000): JSONObject =
        request(path, "GET", timeoutMs) { }

    fun postMultipart(
        path: String,
        fields: Map<String, String>,
        fileField: String,
        fileName: String,
        mime: String,
        bytes: ByteArray,
        timeoutMs: Int = 120_000,
    ): JSONObject {
        val boundary = "----almostdone-" + UUID.randomUUID()
        val body = ByteArrayOutputStream()
        fun line(text: String) = body.write((text + "\r\n").toByteArray(Charsets.UTF_8))
        fields.forEach { (name, value) ->
            line("--$boundary")
            line("Content-Disposition: form-data; name=\"$name\"")
            line("")
            line(value)
        }
        line("--$boundary")
        line("Content-Disposition: form-data; name=\"$fileField\"; filename=\"$fileName\"")
        line("Content-Type: $mime")
        line("")
        body.write(bytes)
        line("")
        line("--$boundary--")
        val payload = body.toByteArray()
        return request(path, "POST", timeoutMs) { connection ->
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "multipart/form-data; boundary=$boundary")
            connection.setFixedLengthStreamingMode(payload.size)
            connection.outputStream.use { it.write(payload) }
        }
    }

    private fun request(
        path: String,
        method: String,
        timeoutMs: Int,
        write: (HttpURLConnection) -> Unit,
    ): JSONObject {
        val connection =
            try {
                URL(normalize(baseUrl) + path.trimStart('/')).openConnection() as HttpURLConnection
            } catch (e: Exception) {
                throw ApiException("Некорректный адрес сервера: $baseUrl")
            }
        try {
            connection.requestMethod = method
            connection.connectTimeout = 5_000
            connection.readTimeout = timeoutMs
            connection.setRequestProperty("Accept", "application/json")
            write(connection)
            val code = connection.responseCode
            val stream = if (code in 200..299) connection.inputStream else connection.errorStream
            val text = stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }.orEmpty()
            if (code !in 200..299) {
                val message =
                    runCatching { JSONObject(text).getJSONObject("error").getString("message") }
                        .getOrNull() ?: "Сервер ответил $code"
                throw ApiException(message)
            }
            return JSONObject(text)
        } catch (e: ApiException) {
            throw e
        } catch (e: java.net.SocketTimeoutException) {
            throw ApiException("Сервер не ответил вовремя")
        } catch (e: java.io.IOException) {
            throw ApiException("Нет связи с сервером ${normalize(baseUrl)}")
        } finally {
            connection.disconnect()
        }
    }

    companion object {
        const val DEFAULT_URL = "http://10.0.2.2:8000/api/v1/" // эмулятор → localhost компьютера

        fun normalize(url: String): String {
            var u = url.trim()
            if (!u.startsWith("http://") && !u.startsWith("https://")) u = "http://$u"
            if (!u.contains("/api/v1")) u = u.trimEnd('/') + "/api/v1"
            return u.trimEnd('/') + "/"
        }
    }
}
