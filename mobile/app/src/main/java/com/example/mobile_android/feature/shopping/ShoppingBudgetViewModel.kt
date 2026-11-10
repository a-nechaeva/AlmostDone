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

/** UI-only examples. These responses do not represent a calculated cooking plan. */
data class ShoppingBudgetExample(
    val title: String,
    val packages: List<ShoppingBudgetPackage>,
    val alternativeRecipeIds: List<String>,
    val totalKopecks: Long?,
)

data class ShoppingBudgetPackage(
    val ingredientId: String,
    val label: String,
    val quantity: Quantity,
    val priceKopecks: Long?,
) {
    val packageLabel: String
        get() = "1 упаковка · ${quantityLabel(quantity)}"
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
                        ),
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
    ) : ShoppingBudgetResult
}

data class ShoppingBudgetForm(
    val text: String = "500",
    val invalid: Boolean = false,
    val result: ShoppingBudgetResult = ShoppingBudgetResult.Idle,
)

class ShoppingBudgetViewModel(
    private val savedState: SavedStateHandle,
    private val source: ShoppingBudgetSource = FakeShoppingBudgetSource(),
) : ViewModel() {
    private val mutableForm =
        MutableStateFlow(
            ShoppingBudgetForm(text = savedState["shopping-budget-text"] ?: "500"),
        )
    val form = mutableForm.asStateFlow()
    private var request: Job? = null
    private var revision = 0L

    fun textChanged(value: String) {
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
        if (mutableForm.value.result == ShoppingBudgetResult.Loading) return
        val budget = parseMoney(mutableForm.value.text)
        if (budget == null) {
            mutableForm.value = mutableForm.value.copy(invalid = true)
            return
        }
        val version = ++revision
        mutableForm.value =
            mutableForm.value.copy(invalid = false, result = ShoppingBudgetResult.Loading)
        request = viewModelScope.launch {
            val result =
                try {
                    val example = source.example(budget)
                    if (example == null || example.packages.isEmpty()) ShoppingBudgetResult.Empty
                    else ShoppingBudgetResult.Ready(example, example.estimate(budget))
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
        revision++
        request?.cancel()
        mutableForm.value = mutableForm.value.copy(result = ShoppingBudgetResult.Idle)
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
