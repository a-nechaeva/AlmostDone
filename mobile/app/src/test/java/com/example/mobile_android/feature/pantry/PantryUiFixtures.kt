package com.example.mobile_android.feature.pantry

import com.example.mobile_android.data.DemoCatalog
import com.example.mobile_android.domain.*
import java.io.IOException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.*

internal class PantryUiHousehold : HouseholdRepository {
    val values = MutableStateFlow(Household(pantry = DemoCatalog.initialPantry))
    var failRead = false
    var failWrite = false
    var gate: CompletableDeferred<Unit>? = null
    val calls = mutableListOf<Pair<String, Quantity?>>()
    override val household: Flow<Household>
        get() = flow {
            if (failRead) throw IOException("read unavailable")
            emitAll(values)
        }

    private suspend fun write() {
        gate?.await()
        if (failWrite) throw IOException("write unavailable")
    }

    override suspend fun addPantry(id: String, quantity: Quantity?) {
        calls += "add:$id" to quantity
        write()
        requireNotNull(DemoCatalog.catalog.ingredient(id))
        require(quantity == null || quantity.unit == DemoCatalog.catalog.ingredient(id)?.unit)
        val old = values.value.pantry.find { it.ingredientId == id }
        require(old?.quantity == null || quantity == null || old.quantity.unit == quantity.unit)
        val total =
            if (old == null) quantity
            else if (old.quantity == null || quantity == null) null
            else Quantity(old.quantity.value + quantity.value, quantity.unit)
        values.update {
            it.copy(
                pantry =
                    it.pantry.filterNot { row -> row.ingredientId == id } + PantryItem(id, total)
            )
        }
    }

    override suspend fun setPantry(id: String, quantity: Quantity?) {
        calls += "set:$id" to quantity
        write()
        values.update {
            it.copy(
                pantry =
                    it.pantry.filterNot { row -> row.ingredientId == id } +
                        listOfNotNull(
                            if (quantity?.value == 0.0) null else PantryItem(id, quantity)
                        )
            )
        }
    }

    override suspend fun removePantry(id: String) {
        calls += "remove:$id" to null
        write()
        values.update { it.copy(pantry = it.pantry.filterNot { row -> row.ingredientId == id }) }
    }

    override suspend fun toggleFavorite(id: String, ingredient: Boolean) {
        write()
        values.update {
            it.copy(
                favoriteIngredients =
                    if (id in it.favoriteIngredients) it.favoriteIngredients - id
                    else it.favoriteIngredients + id
            )
        }
    }

    override suspend fun planRecipe(id: String, servings: Int) = error("unused")

    override suspend fun removePlannedRecipe(id: String) = error("unused")

    override suspend fun addManualPurchase(id: String, quantity: Quantity) = error("unused")

    override suspend fun removeManualPurchase(id: String) = error("unused")

    override suspend fun toggleCheckedPurchase(id: String) = error("unused")

    override suspend fun addCheckedPurchasesToPantry() = error("unused")
}
