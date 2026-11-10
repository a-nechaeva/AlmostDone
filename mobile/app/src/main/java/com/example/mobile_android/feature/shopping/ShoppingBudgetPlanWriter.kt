package com.example.mobile_android.feature.shopping

import com.example.mobile_android.domain.Quantity

data class ShoppingPackageSelection(
    val ingredientId: String,
    val packageId: String,
    val packageQuantity: Quantity,
    val packageCount: Int,
)

@JvmInline value class BudgetPurchaseReceipt(val id: String)

sealed interface BudgetPlanAddition {
    data object AlreadyInList : BudgetPlanAddition

    data class Added(val receipt: BudgetPurchaseReceipt, val alreadyInList: Int) :
        BudgetPlanAddition
}

enum class BudgetPlanUndo {
    Restored,
    PurchasesChanged,
}

/** Implement against the same user-scoped store that publishes the shopping list. */
interface ShoppingBudgetPlanWriter {
    /**
     * Validate all package identities and quantities before committing. In one transaction, ensure
     * the requested package quantities are covered by the shared list. Leave covered lines alone
     * and return a receipt for the changed lines. An exception leaves no changes.
     */
    suspend fun add(packages: List<ShoppingPackageSelection>): BudgetPlanAddition

    /**
     * Restore the changes covered by the receipt in one transaction. If later edits have superseded
     * any affected line, leave the list intact and return PurchasesChanged. A transient exception
     * leaves the receipt usable for retry.
     */
    suspend fun undo(receipt: BudgetPurchaseReceipt): BudgetPlanUndo
}
