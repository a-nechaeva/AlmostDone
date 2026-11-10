package com.example.mobile_android.feature.favorites

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.example.mobile_android.feature.common.ActionState
import com.example.mobile_android.ui.components.*

@Composable
fun FavoritesScreen(
    state: FavoritesState,
    action: ActionState,
    favorite: (String, Boolean) -> Unit,
    recipe: (String) -> Unit,
    dismiss: () -> Unit,
) {
    var ingredients by rememberSaveable { mutableStateOf(false) }
    LazyColumn(
        contentPadding = PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item { PageHeading("Избранное") }
        item { DemoNotice() }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                ChoiceChip(!ingredients, { ingredients = false }, { Text("Блюда") })
                ChoiceChip(ingredients, { ingredients = true }, { Text("Ингредиенты") })
            }
        }
        item { ActionMessage(action, dismiss) }
        if (ingredients) {
            if (state.ingredients.isEmpty())
                item {
                    EmptyPanel(
                        "Нет избранных ингредиентов",
                        "Отметьте сердечком продукт в разделе «Продукты».",
                    )
                }
            items(state.ingredients, key = { it.id }) { ingredient ->
                Row(
                    Modifier.fillMaxWidth().heightIn(min = 56.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(ingredient.name, Modifier.weight(1f))
                    IconButton({ favorite(ingredient.id, true) }, enabled = !action.pending) {
                        Icon(
                            Icons.Default.Favorite,
                            "Убрать ${ingredient.name} из избранных ингредиентов",
                            tint = MaterialTheme.colorScheme.primary,
                        )
                    }
                }
            }
        } else {
            if (state.recipes.isEmpty())
                item {
                    EmptyPanel("Нет избранных блюд", "Отметьте сердечком понравившийся рецепт.")
                }
            items(state.recipes, key = { it.recipe.id }) { match ->
                RecipeCard(
                    match,
                    true,
                    { recipe(match.recipe.id) },
                    { favorite(match.recipe.id, false) },
                )
            }
        }
    }
}
