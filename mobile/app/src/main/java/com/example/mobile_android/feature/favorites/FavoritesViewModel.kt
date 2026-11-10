package com.example.mobile_android.feature.favorites

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.mobile_android.domain.*
import com.example.mobile_android.feature.common.*
import kotlinx.coroutines.flow.*

data class FavoritesState(
    val recipes: List<RecipeMatch>,
    val ingredients: List<Ingredient>,
    val household: Household,
)

class FavoritesViewModel(
    private val catalog: CatalogRepository,
    private val household: HouseholdRepository,
    private val preferences: PreferencesRepository,
) : ViewModel() {
    private val refresh = MutableStateFlow(0)
    val actions = ScreenActions(viewModelScope)
    val state =
        loadingStates(refresh) {
                combine(catalog.catalog, household.household, preferences.preferences) { c, h, p ->
                    FavoritesState(
                        c.recipes
                            .filter { it.id in h.favoriteRecipes }
                            .map { matchRecipe(it, h.pantry, c, p) },
                        c.ingredients.filter { it.id in h.favoriteIngredients },
                        h,
                    )
                }
            }
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), ScreenState.Loading)

    fun retry() {
        refresh.update { it + 1 }
    }

    fun favorite(id: String, ingredient: Boolean) =
        actions.run {
            // This screen removes favorites. A repeated click on a stale card must not add it back.
            val current = household.household.first()
            val ids = if (ingredient) current.favoriteIngredients else current.favoriteRecipes
            if (id in ids) household.toggleFavorite(id, ingredient)
        }
}
