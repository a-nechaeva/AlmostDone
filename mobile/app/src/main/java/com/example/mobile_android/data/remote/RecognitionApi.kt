package com.example.mobile_android.data.remote

import com.example.mobile_android.domain.Quantity
import java.io.IOException
import java.util.UUID
import kotlinx.coroutines.delay
import org.json.JSONObject

/** Сбой серверного распознавания: сеть, отказ провайдера или статус failed. */
class RecognitionException(message: String?, cause: Throwable? = null) : IOException(message, cause)

class RecognitionLineResult(
    val lineId: String,
    val rawName: String,
    val ingredientId: String?,
    val quantity: Quantity?,
    val matched: Boolean,
)

class RecognitionResult(val id: String, val kind: String, val lines: List<RecognitionLineResult>)

/**
 * Серверное распознавание чека или фото продуктов (`POST /recognitions`, `GET /recognitions/{id}`).
 *
 * Загрузка идёт одним multipart-запросом с `Idempotency-Key`; результат дочитывается опросом
 * с интервалом `poll_after_seconds` из ответа (подсказка `Retry-After` учитывается как минимум).
 * Отмена coroutine прерывает ожидание без повторных запросов. Байты фото и сырые строки чека
 * не пишутся в логи; временные файлы удаляет вызывающая сторона после завершения сценария.
 */
class RecognitionApi(
    private val api: AuthenticatedApi,
    private val sleeper: suspend (millis: Long) -> Unit = { delay(it) },
    private val maxPolls: Int = 60,
) {
    /** [kind] — `receipt` или `products` по RecognitionKind. */
    suspend fun recognize(jpeg: ByteArray, kind: String): RecognitionResult {
        require(kind == "receipt" || kind == "products")
        require(jpeg.isNotEmpty() && jpeg.size <= MAX_BYTES) { "Фото должно быть JPEG до 10 МиБ." }
        val upload =
            UploadFile(
                fields = mapOf("kind" to kind),
                filename = if (kind == "receipt") "receipt.jpg" else "products.jpg",
                contentType = "image/jpeg",
                bytes = jpeg,
            )
        val created =
            api.execute(
                ApiRequest(
                    "recognitions",
                    ApiMethod.POST,
                    idempotencyKey = UUID.randomUUID().toString(),
                    upload = upload,
                )
            )
        var recognition = parse(created.json ?: throw ApiProtocolException())
        var polls = 0
        while (recognition.status == "queued" || recognition.status == "processing") {
            if (++polls > maxPolls) throw RecognitionException("Распознавание заняло слишком много времени.")
            val waitSeconds = recognition.pollAfterSeconds.coerceIn(1, 30)
            sleeper(waitSeconds * 1_000L)
            recognition =
                parse(
                    api.execute(ApiRequest("recognitions/${recognition.id}")).json
                        ?: throw ApiProtocolException()
                )
        }
        if (recognition.status == "failed") {
            throw RecognitionException(recognition.failure ?: "Сервер не смог распознать фото.")
        }
        if (recognition.status != "succeeded") throw ApiProtocolException()
        return RecognitionResult(recognition.id, recognition.kind, recognition.lines)
    }

    private class Task(
        val id: String,
        val kind: String,
        val status: String,
        val pollAfterSeconds: Int,
        val failure: String?,
        val lines: List<RecognitionLineResult>,
    )

    private fun parse(json: JSONObject): Task {
        val items = json.getJSONArray("items")
        val lines =
            List(items.length()) { index ->
                val item = items.getJSONObject(index)
                val candidates = item.getJSONArray("candidates")
                val best =
                    if (candidates.length() == 0) null
                    else {
                        var top = candidates.getJSONObject(0)
                        for (i in 1 until candidates.length()) {
                            val next = candidates.getJSONObject(i)
                            if (next.optDouble("confidence") > top.optDouble("confidence")) top = next
                        }
                        top
                    }
                val status = item.optString("status")
                RecognitionLineResult(
                    lineId = item.getString("line_id"),
                    rawName = item.optString("raw_name"),
                    // «Лучший» кандидат подставляется для ручного подтверждения; сопоставление
                    // с каталогом и выбор строки всегда остаются за пользователем.
                    ingredientId = best?.optString("ingredient_id")?.takeIf { it.isNotBlank() },
                    quantity =
                        if (item.isNull("suggested_quantity")) null
                        else parseQuantity(item.getJSONObject("suggested_quantity")),
                    matched = status == "matched",
                )
            }
        return Task(
            id = json.getString("id"),
            kind = json.getString("kind"),
            status = json.getString("status"),
            pollAfterSeconds = json.optInt("poll_after_seconds", 2).coerceAtLeast(1),
            failure =
                json.optJSONObject("failure")?.optJSONObject("error")?.optString("message")
                    ?.takeIf { it.isNotBlank() },
            lines = lines,
        )
    }

    private companion object {
        const val MAX_BYTES = 10 * 1024 * 1024
    }
}
