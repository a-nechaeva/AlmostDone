package com.example.mobile_android.feature.shopping

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.mobile_android.domain.*
import com.example.mobile_android.feature.common.*
import kotlinx.coroutines.flow.*

data class ShoppingState(
    val catalog: Catalog,
    val household: Household,
    val quote: ShoppingQuote,
    val budgetKopecks: Long,
    val suggestion: PurchaseSuggestion?,
    val planWarnings: List<String>,
)

class ShoppingViewModel(
    private val catalog: CatalogRepository,
    private val household: HouseholdRepository,
    private val preferences: PreferencesRepository,
    private val savedState: SavedStateHandle,
) : ViewModel() {
    private val refresh = MutableStateFlow(0)
    val actions = ScreenActions(viewModelScope)
    val state =
        loadingStates(refresh) {
                combine(
                    catalog.catalog,
                    household.household,
                    preferences.preferences,
                    savedState.getStateFlow("budget", 50000L),
                ) { c, h, p, budget ->
                    val warnings =
                        h.plan.mapNotNull { planned ->
                            val recipe =
                                c.recipe(planned.recipeId)
                                    ?: return@mapNotNull "Рецепт недоступен: уточните список покупок."
                            val assessment =
                                matchRecipe(recipe, h.pantry, c, p, planned.servings).dietary
                            if (assessment.status == Suitability.ALLOWED) null
                            else "${recipe.title}: ${assessment.reasons.joinToString("; ")}"
                        }
                    ShoppingState(
                        c,
                        h,
                        shoppingQuote(c, h),
                        budget,
                        suggestSinglePurchase(c, h, p, budget),
                        warnings,
                    )
                }
            }
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), ScreenState.Loading)

    fun retry() {
        refresh.update { it + 1 }
    }

    fun budgetChanged(value: Long) {
        savedState["budget"] = value.coerceIn(0, 100000000)
    }

    fun removeManual(id: String) = actions.run { household.removeManualPurchase(id) }

    fun toggleChecked(id: String) = actions.run { household.toggleCheckedPurchase(id) }

    fun removeRecipe(id: String) = actions.run { household.removePlannedRecipe(id) }

    fun addBoughtToPantry() =
        actions.run("Купленные продукты добавлены домой") {
            household.addCheckedPurchasesToPantry()
        }

    fun addSuggestion() {
        val suggestion = (state.value as? ScreenState.Ready)?.data?.suggestion ?: return
        actions.run("Покупка добавлена в список") {
            household.addManualPurchase(suggestion.ingredient.id, suggestion.quantity)
        }
    }
}
