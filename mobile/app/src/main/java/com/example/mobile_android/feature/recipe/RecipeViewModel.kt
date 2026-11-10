package com.example.mobile_android.feature.recipe

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.mobile_android.domain.*
import com.example.mobile_android.feature.common.*
import kotlinx.coroutines.flow.*

data class RecipeState(
    val catalog: Catalog,
    val match: RecipeMatch?,
    val favorite: Boolean,
    val planned: Boolean,
    val requirements: List<Shortage>,
)

class RecipeViewModel(
    private val catalog: CatalogRepository,
    private val household: HouseholdRepository,
    private val preferences: PreferencesRepository,
    private val savedState: SavedStateHandle,
) : ViewModel() {
    private val id = checkNotNull(savedState.get<String>("recipeId"))
    private val refresh = MutableStateFlow(0)
    val actions = ScreenActions(viewModelScope)
    val state =
        loadingStates(refresh) {
                combine(
                    catalog.catalog,
                    household.household,
                    preferences.preferences,
                    savedState.getStateFlow("servings", 0),
                ) { c, h, p, servings ->
                    val recipe = c.recipe(id)
                    RecipeState(
                        c,
                        recipe?.let {
                            matchRecipe(
                                it,
                                h.pantry,
                                c,
                                p,
                                if (servings == 0) it.servings else servings,
                            )
                        },
                        id in h.favoriteRecipes,
                        h.plan.any { it.recipeId == id },
                        recipe
                            ?.let {
                                recipeRequirements(it, if (servings == 0) it.servings else servings)
                            }
                            .orEmpty(),
                    )
                }
            }
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), ScreenState.Loading)

    fun retry() {
        refresh.update { it + 1 }
    }

    fun servingsChanged(value: Int) {
        savedState["servings"] = value.coerceIn(1, 12)
    }

    fun favorite() = actions.run { household.toggleFavorite(id, false) }

    fun addToShopping() {
        val data = (state.value as? ScreenState.Ready)?.data ?: return
        val match = data.match ?: return
        actions.run("Рецепт добавлен в список покупок") { household.planRecipe(id, match.servings) }
    }
}
