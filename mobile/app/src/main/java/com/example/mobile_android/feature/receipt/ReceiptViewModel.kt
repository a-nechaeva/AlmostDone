package com.example.mobile_android.feature.receipt

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.mobile_android.domain.CatalogRepository
import com.example.mobile_android.domain.Ingredient
import com.example.mobile_android.domain.Quantity
import com.example.mobile_android.domain.QuantityUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

data class ReceiptLine(
    val id: Int,
    val text: String,
    val ingredientId: String?,
    val amount: String = "",
    val unit: QuantityUnit? = null,
    val selected: Boolean = false,
    /** ID строки в серверном результате распознавания; null — локальные демо-строки. */
    val serverLineId: String? = null,
) {
    fun quantity(ingredient: Ingredient?): Quantity? {
        if (ingredient == null || ingredient.unit != unit) return null
        val value = amount.trim().replace(',', '.').toDoubleOrNull() ?: return null
        return if (value > 0 && value <= 1_000_000) Quantity(value, ingredient.unit) else null
    }
}

internal fun interface ReceiptRecognizer {
    suspend fun recognize(): List<ReceiptLine>
}

internal object DemoReceiptRecognizer : ReceiptRecognizer {
    override suspend fun recognize() =
        listOf(
            ReceiptLine(1, "СЫР РОССИЙСКИЙ 200Г", "hard-cheese", "200", QuantityUnit.GRAM, true),
            ReceiptLine(2, "ЯЙЦО КУР.С1 10ШТ", "eggs", "10", QuantityUnit.PIECE),
            ReceiptLine(3, "МОЛОКО ПАСТ. 2.5% 1Л", "milk", "1000", QuantityUnit.MILLILITER),
            ReceiptLine(4, "ПАКЕТ МАЛЫЙ", null),
        )
}

fun interface ReceiptImporter {
    suspend fun add(quantities: Map<String, Quantity>)
}

/** Результат серверного распознавания фото: ID задачи и строки с их серверными line_id. */
class RecognizedReceipt(val recognitionId: String, val lines: List<ReceiptLine>)

/** Одна подтверждённая пользователем строка для `POST /recognition-imports`. */
data class ReceiptImportLine(val lineId: String, val ingredientId: String, val quantity: Quantity?)

/**
 * Подтверждение импорта распознанного чека на сервере (`POST /recognition-imports`
 * с `If-Match` и `Idempotency-Key`). После успеха запасы зеркалируются в локальное
 * хранилище внутри реализации.
 */
interface ServerReceiptImporter {
    suspend fun importReceipt(recognitionId: String, kind: String, lines: List<ReceiptImportLine>)
}

internal class UnknownReceiptPantryQuantity(val ingredientId: String) : IllegalStateException()

internal enum class ReceiptPhotoRequest { CAMERA, PICKER }

/** Что на фото: кассовый чек или сами продукты (холодильник, стол, пакет). */
enum class ReceiptPhotoKind {
    RECEIPT,
    PRODUCTS;

    /** Значение `RecognitionKind` из контракта API. */
    internal val apiKind: String
        get() = if (this == RECEIPT) "receipt" else "products"
}

internal enum class ReceiptPhotoIssue { NO_CAMERA, NO_PICKER, ACCESS, UNREADABLE, EMPTY, SERVER }

/** Сбой сервера распознавания (сеть, GigaChat) — в отличие от нечитаемого фото. */
internal class ReceiptServerException(message: String?, cause: Throwable? = null) : Exception(message, cause)

internal sealed interface ReceiptState {
    data class Capture(val issue: ReceiptPhotoIssue? = null) : ReceiptState
    data object Reading : ReceiptState
    data class Review(
        val lines: List<ReceiptLine>,
        val ingredients: List<Ingredient>,
        val saving: Boolean = false,
        val error: String? = null,
        /** Строки из демо-заглушки, а не с сервера. */
        val demo: Boolean = true,
        /** ID серверной задачи распознавания; null — локальные демо-строки. */
        val recognitionId: String? = null,
    ) : ReceiptState {
        fun ingredient(line: ReceiptLine) = ingredients.find { it.id == line.ingredientId }
    }
    data class Added(val names: List<String>) : ReceiptState
}

internal class ReceiptViewModel(
    private val catalog: CatalogRepository,
    private val importer: ReceiptImporter?,
    private val savedState: SavedStateHandle,
    private val discardCapture: (String) -> Unit,
    private val recognizer: ReceiptRecognizer = DemoReceiptRecognizer,
    /** Распознавание по самому фото (сервер). null — прежняя демо-заглушка [recognizer]. */
    private val photoRecognizer: (suspend (ByteArray, ReceiptPhotoKind) -> RecognizedReceipt)? = null,
    /** Подтверждение импорта на сервере; null — только локальная запись через [importer]. */
    private val serverImporter: ServerReceiptImporter? = null,
) : ViewModel() {
    private val mutableState = MutableStateFlow<ReceiptState>(ReceiptState.Capture())
    val state = mutableState.asStateFlow()

    /** Выбор «чек / продукты» имеет смысл, только когда фото распознаёт сервер. */
    val canChooseKind = photoRecognizer != null
    val kind = savedState.getStateFlow("receiptPhotoKind", ReceiptPhotoKind.RECEIPT)

    fun chooseKind(value: ReceiptPhotoKind) {
        if (state.value is ReceiptState.Capture) savedState["receiptPhotoKind"] = value
    }
    private var reading: Job? = null
    val photoRequest = savedState.getStateFlow<String?>("receiptPhotoRequest", null)

    fun beginPhotoRequest(request: ReceiptPhotoRequest): Boolean {
        if (state.value !is ReceiptState.Capture || photoRequest.value != null) return false
        savedState["receiptPhotoRequest"] = request.name
        return true
    }

    fun finishPhotoRequest(request: ReceiptPhotoRequest): Boolean {
        if (photoRequest.value != request.name) return false
        savedState["receiptPhotoRequest"] = null
        return true
    }

    var cameraFile: String?
        get() = savedState["receiptCameraFile"]
        set(value) { savedState["receiptCameraFile"] = value }

    fun cameraFinished(): String? = cameraFile.also { cameraFile = null }

    fun photoIssue(issue: ReceiptPhotoIssue) {
        if (state.value is ReceiptState.Capture) mutableState.value = ReceiptState.Capture(issue)
    }

    fun readPhoto(validate: suspend () -> Unit) = readImage {
        validate()
        null
    }

    /** [read] возвращает JPEG для распознавания (или null — тогда демо-распознавание). */
    fun readImage(read: suspend () -> ByteArray?) {
        if (state.value !is ReceiptState.Capture) return
        mutableState.value = ReceiptState.Reading
        reading = viewModelScope.launch {
            val result = try {
                val photo = read()
                val ingredients = catalog.catalog.first().ingredients.sortedBy { it.name }
                val recognized = photoRecognizer?.let { recognize -> photo?.let { recognize(it, kind.value) } }
                val lines = (recognized?.lines ?: recognizer.recognize()).map { line ->
                    val ingredient = ingredients.find { it.id == line.ingredientId }
                    if (ingredient == null) line.copy(
                        ingredientId = null, amount = "", unit = null, selected = false,
                    ) else line.copy(selected = line.selected && line.quantity(ingredient) != null)
                }
                if (lines.isEmpty()) ReceiptState.Capture(ReceiptPhotoIssue.EMPTY)
                else ReceiptState.Review(
                    lines,
                    ingredients,
                    demo = recognized == null,
                    recognitionId = recognized?.recognitionId,
                )
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: SecurityException) {
                ReceiptState.Capture(ReceiptPhotoIssue.ACCESS)
            } catch (_: ReceiptServerException) {
                ReceiptState.Capture(ReceiptPhotoIssue.SERVER)
            } catch (_: Exception) {
                ReceiptState.Capture(ReceiptPhotoIssue.UNREADABLE)
            }
            ensureActive()
            mutableState.value = result
        }
    }

    fun reset() {
        if ((state.value as? ReceiptState.Review)?.saving == true || state.value is ReceiptState.Added) return
        reading?.cancel()
        mutableState.value = ReceiptState.Capture()
    }

    fun toggle(lineId: Int, selected: Boolean) = updateLine(lineId) { review, line ->
        line.copy(selected = selected && line.quantity(review.ingredient(line)) != null)
    }

    fun edit(lineId: Int, ingredient: Ingredient, amount: String) = updateLine(lineId) { review, line ->
        if (ingredient !in review.ingredients) return@updateLine line
        val edited = line.copy(ingredientId = ingredient.id, unit = ingredient.unit, amount = amount)
        edited.copy(selected = line.selected && edited.quantity(ingredient) != null)
    }

    private fun updateLine(lineId: Int, change: (ReceiptState.Review, ReceiptLine) -> ReceiptLine) {
        val review = state.value as? ReceiptState.Review ?: return
        if (review.saving) return
        mutableState.value = review.copy(
            lines = review.lines.map { if (it.id == lineId) change(review, it) else it },
            error = null,
        )
    }

    fun confirm() {
        val review = state.value as? ReceiptState.Review ?: return
        val selected = review.lines.filter { it.selected }
        if (review.saving || selected.isEmpty()) return
        val recognition = review.recognitionId
        if (recognition != null && serverImporter != null) {
            confirmOnServer(review, recognition, selected)
            return
        }
        val totals = linkedMapOf<String, Quantity>()
        for (line in selected) {
            val ingredient = review.ingredient(line) ?: return
            val quantity = line.quantity(ingredient) ?: return
            val total = quantity.value + (totals[ingredient.id]?.value ?: 0.0)
            if (total > 1_000_000) {
                mutableState.value = review.copy(error = "Суммарное количество слишком велико. Проверьте строки.")
                return
            }
            totals[ingredient.id] = Quantity(total, ingredient.unit)
        }
        val writer = importer
        if (writer == null) {
            mutableState.value = review.copy(error = "Добавление продуктов сейчас недоступно.")
            return
        }
        mutableState.value = review.copy(saving = true, error = null)
        viewModelScope.launch {
            try {
                writer.add(totals)
                mutableState.value = ReceiptState.Added(totals.keys.map { id ->
                    review.ingredients.first { it.id == id }.name
                })
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (unknown: UnknownReceiptPantryQuantity) {
                val name = review.ingredients.first { it.id == unknown.ingredientId }.name
                mutableState.value = review.copy(
                    error = "Уточните остаток продукта «$name» в разделе «Продукты», затем снова добавьте чек.",
                )
            } catch (_: Exception) {
                mutableState.value = review.copy(error = "Не удалось добавить продукты. Проверьте количество и повторите.")
            }
        }
    }

    /**
     * Подтверждение через `POST /recognition-imports`: на сервер уходят только выбранные строки
     * с canonical ID, положительным количеством и серверным line_id. Двойное нажатие блокируется
     * флагом saving, повтор той же операции защищён Idempotency-Key в реализации импортёра.
     * При отказе выбор строк сохраняется и ошибку можно повторить.
     */
    private fun confirmOnServer(
        review: ReceiptState.Review,
        recognitionId: String,
        selected: List<ReceiptLine>,
    ) {
        val items = mutableListOf<ReceiptImportLine>()
        for (line in selected) {
            val ingredient = review.ingredient(line) ?: return
            val lineId = line.serverLineId ?: return
            // Выбрать строку можно только с корректным положительным количеством (см. toggle/edit).
            val quantity = line.quantity(ingredient) ?: return
            items += ReceiptImportLine(lineId, ingredient.id, quantity)
        }
        mutableState.value = review.copy(saving = true, error = null)
        viewModelScope.launch {
            try {
                serverImporter!!.importReceipt(recognitionId, kind.value.apiKind, items)
                mutableState.value = ReceiptState.Added(items.map { line ->
                    review.ingredients.first { it.id == line.ingredientId }.name
                }.distinct())
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                mutableState.value = review.copy(
                    error = "Не удалось добавить продукты. Проверьте количество и повторите."
                )
            }
        }
    }

    override fun onCleared() {
        cameraFile?.let(discardCapture)
    }
}
