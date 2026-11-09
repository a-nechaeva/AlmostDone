package com.example.mobile_android.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.example.mobile_android.data.repository.RecipeRepository
import com.example.mobile_android.viewmodel.FavoritesViewModel

@Composable
fun RecipeDetailScreen(
    recipeId: String,
    onBack: () -> Unit,
    favoritesViewModel: FavoritesViewModel,
) {
    val recipe = remember(recipeId) { RecipeRepository.recipeById(recipeId) }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(recipe?.title ?: "Рецепт") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Назад")
                    }
                },
                actions = {
                    recipe?.let { r ->
                        IconButton(onClick = { favoritesViewModel.toggle(r.id) }) {
                            Icon(
                                if (favoritesViewModel.isFavorite(r.id)) Icons.Filled.Favorite
                                else Icons.Filled.FavoriteBorder,
                                contentDescription = "В избранное",
                            )
                        }
                    }
                },
            )
        }
    ) { padding ->
        if (recipe == null) {
            Text("Рецепт не найден", Modifier.padding(padding))
            return@Scaffold
        }
        val metrics = remember(recipe) { RecipeRepository.metrics(recipe) }
        LazyColumn(
            Modifier.padding(padding).fillMaxSize(),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            item { Text("Метрики блюда", style = MaterialTheme.typography.titleMedium) }
            item { Text("Стоимость докупки: ≈${metrics.cost.toInt()} ₽ · Порций: ${recipe.portions}") }
            item { Text("КБЖУ: ${metrics.kcal.toInt()} / ${metrics.protein.toInt()} / ${metrics.fat.toInt()} / ${metrics.carb.toInt()}") }
            item { Text("Аллергены: ${metrics.allergens.joinToString(", ").ifEmpty { "нет" }}") }
            item { Text("Способы: ${recipe.methods.joinToString { it.title }}") }
            if (recipe.warnings.isNotEmpty()) {
                item { Text("Предупреждения: ${recipe.warnings.joinToString("; ")}", color = MaterialTheme.colorScheme.error) }
            }
            item { Text("Ингредиенты", style = MaterialTheme.typography.titleMedium) }
            items(recipe.ingredients) { ri ->
                val ing = RecipeRepository.ingredientById(ri.ingredientId)
                Text("${ing?.name ?: ri.ingredientId} — ${ri.grams.toInt()} г")
            }
            item { Text("Приготовление", style = MaterialTheme.typography.titleMedium) }
            items(recipe.steps.withIndex().toList()) { (index, step) ->
                Text("${index + 1}. $step")
            }
        }
    }
}