package com.example.mobile_android.ui.screens

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.mobile_android.data.model.CookingMethod
import com.example.mobile_android.navigation.MainTab
import com.example.mobile_android.ui.components.MainScaffold
import com.example.mobile_android.ui.components.RecipeCard
import com.example.mobile_android.viewmodel.RecipesUiState
import com.example.mobile_android.viewmodel.RecipesViewModel

@Composable
fun HomeScreen(
    onRecipeClick: (String) -> Unit,
    onTabSelect: (MainTab) -> Unit,
    viewModel: RecipesViewModel = viewModel(),
) {
    val state = viewModel.uiState
    MainScaffold(currentTab = MainTab.HOME, onTabSelect = onTabSelect) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("Рецепты", style = MaterialTheme.typography.headlineSmall, modifier = Modifier.weight(1f))
                TextButton(onClick = viewModel::toggleFiltersPanel) {
                    Text(if (state.showFilters) "Скрыть фильтры" else "Фильтры")
                }
            }
            if (state.showFilters) FiltersPanel(state = state, viewModel = viewModel)
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(state.visibleRecipes, key = { it.id }) { recipe ->
                    RecipeCard(recipe = recipe, onClick = { onRecipeClick(recipe.id) })
                }
            }
        }
    }
}

@Composable
private fun FiltersPanel(state: RecipesUiState, viewModel: RecipesViewModel) {
    Column(Modifier.padding(horizontal = 16.dp)) {
        Text("Время: не больше ${state.maxTime} мин")
        Slider(
            value = state.maxTime.toFloat(),
            onValueChange = { viewModel.setMaxTime(it.toInt()) },
            valueRange = 5f..180f,
            modifier = Modifier.fillMaxWidth(),
        )
        Text("Калорийность: не больше ${state.maxKcal} ккал")
        Slider(
            value = state.maxKcal.toFloat(),
            onValueChange = { viewModel.setMaxKcal(it.toInt()) },
            valueRange = 100f..3000f,
            modifier = Modifier.fillMaxWidth(),
        )
        Row(
            Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            CookingMethod.entries.forEach { method ->
                FilterChip(
                    selected = state.methods.contains(method),
                    onClick = { viewModel.toggleMethod(method) },
                    label = { Text(method.title) },
                )
            }
        }
        Spacer(Modifier.height(8.dp))
        // TODO: фильтры по аллергенам и профилю пользователя (требование 5)
    }
}