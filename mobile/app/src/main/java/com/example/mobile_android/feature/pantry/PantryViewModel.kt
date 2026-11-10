package com.example.mobile_android.feature.pantry

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.mobile_android.domain.*
import com.example.mobile_android.feature.common.*
import kotlinx.coroutines.flow.*

data class PantryState(val catalog: Catalog, val household: Household, val query: String) {
    val added: List<Pair<Ingredient, PantryItem>>
        get() =
            household.pantry
                .mapNotNull { item -> catalog.ingredient(item.ingredientId)?.let { it to item } }
                .sortedBy { it.first.name }

    val suggestions: List<Ingredient>
        get() =
            if (query.isBlank()) emptyList()
            else catalog.ingredients.filter { it.name.contains(query.trim(), ignoreCase = true) }
}

class PantryViewModel(
    private val catalog: CatalogRepository,
    private val repository: HouseholdRepository,
    private val savedState: SavedStateHandle,
) : ViewModel() {
    private val refresh = MutableStateFlow(0)
    val actions = ScreenActions(viewModelScope)
    private val query = savedState.getStateFlow("query", "")
    private val mutableDeleted = MutableStateFlow<PantryItem?>(null)
    val deleted = mutableDeleted.asStateFlow()
    val state =
        loadingStates(refresh) {
                combine(catalog.catalog, repository.household, query) { c, h, q ->
                    PantryState(c, h, q)
                }
            }
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), ScreenState.Loading)

    fun retry() {
        refresh.update { it + 1 }
    }

    fun queryChanged(value: String) {
        savedState["query"] = value.take(100)
    }

    fun add(id: String, quantity: Quantity?) =
        actions.run("Продукт добавлен") {
            repository.addPantry(id, quantity)
            savedState["query"] = ""
        }

    fun edit(id: String, quantity: Quantity?) =
        actions.run("Количество обновлено") { repository.setPantry(id, quantity) }

    fun remove(item: PantryItem) =
        actions.run("Продукт удалён") {
            repository.removePantry(item.ingredientId)
            mutableDeleted.value = item
        }

    fun undoDelete() =
        actions.run("Продукт восстановлен") {
            mutableDeleted.value?.let { repository.addPantry(it.ingredientId, it.quantity) }
            mutableDeleted.value = null
        }

    fun favorite(id: String) = actions.run { repository.toggleFavorite(id, ingredient = true) }
}
