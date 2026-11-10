package com.example.mobile_android.feature.favorites

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.mobile_android.domain.*
import com.example.mobile_android.feature.common.*
import com.example.mobile_android.feature.favorites.FavoritesPantryWrite.Phase
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch

data class FavoritesState(
    val recipes: List<RecipeMatch>,
    val ingredients: List<Ingredient>,
    val household: Household,
)

internal data class FavoritesPantryWrite(
    val phase: Phase = Phase.Idle,
    val revision: Long = 0,
) {
    enum class Phase { Idle, Saving, Added, Failed }
}

class FavoritesViewModel(
    private val catalog: CatalogRepository,
    private val household: HouseholdRepository,
    private val preferences: PreferencesRepository,
) : ViewModel() {
    private val refresh = MutableStateFlow(0)
    private val mutablePantryWrite = MutableStateFlow(FavoritesPantryWrite())
    internal val pantryWrite = mutablePantryWrite.asStateFlow()
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

    internal fun addIngredientToPantry(selection: FavoritesIngredientSelection, revision: Long) {
        if (actions.state.value.pending) return
        val current = pantryWrite.value
        // An instant failure must still require a click from the new retry button.
        if (current.revision != revision) return
        if (current.phase != Phase.Idle && current.phase != Phase.Failed) return

        val saving = FavoritesPantryWrite(Phase.Saving, revision + 1)
        mutablePantryWrite.value = saving
        viewModelScope.launch {
            try {
                household.addPantry(selection.ingredientId, selection.quantity)
                mutablePantryWrite.value = saving.copy(phase = Phase.Added)
            } catch (cancelled: CancellationException) {
                mutablePantryWrite.value = saving.copy(phase = Phase.Idle)
                throw cancelled
            } catch (_: Exception) {
                mutablePantryWrite.value = saving.copy(phase = Phase.Failed)
            }
        }
    }

    internal fun tryDismissPantryWrite(): Boolean {
        val current = pantryWrite.value
        if (current.phase == Phase.Saving) return false
        mutablePantryWrite.value = FavoritesPantryWrite(revision = current.revision + 1)
        return true
    }

    fun favorite(id: String, ingredient: Boolean) {
        if (pantryWrite.value.phase == Phase.Saving) return
        actions.run {
            // This screen removes favorites. A repeated click on a stale card must not add it back.
            val current = household.household.first()
            val ids = if (ingredient) current.favoriteIngredients else current.favoriteRecipes
            if (id in ids) household.toggleFavorite(id, ingredient)
        }
    }
}
