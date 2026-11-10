package com.example.mobile_android.feature.favorites

import com.example.mobile_android.data.DemoCatalog
import com.example.mobile_android.domain.*
import java.io.IOException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.*

internal class FavoritesHouseholdFake(initial: Household = Household()) : HouseholdRepository {
    val values = MutableStateFlow(initial)
    var failRead = false
    var failWrite = false
    var writeGate: CompletableDeferred<Unit>? = null
    val writes = mutableListOf<Pair<String, Boolean>>()
    override val household: Flow<Household>
        get() = flow {
            if (failRead) throw IOException("read")
            emitAll(values)
        }

    override suspend fun toggleFavorite(id: String, ingredient: Boolean) {
        writes += id to ingredient
        writeGate?.await()
        if (failWrite) throw IOException("write")
        values.update { current ->
            fun toggle(ids: Set<String>) = if (id in ids) ids - id else ids + id
            if (ingredient) current.copy(favoriteIngredients = toggle(current.favoriteIngredients))
            else current.copy(favoriteRecipes = toggle(current.favoriteRecipes))
        }
    }

    override suspend fun addPantry(id: String, quantity: Quantity?) = error("Not used")
    override suspend fun setPantry(id: String, quantity: Quantity?) = error("Not used")
    override suspend fun removePantry(id: String) = error("Not used")
    override suspend fun planRecipe(id: String, servings: Int) = error("Not used")
    override suspend fun removePlannedRecipe(id: String) = error("Not used")
    override suspend fun addManualPurchase(id: String, quantity: Quantity) = error("Not used")
    override suspend fun removeManualPurchase(id: String) = error("Not used")
    override suspend fun toggleCheckedPurchase(id: String) = error("Not used")
    override suspend fun addCheckedPurchasesToPantry() = error("Not used")
}

internal class FavoritesPreferencesFake : PreferencesRepository {
    val values = MutableStateFlow(FoodPreferences())
    override val preferences: Flow<FoodPreferences> = values
    override suspend fun update(transform: (FoodPreferences) -> FoodPreferences) {
        values.update(transform)
    }
}

internal fun favoritesFixture(
    recipeIds: Set<String> = setOf("omelette", "cheese"),
    ingredientIds: Set<String> = setOf("eggs", "tomatoes"),
    catalog: Catalog = DemoCatalog.catalog,
): FavoritesState {
    val household = Household(pantry = DemoCatalog.initialPantry, favoriteRecipes = recipeIds, favoriteIngredients = ingredientIds)
    return FavoritesState(
        catalog.recipes.filter { it.id in recipeIds }.map {
            matchRecipe(it, household.pantry, catalog, FoodPreferences())
        },
        catalog.ingredients.filter { it.id in ingredientIds },
        household,
    )
}
