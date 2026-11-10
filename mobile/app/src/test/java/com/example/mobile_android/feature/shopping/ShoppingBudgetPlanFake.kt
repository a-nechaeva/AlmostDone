package com.example.mobile_android.feature.shopping

import com.example.mobile_android.data.DemoCatalog
import com.example.mobile_android.domain.Household
import com.example.mobile_android.domain.ManualPurchase
import com.example.mobile_android.domain.Quantity
import com.example.mobile_android.domain.QuantityUnit
import com.example.mobile_android.domain.ShoppingLine
import com.example.mobile_android.domain.ShoppingQuote
import com.example.mobile_android.domain.shoppingQuote
import java.io.IOException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

internal val twoPackageBudgetExample =
    FakeShoppingBudgetSource.READY.let { cheese ->
        cheese.copy(
            packages =
                cheese.packages +
                    ShoppingBudgetPackage(
                        "tomatoes",
                        "Томаты",
                        Quantity(500.0, QuantityUnit.GRAM),
                        16000,
                        packageId = "tomatoes-500g",
                    ),
            totalKopecks = 39000,
        )
    }

internal class ShoppingBudgetPlanFake(private val household: ShoppingUiHousehold) :
    ShoppingBudgetPlanWriter {
    private val catalog = DemoCatalog.catalog
    private val mutex = Mutex()
    private val receipts = mutableMapOf<BudgetPurchaseReceipt, Change>()
    private var nextReceipt = 0
    var gate: CompletableDeferred<Unit>? = null
    var undoGate: CompletableDeferred<Unit>? = null
    var failAdd = false
    var failUndo = false
    val submissions = mutableListOf<List<ShoppingPackageSelection>>()

    override suspend fun add(packages: List<ShoppingPackageSelection>): BudgetPlanAddition =
        mutex.withLock {
            submissions += packages.toList()
            gate?.await()
            val selected = packages.map(::resolve)
            require(
                selected.isNotEmpty() &&
                    selected.distinctBy { it.ingredientId }.size == selected.size
            )
            val before = household.values.value
            val quote = shoppingQuote(catalog, before)
            val missing =
                selected.filter { item ->
                    val current =
                        quote.lines.find { it.ingredientId == item.ingredientId }?.buyQuantity
                    current == null ||
                        current.unit != item.quantity.unit ||
                        current.value < item.quantity.value
                }
            if (missing.isEmpty()) return@withLock BudgetPlanAddition.AlreadyInList

            val existingIds = before.manualPurchases.map { it.ingredientId }.toSet()
            val replacements = missing.associateBy { it.ingredientId }
            val after =
                before.copy(
                    manualPurchases =
                        before.manualPurchases.map { replacements[it.ingredientId] ?: it } +
                            missing.filterNot { it.ingredientId in existingIds },
                    checkedPurchases = before.checkedPurchases - replacements.keys,
                )
            val updatedQuote = shoppingQuote(catalog, after)
            require(
                missing.all { item ->
                    val quantity =
                        updatedQuote.lines
                            .find { it.ingredientId == item.ingredientId }
                            ?.buyQuantity
                    quantity != null &&
                        quantity.unit == item.quantity.unit &&
                        quantity.value >= item.quantity.value
                }
            )
            if (failAdd) throw IOException("test commit failure")
            check(household.values.compareAndSet(before, after))
            val receipt = BudgetPurchaseReceipt((++nextReceipt).toString())
            receipts[receipt] =
                Change(
                    snapshot(before, quote, replacements.keys),
                    snapshot(after, updatedQuote, replacements.keys),
                )
            BudgetPlanAddition.Added(receipt, selected.size - missing.size)
        }

    override suspend fun undo(receipt: BudgetPurchaseReceipt): BudgetPlanUndo =
        mutex.withLock {
            val change = receipts[receipt] ?: return@withLock BudgetPlanUndo.PurchasesChanged
            undoGate?.await()
            val current = household.values.value
            val ids = change.before.keys
            if (snapshot(current, shoppingQuote(catalog, current), ids) != change.after) {
                receipts.remove(receipt)
                return@withLock BudgetPlanUndo.PurchasesChanged
            }
            if (failUndo) throw IOException("test undo failure")
            val restored =
                current.copy(
                    manualPurchases =
                        current.manualPurchases.mapNotNull { row ->
                            if (row.ingredientId in ids)
                                change.before.getValue(row.ingredientId).manual
                            else row
                        },
                    checkedPurchases =
                        current.checkedPurchases - ids +
                            change.before.filterValues { it.checked }.keys,
                )
            check(household.values.compareAndSet(current, restored))
            receipts.remove(receipt)
            BudgetPlanUndo.Restored
        }

    private fun resolve(packageSelection: ShoppingPackageSelection): ManualPurchase {
        val ingredient = requireNotNull(catalog.ingredient(packageSelection.ingredientId))
        val packageId =
            when (ingredient.id) {
                "hard-cheese" -> "hard-cheese-200g"
                "tomatoes" -> "tomatoes-500g"
                else -> error("No package fixture for ${ingredient.id}")
            }
        val offer = requireNotNull(ingredient.offer)
        require(
            packageSelection.packageId == packageId &&
                packageSelection.packageQuantity == offer.quantity &&
                packageSelection.packageCount > 0
        )
        return ManualPurchase(
            ingredient.id,
            offer.quantity.copy(value = offer.quantity.value * packageSelection.packageCount),
        )
    }

    private fun snapshot(household: Household, quote: ShoppingQuote, ids: Set<String>) =
        ids.associateWith { id ->
            PurchaseSnapshot(
                household.manualPurchases.find { it.ingredientId == id },
                quote.lines.find { it.ingredientId == id },
                id in household.checkedPurchases,
            )
        }

    private data class PurchaseSnapshot(
        val manual: ManualPurchase?,
        val line: ShoppingLine?,
        val checked: Boolean,
    )

    private data class Change(
        val before: Map<String, PurchaseSnapshot>,
        val after: Map<String, PurchaseSnapshot>,
    )
}
