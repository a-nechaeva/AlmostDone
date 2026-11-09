package com.example.mobile_android.viewmodel

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import com.example.mobile_android.data.model.Ingredient
import com.example.mobile_android.data.repository.RecipeRepository

class PantryViewModel : ViewModel() {
    var query by mutableStateOf("")
        private set
    var addedIds by mutableStateOf(listOf<String>())
        private set

    val suggestions: List<Ingredient>
        get() = if (query.length < 2) emptyList()
        else RecipeRepository.ingredients.filter {
            it.name.contains(query, ignoreCase = true) && it.id !in addedIds
        }

    val added: List<Ingredient>
        get() = addedIds.mapNotNull { RecipeRepository.ingredientById(it) }

    fun onQueryChange(value: String) { query = value }
    fun add(id: String) { addedIds = addedIds + id; query = "" }
    fun remove(id: String) { addedIds = addedIds - id }
}