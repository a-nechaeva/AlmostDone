package com.example.mobile_android.viewmodel

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import com.example.mobile_android.data.model.Recipe
import com.example.mobile_android.data.repository.RecipeRepository

class FavoritesViewModel : ViewModel() {
    var favoriteIds by mutableStateOf(setOf<String>())
        private set

    val favoriteRecipes: List<Recipe>
        get() = RecipeRepository.recipes.filter { it.id in favoriteIds }

    fun isFavorite(id: String) = id in favoriteIds

    fun toggle(id: String) {
        favoriteIds = if (id in favoriteIds) favoriteIds - id else favoriteIds + id
    }
}