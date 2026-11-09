package com.example.mobile_android.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.example.mobile_android.navigation.MainTab
import com.example.mobile_android.ui.components.MainScaffold
import com.example.mobile_android.ui.components.RecipeCard
import com.example.mobile_android.viewmodel.FavoritesViewModel

@Composable
fun FavoritesScreen(
    onRecipeClick: (String) -> Unit,
    onTabSelect: (MainTab) -> Unit,
    favoritesViewModel: FavoritesViewModel,
) {
    MainScaffold(currentTab = MainTab.FAVORITES, onTabSelect = onTabSelect) { padding ->
        val favorites = favoritesViewModel.favoriteRecipes
        if (favorites.isEmpty()) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                Text("Пока нет избранных блюд")
            }
        } else {
            LazyColumn(
                Modifier.fillMaxSize().padding(padding),
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(favorites, key = { it.id }) { recipe ->
                    RecipeCard(recipe = recipe, onClick = { onRecipeClick(recipe.id) })
                }
            }
        }
    }
}