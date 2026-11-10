package com.example.mobile_android.feature.shopping

import com.example.mobile_android.domain.*
import java.io.IOException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.*

internal class ShoppingUiHousehold : HouseholdRepository {
    val values =
        MutableStateFlow(
            Household(
                manualPurchases =
                    listOf(ManualPurchase("hard-cheese", Quantity(200.0, QuantityUnit.GRAM))),
            ),
        )
    var failRead = false
    var failWrite = false
    var writeGate: CompletableDeferred<Unit>? = null
    var toggleCalls = 0
    var checkoutCalls = 0
    override val household: Flow<Household>
        get() = flow {
            if (failRead) throw IOException("test read failure")
            emitAll(values)
        }

    override suspend fun toggleCheckedPurchase(id: String) {
        toggleCalls++
        writeGate?.await()
        if (failWrite) throw IOException("test write failure")
        values.update {
            it.copy(
                checkedPurchases =
                    if (id in it.checkedPurchases) it.checkedPurchases - id
                    else it.checkedPurchases + id,
            )
        }
    }

    override suspend fun addCheckedPurchasesToPantry() {
        checkoutCalls++
    }

    override suspend fun addManualPurchase(id: String, quantity: Quantity) {
        if (failWrite) throw IOException("test write failure")
        values.update { state ->
            state.copy(
                manualPurchases =
                    state.manualPurchases.filterNot { it.ingredientId == id } +
                        ManualPurchase(id, quantity),
            )
        }
    }

    override suspend fun removeManualPurchase(id: String) {
        values.update {
            it.copy(
                manualPurchases = it.manualPurchases.filterNot { row -> row.ingredientId == id },
            )
        }
    }

    override suspend fun removePlannedRecipe(id: String) {
        values.update { it.copy(plan = it.plan.filterNot { row -> row.recipeId == id }) }
    }

    override suspend fun addPantry(id: String, quantity: Quantity?) = error("Unused")

    override suspend fun setPantry(id: String, quantity: Quantity?) = error("Unused")

    override suspend fun removePantry(id: String) = error("Unused")

    override suspend fun toggleFavorite(id: String, ingredient: Boolean) = error("Unused")

    override suspend fun planRecipe(id: String, servings: Int) = error("Unused")
}

internal class ShoppingUiPreferences : PreferencesRepository {
    override val preferences = MutableStateFlow(FoodPreferences())

    override suspend fun update(transform: (FoodPreferences) -> FoodPreferences) {
        preferences.update(transform)
    }
}
