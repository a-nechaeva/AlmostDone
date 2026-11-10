package com.example.mobile_android.feature

import com.example.mobile_android.data.DemoCatalog
import com.example.mobile_android.domain.*
import java.io.IOException
import kotlinx.coroutines.flow.*

class FakeHousehold : HouseholdRepository {
    val values = MutableStateFlow(Household(pantry = DemoCatalog.initialPantry))
    var failRead = false
    var failWrite = false
    override val household: Flow<Household>
        get() = flow {
            if (failRead) throw IOException("storage unavailable")
            emitAll(values)
        }

    override suspend fun toggleFavorite(id: String, ingredient: Boolean) {
        if (failWrite) throw IOException("storage unavailable")
        values.update {
            fun Set<String>.toggle() = if (id in this) this - id else this + id
            if (ingredient) it.copy(favoriteIngredients = it.favoriteIngredients.toggle())
            else it.copy(favoriteRecipes = it.favoriteRecipes.toggle())
        }
    }

    override suspend fun addPantry(id: String, quantity: Quantity?) {
        if (failWrite) throw IOException("storage unavailable")
        values.update { state ->
            val old = state.pantry.find { it.ingredientId == id }
            require(old?.quantity == null || quantity == null || old.quantity.unit == quantity.unit)
            val total =
                if (old == null) quantity
                else if (old.quantity == null || quantity == null) null
                else Quantity(old.quantity.value + quantity.value, quantity.unit)
            state.copy(
                pantry = state.pantry.filterNot { it.ingredientId == id } + PantryItem(id, total)
            )
        }
    }

    override suspend fun setPantry(id: String, quantity: Quantity?) {
        if (failWrite) throw IOException("storage unavailable")
        values.update {
            it.copy(
                pantry =
                    it.pantry.filterNot { row -> row.ingredientId == id } + PantryItem(id, quantity)
            )
        }
    }

    override suspend fun removePantry(id: String) {
        if (failWrite) throw IOException("storage unavailable")
        values.update { it.copy(pantry = it.pantry.filterNot { row -> row.ingredientId == id }) }
    }

    override suspend fun planRecipe(id: String, servings: Int) {
        error("Not used in this fake")
    }

    override suspend fun removePlannedRecipe(id: String) {
        error("Not used in this fake")
    }

    override suspend fun addManualPurchase(id: String, quantity: Quantity) {
        if (failWrite) throw IOException("storage unavailable")
        require(quantity.value > 0)
        require(DemoCatalog.catalog.ingredient(id)?.unit == quantity.unit)
        values.update {
            it.copy(
                manualPurchases =
                    it.manualPurchases.filterNot { row -> row.ingredientId == id } +
                        ManualPurchase(id, quantity)
            )
        }
    }

    override suspend fun removeManualPurchase(id: String) {
        error("Not used in this fake")
    }

    override suspend fun toggleCheckedPurchase(id: String) {
        error("Not used in this fake")
    }

    override suspend fun addCheckedPurchasesToPantry() {
        error("Not used in this fake")
    }
}

class FakePreferences : PreferencesRepository {
    val values = MutableStateFlow(FoodPreferences())
    var failRead = false
    override val preferences: Flow<FoodPreferences>
        get() = flow {
            if (failRead) throw IOException("profile unavailable")
            emitAll(values)
        }

    override suspend fun update(transform: (FoodPreferences) -> FoodPreferences) {
        values.update(transform)
    }
}
