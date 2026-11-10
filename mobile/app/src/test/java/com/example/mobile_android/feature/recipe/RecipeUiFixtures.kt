package com.example.mobile_android.feature.recipe

import com.example.mobile_android.data.DemoCatalog
import com.example.mobile_android.domain.*
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.*

internal class RecipeUiHousehold : HouseholdRepository {
    val values = MutableStateFlow(Household(pantry = DemoCatalog.initialPantry))
    var failRead = false
    var failWrite = false
    var gate: CompletableDeferred<Unit>? = null
    var favoriteCalls = 0
    var shoppingCalls = 0
    override val household: Flow<Household>
        get() = flow {
            if (failRead) throw java.io.IOException("fake read failure")
            emitAll(values)
        }

    private suspend fun write() {
        gate?.await()
        if (failWrite) throw java.io.IOException("fake write failure")
    }

    override suspend fun toggleFavorite(id: String, ingredient: Boolean) {
        check(!ingredient)
        favoriteCalls++
        write()
        values.update { it.copy(favoriteRecipes = if (id in it.favoriteRecipes) it.favoriteRecipes - id else it.favoriteRecipes + id) }
    }

    override suspend fun planRecipe(id: String, servings: Int) {
        shoppingCalls++
        write()
        values.update { it.copy(plan = it.plan.filterNot { row -> row.recipeId == id } + PlannedRecipe(id, servings)) }
    }

    override suspend fun setPantry(id: String, quantity: Quantity?) {
        values.update { it.copy(pantry = it.pantry.filterNot { row -> row.ingredientId == id } + PantryItem(id, quantity)) }
    }
    override suspend fun addPantry(id: String, quantity: Quantity?) = error("Unused")
    override suspend fun removePantry(id: String) = error("Unused")
    override suspend fun removePlannedRecipe(id: String) = error("Unused")
    override suspend fun addManualPurchase(id: String, quantity: Quantity) = error("Unused")
    override suspend fun removeManualPurchase(id: String) = error("Unused")
    override suspend fun toggleCheckedPurchase(id: String) = error("Unused")
    override suspend fun addCheckedPurchasesToPantry() = error("Unused")
}

internal class RecipeUiPreferences : PreferencesRepository {
    val values = MutableStateFlow(FoodPreferences())
    override val preferences = values
    override suspend fun update(transform: (FoodPreferences) -> FoodPreferences) { values.update(transform) }
}

internal fun recipeUiState(
    id: String = "cheese",
    pantry: List<PantryItem> = DemoCatalog.initialPantry,
    catalog: Catalog = DemoCatalog.catalog,
    servings: Int? = null,
): RecipeState {
    val recipe = catalog.recipe(id)
    val count = servings ?: recipe?.servings ?: 1
    return RecipeState(catalog, recipe?.let { matchRecipe(it, pantry, catalog, FoodPreferences(), count) }, false, false, recipe?.let { recipeRequirements(it, count) }.orEmpty())
}
