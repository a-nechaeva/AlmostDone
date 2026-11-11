package com.example.mobile_android.feature.shopping

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.mobile_android.domain.Quantity
import com.example.mobile_android.domain.QuantityUnit
import com.example.mobile_android.ui.parseMoney
import com.example.mobile_android.ui.quantityLabel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * Покупки на бюджет. [computed] = false — фиксированный UI-пример (fake), true — подобрано
 * движком по продуктам дома и каталогу.
 */
data class ShoppingBudgetExample(
    val title: String,
    val packages: List<ShoppingBudgetPackage>,
    val alternativeRecipeIds: List<String>,
    val totalKopecks: Long?,
    val computed: Boolean = false,
)

data class ShoppingBudgetPackage(
    val ingredientId: String,
    val label: String,
    val quantity: Quantity,
    val priceKopecks: Long?,
    val packageId: String,
    val packageCount: Int = 1,
) {
    val packageLabel: String
        get() =
            if (packageCount == 1) "1 упаковка · ${quantityLabel(quantity)}"
            else "$packageCount × ${quantityLabel(quantity)}"

    internal fun selection() =
        ShoppingPackageSelection(ingredientId, packageId, quantity, packageCount)
}

fun interface ShoppingBudgetSource {
    suspend fun example(budgetKopecks: Long): ShoppingBudgetExample?
}

/** Selects between fixed demo replies; does not search recipes or calculate a plan. */
class FakeShoppingBudgetSource(
    private val reply: ShoppingBudgetExample? = READY,
) : ShoppingBudgetSource {
    override suspend fun example(budgetKopecks: Long) =
        if (reply?.totalKopecks?.let { it > budgetKopecks } == true) null else reply

    companion object {
        val READY =
            ShoppingBudgetExample(
                title = "Пример покупки с сыром",
                packages =
                    listOf(
                        ShoppingBudgetPackage(
                            "hard-cheese",
                            "Твёрдый сыр",
                            Quantity(200.0, QuantityUnit.GRAM),
                            23000,
                            packageId = "hard-cheese-200g",
                        )
                    ),
                alternativeRecipeIds = listOf("cheese", "cheeseEgg"),
                totalKopecks = 23000,
            )
        val UNKNOWN_PRICE =
            READY.copy(
                packages = READY.packages.map { it.copy(priceKopecks = null) },
                totalKopecks = null,
            )
    }
}

enum class ShoppingBudgetEstimate {
    WITHIN_EXAMPLE_BUDGET,
    ABOVE_EXAMPLE_BUDGET,
    UNKNOWN,
}

sealed interface ShoppingBudgetResult {
    data object Idle : ShoppingBudgetResult

    data object Loading : ShoppingBudgetResult

    data object Empty : ShoppingBudgetResult

    data object Error : ShoppingBudgetResult

    data class Ready(
        val example: ShoppingBudgetExample,
        val estimate: ShoppingBudgetEstimate,
        val remainingKopecks: Long?,
    ) : ShoppingBudgetResult
}

data class ShoppingBudgetForm(
    val text: String = "500",
    val invalid: Boolean = false,
    val result: ShoppingBudgetResult = ShoppingBudgetResult.Idle,
)

internal data class BudgetPlanWriteState(
    val pending: Boolean = false,
    val message: String? = null,
    val error: Boolean = false,
    val retryAdd: Boolean = false,
    val canUndo: Boolean = false,
)

class ShoppingBudgetViewModel(
    private val savedState: SavedStateHandle,
    private val source: ShoppingBudgetSource = FakeShoppingBudgetSource(),
    private val planWriter: ShoppingBudgetPlanWriter? = null,
) : ViewModel() {
    private val mutableForm =
        MutableStateFlow(
            ShoppingBudgetForm(text = savedState["shopping-budget-text"] ?: "500"),
        )
    val form = mutableForm.asStateFlow()
    private val mutableWrite = MutableStateFlow(BudgetPlanWriteState())
    internal val write = mutableWrite.asStateFlow()
    private var undoReceipt: BudgetPurchaseReceipt? = null
    private var request: Job? = null
    private var revision = 0L

    fun textChanged(value: String) {
        if (mutableWrite.value.pending) return
        revision++
        request?.cancel()
        savedState["shopping-budget-text"] = value
        mutableForm.value =
            ShoppingBudgetForm(
                text = value,
                invalid = value.isNotBlank() && parseMoney(value) == null,
            )
    }

    fun submit() {
        if (mutableWrite.value.pending || mutableForm.value.result == ShoppingBudgetResult.Loading)
            return
        val budget = parseMoney(mutableForm.value.text)
        if (budget == null) {
            mutableForm.value = mutableForm.value.copy(invalid = true)
            return
        }
        val version = ++revision
        mutableForm.value =
            mutableForm.value.copy(invalid = false, result = ShoppingBudgetResult.Loading)
        request =
            viewModelScope.launch {
                val result =
                    try {
                        val example = source.example(budget)
                        if (example == null || example.packages.isEmpty())
                            ShoppingBudgetResult.Empty
                        else {
                            val estimate = example.estimate(budget)
                            ShoppingBudgetResult.Ready(
                                example,
                                estimate,
                                if (estimate == ShoppingBudgetEstimate.WITHIN_EXAMPLE_BUDGET)
                                    budget - requireNotNull(example.totalKopecks)
                                else null,
                            )
                        }
                    } catch (cancelled: CancellationException) {
                        throw cancelled
                    } catch (_: Exception) {
                        ShoppingBudgetResult.Error
                    }
                if (version == revision) mutableForm.value = mutableForm.value.copy(result = result)
            }
    }

    fun retry() = submit()

    fun clearResult() {
        if (mutableWrite.value.pending) return
        if (mutableWrite.value.retryAdd)
            mutableWrite.value = BudgetPlanWriteState(canUndo = undoReceipt != null)
        revision++
        request?.cancel()
        mutableForm.value = mutableForm.value.copy(result = ShoppingBudgetResult.Idle)
    }

    internal fun addPlan() {
        val writer = planWriter ?: return
        val result = mutableForm.value.result as? ShoppingBudgetResult.Ready ?: return
        if (result.estimate != ShoppingBudgetEstimate.WITHIN_EXAMPLE_BUDGET) return
        writePlan(failure = "Не удалось добавить план в покупки.", retryAdd = true) {
            when (val addition = writer.add(result.example.packages.map { it.selection() })) {
                BudgetPlanAddition.AlreadyInList -> "План уже в покупках"
                is BudgetPlanAddition.Added -> {
                    undoReceipt = addition.receipt
                    if (addition.alreadyInList == 0) "План добавлен в покупки"
                    else "План добавлен. Некоторые позиции уже в покупках."
                }
            }
        }
    }

    internal fun undoPlan() {
        val writer = planWriter ?: return
        val receipt = undoReceipt ?: return
        writePlan(failure = "Не удалось отменить добавление.") {
            val result = writer.undo(receipt)
            undoReceipt = null
            when (result) {
                BudgetPlanUndo.Restored -> "Добавление отменено"
                BudgetPlanUndo.PurchasesChanged ->
                    "Список изменился. Отменить добавление уже нельзя."
            }
        }
    }

    private fun writePlan(
        failure: String,
        retryAdd: Boolean = false,
        operation: suspend () -> String,
    ) {
        if (mutableWrite.value.pending) return
        mutableWrite.value = BudgetPlanWriteState(pending = true)
        viewModelScope.launch {
            try {
                val message = operation()
                mutableWrite.value =
                    BudgetPlanWriteState(message = message, canUndo = undoReceipt != null)
            } catch (cancelled: CancellationException) {
                mutableWrite.value = BudgetPlanWriteState(canUndo = undoReceipt != null)
                throw cancelled
            } catch (_: Exception) {
                mutableWrite.value =
                    BudgetPlanWriteState(
                        message = failure,
                        error = true,
                        retryAdd = retryAdd,
                        canUndo = undoReceipt != null,
                    )
            }
        }
    }
}

private fun ShoppingBudgetExample.estimate(budget: Long): ShoppingBudgetEstimate {
    val total = totalKopecks
    return when {
        total == null ||
            total < 0 ||
            packages.any { it.priceKopecks == null || it.priceKopecks < 0 } ->
            ShoppingBudgetEstimate.UNKNOWN
        total > budget -> ShoppingBudgetEstimate.ABOVE_EXAMPLE_BUDGET
        else -> ShoppingBudgetEstimate.WITHIN_EXAMPLE_BUDGET
    }
}
