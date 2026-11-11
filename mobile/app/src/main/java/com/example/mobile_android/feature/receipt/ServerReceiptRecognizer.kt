package com.example.mobile_android.feature.receipt

import com.example.mobile_android.data.remote.RecognitionKind
import com.example.mobile_android.data.remote.ServerConnection
import kotlinx.coroutines.CancellationException

/**
 * Распознавание чека на сервере (POST /api/v1/recognitions) → строки экрана проверки.
 *
 * Количество приходит уже в единицах приложения (граммы; не видно на фото — одна упаковка).
 * Отмечены только уверенные совпадения (matched), сомнительные пользователь отмечает сам.
 */
internal fun ServerConnection.receiptRecognizer(): suspend (ByteArray) -> List<ReceiptLine> = { jpeg ->
    val lines =
        try {
            recognize(RecognitionKind.RECEIPT, jpeg)
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (e: Exception) {
            throw ReceiptServerException(e.message, e)
        }
    lines
        .filter { it.rawName.isNotBlank() }
        .mapIndexed { index, line ->
            ReceiptLine(
                id = index + 1,
                text = line.rawName,
                ingredientId = line.ingredientId,
                amount = line.quantity?.value?.let(::formatAmount).orEmpty(),
                unit = line.quantity?.unit,
                selected = line.status == "matched",
            )
        }
}

private fun formatAmount(value: Double): String =
    if (value % 1.0 == 0.0) value.toLong().toString() else "%.1f".format(value).replace('.', ',')
