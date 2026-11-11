package com.example.mobile_android.feature.dishes

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.mobile_android.domain.*
import com.example.mobile_android.feature.common.*
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.withContext

enum class Availability(val label: String) {
    ALL("Все"),
    NOW("Сейчас"),
    BUY("Докупить 1–3"),
}

enum class DishesView(val label: String) {
    LIST("Список"),
    GRAPH("Граф"),
}

internal const val ANY_MINUTES = 0
internal const val MAX_MINUTES = 180
private const val ANY_KCAL = 3000

data class DishFilters(
    val query: String = "",
    val maxMinutes: Int = ANY_MINUTES,
    val maxKcal: Int = ANY_KCAL,
    val method: String = "",
    val availability: Availability = Availability.ALL,
    val excludedAllergens: Set<Allergen> = emptySet(),
) {
    val hasTimeLimit: Boolean
        get() = maxMinutes != ANY_MINUTES

    val hasCalorieLimit: Boolean
        get() = maxKcal != ANY_KCAL
}

data class DishesState(
    val matches: List<RecipeMatch>,
    val household: Household,
    val filters: DishFilters,
    val suggestion: PurchaseSuggestion?,
    val ingredientNames: Map<String, String> = emptyMap(),
    internal val inputRevision: Long = 0,
) {
    val visible = matches.filter { it.dietary.status != Suitability.HIDDEN }
    val hidden = matches.filter { it.dietary.status == Suitability.HIDDEN }
}

@OptIn(ExperimentalCoroutinesApi::class)
class DishesViewModel(
    private val catalog: CatalogRepository,
    private val household: HouseholdRepository,
    private val preferences: PreferencesRepository,
    private val savedState: SavedStateHandle,
    private val computationDispatcher: CoroutineDispatcher = Dispatchers.Default,
) : ViewModel() {
    private val refresh = MutableStateFlow(0)
    private val revision = MutableStateFlow(0L)
    internal val inputRevision = revision.asStateFlow()
    val actions = ScreenActions(viewModelScope)
    val view = savedState.getStateFlow("dishesView", DishesView.LIST.name)
    // The field keeps its input and caret while a result is being recomputed.
    val query = savedState.getStateFlow("query", "")
    private val selection =
        MutableStateFlow(
            DishFilters(
                query = query.value,
                maxMinutes = savedState["minutes"] ?: ANY_MINUTES,
                maxKcal = savedState["kcal"] ?: ANY_KCAL,
                method = savedState["method"] ?: "",
                availability =
                    Availability.entries.firstOrNull {
                        it.name == savedState.get<String>("availability")
                    } ?: Availability.ALL,
                excludedAllergens =
                    savedState
                        .get<ArrayList<String>>("dishesExcludedAllergens")
                        .orEmpty()
                        .mapNotNull { name -> Allergen.entries.find { it.name == name } }
                        .toSet(),
            )
        )
    val filters = selection.asStateFlow()

    val state =
        loadingStates(refresh) {
                combine(
                        catalog.catalog,
                        household.household,
                        preferences.preferences,
                        filters,
                        ::DishesInput,
                    )
                    .map { input ->
                        val next = revision.value + 1
                        revision.value = next
                        next to input
                    }
                    .mapLatest { (version, input) ->
                        withContext(computationDispatcher) { input.calculate(version) }
                    }
                    .buffer(0)
                    .filter { it.filters == filters.value && it.inputRevision == revision.value }
            }
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), ScreenState.Loading)

    fun retry() {
        revision.update { it + 1 }
        refresh.update { it + 1 }
    }

    fun viewChanged(value: DishesView) {
        savedState["dishesView"] = value.name
    }

    fun addPurchase() {
        val result = (state.value as? ScreenState.Ready)?.data ?: return
        if (result.filters != filters.value || result.inputRevision != revision.value) return
        val suggestion = result.suggestion ?: return
        actions.run("Покупка добавлена в список") {
            household.addManualPurchase(suggestion.ingredient.id, suggestion.quantity)
        }
    }

    fun queryChanged(value: String) = select(filters.value.copy(query = value.take(100)))

    fun maxMinutesChanged(value: Int) =
        select(
            filters.value.copy(
                maxMinutes =
                    if (value == ANY_MINUTES) ANY_MINUTES else value.coerceIn(5, MAX_MINUTES)
            )
        )

    fun maxKcalChanged(value: Int) =
        select(filters.value.copy(maxKcal = value.coerceIn(100, ANY_KCAL)))

    fun methodChanged(value: String) = select(filters.value.copy(method = value))

    fun availabilityChanged(value: Availability) = select(filters.value.copy(availability = value))

    fun toggleAllergen(allergen: Allergen) {
        val current = filters.value
        val selected = current.excludedAllergens
        select(
            current.copy(
                excludedAllergens =
                    if (allergen in selected) selected - allergen else selected + allergen
            )
        )
    }

    fun resetFilters() = select(DishFilters())

    private fun select(value: DishFilters) {
        val previous = filters.value
        if (value == previous) return
        if (value.query != previous.query) savedState["query"] = value.query
        if (value.maxMinutes != previous.maxMinutes) savedState["minutes"] = value.maxMinutes
        if (value.maxKcal != previous.maxKcal) savedState["kcal"] = value.maxKcal
        if (value.method != previous.method) savedState["method"] = value.method
        if (value.availability != previous.availability)
            savedState["availability"] = value.availability.name
        if (value.excludedAllergens != previous.excludedAllergens) {
            savedState["dishesExcludedAllergens"] =
                ArrayList(value.excludedAllergens.map { it.name })
        }
        selection.value = value
    }

    fun favorite(id: String) = actions.run { household.toggleFavorite(id, false) }
}

private data class DishesInput(
    val catalog: Catalog,
    val household: Household,
    val profile: FoodPreferences,
    val filters: DishFilters,
) {
    suspend fun calculate(version: Long): DishesState {
        val preferences =
            profile.copy(excludedAllergens = profile.excludedAllergens + filters.excludedAllergens)
        val query = filters.query.trim()
        val context = currentCoroutineContext()
        val matches = buildList {
            for (recipe in catalog.recipes) {
                context.ensureActive()
                if (!recipe.title.contains(query, ignoreCase = true)) continue
                if (filters.hasTimeLimit && recipe.minutes > filters.maxMinutes) continue
                if (
                    filters.hasCalorieLimit &&
                        recipe.nutritionPerServing?.kcal?.let { it <= filters.maxKcal } != true
                )
                    continue
                if (
                    filters.method.isNotEmpty() && recipe.methods.none { it.name == filters.method }
                )
                    continue
                val match = matchRecipe(recipe, household.pantry, catalog, preferences)
                if (match.inMode(filters.availability)) add(match)
            }
        }
        context.ensureActive()
        return DishesState(
            matches,
            household,
            filters,
            suggestSinglePurchase(
                catalog,
                matches.filter { it.recipe.allergenDataComplete },
                Long.MAX_VALUE,
            ),
            catalog.ingredients.associate { it.id to it.name },
            version,
        )
    }
}

private fun RecipeMatch.inMode(mode: Availability): Boolean {
    // A definite exclusion stays explainable when its ingredient counts match the mode.
    val known =
        dietary.status == Suitability.HIDDEN ||
            (dietary.status == Suitability.ALLOWED && recipe.allergenDataComplete)
    return when (mode) {
        Availability.ALL -> true
        Availability.NOW -> known && ready
        Availability.BUY -> known && missing.size in 1..3 && uncertainQuantityIds.isEmpty()
    }
}
