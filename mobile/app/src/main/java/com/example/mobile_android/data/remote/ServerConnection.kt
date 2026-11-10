package com.example.mobile_android.data.remote

import com.example.mobile_android.domain.Quantity
import kotlinx.coroutines.flow.StateFlow

/** Состояние подключения к серверу. */
sealed interface ServerStatus {
    val url: String

    data class Connecting(override val url: String) : ServerStatus

    data class Connected(override val url: String, val recipes: Int, val ingredients: Int) : ServerStatus

    /** Сервер недоступен — приложение работает на встроенном демо-каталоге. */
    data class Offline(override val url: String, val reason: String) : ServerStatus
}

/** Строка распознавания (RecognitionLine из контракта), уже в единицах приложения. */
data class RecognizedLine(
    val lineId: String,
    val rawName: String,
    val ingredientId: String?,
    val name: String?,
    val confidence: Double,
    /** Сколько добавить в кладовку; если на фото не видно — одна упаковка. */
    val quantity: Quantity?,
    /** matched | ambiguous | unmatched */
    val status: String,
)

enum class RecognitionKind(val api: String, val label: String) {
    RECEIPT("receipt", "Чек"),
    PRODUCTS("products", "Продукты"),
}

/** Связь с сервером: каталог, адрес, распознавание фото. */
interface ServerConnection {
    val status: StateFlow<ServerStatus>

    /** Подключиться к серверу по адресу и загрузить каталог; адрес запоминается. */
    suspend fun connect(url: String)

    /** Распознать фото (JPEG). Бросает ApiException с текстом для пользователя. */
    suspend fun recognize(kind: RecognitionKind, jpeg: ByteArray): List<RecognizedLine>
}
