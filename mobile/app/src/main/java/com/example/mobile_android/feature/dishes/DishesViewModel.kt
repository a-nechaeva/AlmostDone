package com.example.mobile_android.feature.dishes

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.mobile_android.domain.*
import com.example.mobile_android.feature.common.*
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.withContext

enum class Availability(val label: String) {
    ALL("Все"),
    NOW("Сейчас"),
    BUY("Докупить 1–3"),
}

data class DishFilters(
    val query: String = "",
    val maxMinutes: Int = 180,
    val maxKcal: Int = 3000,
    val method: String = "",
    val availability: Availability = Availability.ALL,
)

data class DishesState(
    val matches: List<RecipeMatch>,
    val household: Household,
    val filters: DishFilters,
) {
    val visible
        get() = matches.filter { it.dietary.status != Suitability.HIDDEN }

    val hidden
        get() = matches.filter { it.dietary.status == Suitability.HIDDEN }
}

class DishesViewModel(
    private val catalog: CatalogRepository,
    private val household: HouseholdRepository,
    private val preferences: PreferencesRepository,
    private val savedState: SavedStateHandle,
    private val computationDispatcher: CoroutineDispatcher = Dispatchers.Default,
) : ViewModel() {
    private val refresh = MutableStateFlow(0)
    val actions = ScreenActions(viewModelScope)
    private val filters =
        combine(
            savedState.getStateFlow("query", ""),
            savedState.getStateFlow("minutes", 180),
            savedState.getStateFlow("kcal", 3000),
            savedState.getStateFlow("method", ""),
            savedState.getStateFlow("availability", Availability.ALL.name),
        ) { q, t, k, m, a ->
            DishFilters(q, t, k, m, Availability.valueOf(a))
        }
    val state =
        loadingStates(refresh) {
                combine(catalog.catalog, household.household, preferences.preferences, filters) {
                    c,
                    h,
                    p,
                    f ->
                    withContext(computationDispatcher) {
                        val matches =
                            c.recipes
                                .filter { r ->
                                    r.title.contains(f.query.trim(), ignoreCase = true) &&
                                        r.minutes <= f.maxMinutes &&
                                        (f.maxKcal == 3000 ||
                                            r.nutritionPerServing?.kcal?.let { it <= f.maxKcal } ==
                                                true) &&
                                        (f.method.isBlank() ||
                                            r.methods.any { it.name == f.method })
                                }
                                .map { matchRecipe(it, h.pantry, c, p) }
                                .filter {
                                    when (f.availability) {
                                        Availability.ALL -> true
                                        Availability.NOW ->
                                            it.ready && it.dietary.status == Suitability.ALLOWED
                                        Availability.BUY ->
                                            it.dietary.status == Suitability.ALLOWED &&
                                                it.missing.size in 1..3 &&
                                                it.uncertainQuantityIds.isEmpty()
                                    }
                                }
                        DishesState(matches, h, f)
                    }
                }
            }
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), ScreenState.Loading)

    fun retry() {
        refresh.update { it + 1 }
    }

    fun queryChanged(value: String) {
        savedState["query"] = value.take(100)
    }

    fun maxMinutesChanged(value: Int) {
        savedState["minutes"] = value.coerceIn(5, 180)
    }

    fun maxKcalChanged(value: Int) {
        savedState["kcal"] = value.coerceIn(100, 3000)
    }

    fun methodChanged(value: String) {
        savedState["method"] = value
    }

    fun availabilityChanged(value: Availability) {
        savedState["availability"] = value.name
    }

    fun resetFilters() {
        savedState["minutes"] = 180
        savedState["kcal"] = 3000
        savedState["method"] = ""
        savedState["availability"] = Availability.ALL.name
        savedState["query"] = ""
    }

    fun favorite(id: String) = actions.run { household.toggleFavorite(id, false) }
}
