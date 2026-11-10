package com.example.mobile_android.feature.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.mobile_android.domain.*
import com.example.mobile_android.feature.common.*
import kotlinx.coroutines.flow.*

class ProfileViewModel(private val preferences: PreferencesRepository) : ViewModel() {
    private val refresh = MutableStateFlow(0)
    val actions = ScreenActions(viewModelScope)
    val state =
        loadingStates(refresh) { preferences.preferences }
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), ScreenState.Loading)

    fun retry() {
        refresh.update { it + 1 }
    }

    fun save(draft: FoodPreferences) {
        val snapshot =
            draft.copy(
                excludedAllergens = draft.excludedAllergens.toSet(),
                dietTable = draft.dietTable.trim().take(100),
            )
        actions.run("Предпочтения сохранены") { preferences.update { snapshot } }
    }

    fun foodType(value: FoodType) = actions.run { preferences.update { it.copy(foodType = value) } }

    fun allergen(value: Allergen) =
        actions.run {
            preferences.update { p ->
                p.copy(
                    excludedAllergens =
                        if (value in p.excludedAllergens) p.excludedAllergens - value
                        else p.excludedAllergens + value
                )
            }
        }

    fun gluten(value: Boolean) = actions.run { preferences.update { it.copy(glutenFree = value) } }

    fun lactose(value: Boolean) =
        actions.run { preferences.update { it.copy(lactoseFree = value) } }

    fun diabetes(value: Boolean) = actions.run { preferences.update { it.copy(diabetes = value) } }

    fun table(value: String) =
        actions.run("Название стола сохранено") {
            preferences.update { it.copy(dietTable = value.trim().take(100)) }
        }
}
