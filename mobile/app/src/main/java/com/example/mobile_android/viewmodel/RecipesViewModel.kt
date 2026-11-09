package com.example.mobile_android.viewmodel

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import com.example.mobile_android.data.model.CookingMethod
import com.example.mobile_android.data.model.Recipe
import com.example.mobile_android.data.repository.RecipeRepository

data class RecipesUiState(
    val allRecipes: List<Recipe> = RecipeRepository.recipes,
    val visibleRecipes: List<Recipe> = emptyList(),
    val showFilters: Boolean = false,
    val maxTime: Int = 180,
    val maxKcal: Int = 3000,
    val methods: Set<CookingMethod> = emptySet(),
)

class RecipesViewModel : ViewModel() {
    var uiState by mutableStateOf(RecipesUiState())
        private set

    init { applyFilters() }

    fun toggleFiltersPanel() { uiState = uiState.copy(showFilters = !uiState.showFilters) }
    fun setMaxTime(value: Int) { uiState = uiState.copy(maxTime = value); applyFilters() }
    fun setMaxKcal(value: Int) { uiState = uiState.copy(maxKcal = value); applyFilters() }
    fun toggleMethod(method: CookingMethod) {
        val set = uiState.methods
        uiState = uiState.copy(methods = if (method in set) set - method else set + method)
        applyFilters()
    }

    private fun applyFilters() {
        // Требование 5: позже добавить аллергены и учёт профиля
        val filtered = uiState.allRecipes.filter { recipe ->
            val m = RecipeRepository.metrics(recipe)
            recipe.timeMinutes <= uiState.maxTime &&
                    m.kcal <= uiState.maxKcal &&
                    (uiState.methods.isEmpty() || uiState.methods.intersect(recipe.methods).isNotEmpty())
        }
        uiState = uiState.copy(visibleRecipes = filtered)
    }
}