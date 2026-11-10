package com.example.mobile_android.feature.recipe

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.example.mobile_android.domain.*
import com.example.mobile_android.feature.common.ActionState
import com.example.mobile_android.ui.*
import com.example.mobile_android.ui.components.*

@Composable
fun RecipeScreen(
    state: RecipeState,
    action: ActionState,
    servings: (Int) -> Unit,
    favorite: () -> Unit,
    addToShopping: () -> Unit,
    shopping: () -> Unit,
    dismiss: () -> Unit,
) {
    val match = state.match
    if (match == null) {
        EmptyPanel("Рецепт не найден", "В демонстрационном каталоге такого рецепта нет.")
        return
    }
    val recipe = match.recipe
    LazyColumn(
        contentPadding = PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        item { PageHeading(recipe.title) }
        item {
            RecipePhoto(
                recipe.photo,
                Modifier.fillMaxWidth().height(206.dp),
                "Пример подачи: ${recipe.title}",
                corner = 24.dp,
            )
        }
        item { DemoNotice() }
        item {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    "Порций: ${match.servings}",
                    Modifier.weight(1f),
                    style = MaterialTheme.typography.titleMedium,
                )
                IconButton(
                    { servings(match.servings - 1) },
                    enabled = match.servings > 1 && !action.pending,
                ) {
                    Icon(Icons.Default.Remove, "Уменьшить число порций")
                }
                IconButton(
                    { servings(match.servings + 1) },
                    enabled = match.servings < 12 && !action.pending,
                ) {
                    Icon(Icons.Default.Add, "Увеличить число порций")
                }
                IconButton(favorite, enabled = !action.pending) {
                    Icon(
                        if (state.favorite) Icons.Default.Favorite
                        else Icons.Default.FavoriteBorder,
                        if (state.favorite) "Убрать рецепт из избранного"
                        else "Сохранить рецепт в избранное",
                        tint = MaterialTheme.colorScheme.primary,
                    )
                }
            }
        }
        item { Text("${recipe.minutes} мин · ${recipe.methods.joinToString { it.label }}") }
        item {
            Text(
                "КБЖУ на порцию",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
            )
        }
        item {
            Text(
                recipe.nutritionPerServing?.let {
                    "${it.kcal} ккал · Б ${it.protein} г · Ж ${it.fat} г · У ${it.carbs} г"
                } ?: "Нет данных"
            )
        }
        item {
            Text(
                if (!recipe.allergenDataComplete) "Сведения об аллергенах неполные"
                else if (recipe.allergens.isEmpty()) "По демо-данным аллергены не указаны"
                else "Аллергены: ${recipe.allergens.joinToString { it.label }}"
            )
        }
        if (match.dietary.reasons.isNotEmpty())
            item {
                Text(
                    match.dietary.reasons.joinToString("\n"),
                    color = MaterialTheme.colorScheme.error,
                )
            }
        if (match.uncertainQuantityIds.isNotEmpty())
            item {
                Text(
                    "Проверьте количество и единицы продуктов дома. Докупка пока неизвестна.",
                    color = MaterialTheme.colorScheme.primary,
                )
            }
        item {
            Text(
                "Докупка: ${if (match.purchaseKopecks == null) "нет оценки" else "≈${money(match.purchaseKopecks)}"}. Цена целых упаковок по демо-данным."
            )
        }
        item {
            Text(
                "Ингредиенты на ${match.servings} порц.",
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
            )
        }
        items(state.requirements, key = { it.ingredientId }) { need ->
            val shortage = match.missing.find { it.ingredientId == need.ingredientId }
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    "${state.catalog.ingredient(need.ingredientId)?.name ?: "Неизвестный продукт"} · ${quantityLabel(need.quantity)}"
                )
                if (shortage != null)
                    Text(
                        "Докупить: ${quantityLabel(shortage.quantity)}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.primary,
                    )
                if (need.ingredientId in match.uncertainQuantityIds)
                    Text(
                        "Наличие требует проверки",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.primary,
                    )
            }
        }
        item { ActionMessage(action, dismiss) }
        item {
            PrimaryButton(
                addToShopping,
                Modifier.fillMaxWidth().heightIn(min = 48.dp),
                enabled =
                    !action.pending &&
                        match.dietary.status == Suitability.ALLOWED &&
                        match.uncertainQuantityIds.isEmpty(),
            ) {
                Text(if (state.planned) "Обновить список покупок" else "Добавить рецепт в покупки")
            }
        }
        item {
            Text(
                "Список покупок учитывает все выбранные рецепты и продукты дома.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        if (state.planned)
            item {
                OutlinedButton(shopping, Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
                    Text("Открыть покупки")
                }
            }
        item {
            Text(
                "Приготовление",
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
            )
        }
        items(recipe.steps.withIndex().toList(), key = { it.index }) { (index, step) ->
            Text("${index + 1}. $step")
        }
    }
}
