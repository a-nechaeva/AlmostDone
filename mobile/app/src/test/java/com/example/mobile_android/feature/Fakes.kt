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
        values.update { it.copy(favoriteRecipes = it.favoriteRecipes + id) }
    }

    override suspend fun addPantry(id: String, quantity: Quantity?) {
        values.update { it.copy(pantry = it.pantry + PantryItem(id, quantity)) }
    }

    override suspend fun setPantry(id: String, quantity: Quantity?) {
        error("Not used in this fake")
    }

    override suspend fun removePantry(id: String) {
        error("Not used in this fake")
    }

    override suspend fun planRecipe(id: String, servings: Int) {
        error("Not used in this fake")
    }

    override suspend fun removePlannedRecipe(id: String) {
        error("Not used in this fake")
    }

    override suspend fun addManualPurchase(id: String, quantity: Quantity) {
        error("Not used in this fake")
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
