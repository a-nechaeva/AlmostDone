package com.example.mobile_android.feature.dishes

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ShoppingBag
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.example.mobile_android.domain.PurchaseSet
import com.example.mobile_android.domain.RecipeMatch
import com.example.mobile_android.feature.common.ActionState
import com.example.mobile_android.ui.*
import com.example.mobile_android.ui.components.*

@Composable
fun DishesViewSelector(view: DishesView, change: (DishesView) -> Unit) {
    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
        DishesView.entries.forEachIndexed { index, option ->
            SegmentedButton(
                selected = view == option,
                onClick = { change(option) },
                shape = SegmentedButtonDefaults.itemShape(index, DishesView.entries.size),
                modifier = Modifier.heightIn(min = 48.dp),
            ) {
                Text(option.label)
            }
        }
    }
}

fun LazyListScope.purchaseGraph(
    state: DishesState,
    action: ActionState,
    recipe: (String) -> Unit,
    addPurchase: () -> Unit,
    reset: () -> Unit,
    dismiss: () -> Unit,
    addSet: (String) -> Unit = {},
) {
    val suggestion = state.suggestion
    // Наборы покупок (1–3 продукта); одиночная покупка уже показана отдельным блоком.
    val sets = state.purchaseSets.filter { suggestion == null || it.key != suggestion.ingredient.id }
    if (suggestion == null && sets.isNotEmpty()) {
        item { Text("Что докупить, чтобы открыть блюда", color = MaterialTheme.colorScheme.onSurfaceVariant) }
        item { ActionMessage(action, dismiss) }
        purchaseSetItems(sets, state.visible, action, recipe, addSet)
        return
    }
    if (suggestion == null) {
        if (state.visible.isNotEmpty())
            item {
                EmptyPanel(
                    "Нет связей с одной покупкой",
                    "Среди выбранных блюд нет вариантов с одной известной покупкой. " +
                        "Откройте список, измените фильтры или уточните продукты и ограничения питания.",
                    "Сбросить фильтры",
                    reset,
                )
            }
        return
    }
    item { Text("Лучшая одиночная покупка", color = MaterialTheme.colorScheme.onSurfaceVariant) }
    item {
        Surface(
            shape = MaterialTheme.shapes.large,
            color = MaterialTheme.colorScheme.primaryContainer,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Icon(Icons.Outlined.ShoppingBag, null, tint = MaterialTheme.colorScheme.primary)
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(
                            suggestion.ingredient.name,
                            style = MaterialTheme.typography.titleLarge,
                            fontWeight = FontWeight.Bold,
                        )
                        Text(
                            "≈${money(suggestion.priceKopecks)} · упаковка ${quantityLabel(suggestion.quantity)}"
                        )
                    }
                }
                Text(
                    "Дополнительных блюд: ${suggestion.recipeIds.size}",
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        }
    }
    val recipes = state.visible.filter { it.recipe.id in suggestion.recipeIds }
    items(recipes, key = { "graph-${it.recipe.id}" }) { match ->
        val line = MaterialTheme.colorScheme.outline
        Box(
            Modifier.fillMaxWidth()
                .drawBehind {
                    val x = 14.dp.toPx()
                    val y = size.height / 2
                    drawLine(line, Offset(x, -12.dp.toPx()), Offset(x, size.height), 1.dp.toPx())
                    drawLine(line, Offset(x, y), Offset(32.dp.toPx(), y), 1.dp.toPx())
                }
                .padding(start = 32.dp)
        ) {
            Card(
                onClick = { recipe(match.recipe.id) },
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
            ) {
                Row(
                    Modifier.padding(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    RecipePhoto(match.recipe.photo, Modifier.size(80.dp))
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(
                            match.recipe.title,
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold,
                        )
                        Text(
                            "${match.recipe.minutes} мин · ${match.recipe.nutritionPerServing?.kcal?.let { "$it ккал / порц." } ?: "КБЖУ неизвестно"}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Text(
                            "Докупить: ${suggestion.ingredient.name}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.primary,
                        )
                    }
                }
            }
        }
    }
    item {
        Surface(
            shape = MaterialTheme.shapes.medium,
            color = MaterialTheme.colorScheme.tertiaryContainer,
        ) {
            Column(
                Modifier.fillMaxWidth().padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Text("Одна покупка → больше блюд", fontWeight = FontWeight.Bold)
                Text(
                    "Каждое блюдо — отдельный вариант. Продукты дома учитываются для каждого варианта отдельно."
                )
            }
        }
    }
    item {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            ActionMessage(action, dismiss)
            PrimaryButton(
                addPurchase,
                Modifier.fillMaxWidth().heightIn(min = 48.dp),
                enabled = !action.pending,
            ) {
                Text("Добавить в покупки")
            }
        }
    }
    if (sets.isNotEmpty()) {
        item { Text("Другие наборы покупок", color = MaterialTheme.colorScheme.onSurfaceVariant) }
        purchaseSetItems(sets, state.visible, action, recipe, addSet)
    }
}

private fun LazyListScope.purchaseSetItems(
    sets: List<PurchaseSet>,
    visible: List<RecipeMatch>,
    action: ActionState,
    recipe: (String) -> Unit,
    addSet: (String) -> Unit,
) {
    val byId = visible.associateBy { it.recipe.id }
    items(sets, key = { "set-${it.key}" }) { set ->
        Surface(
            shape = MaterialTheme.shapes.large,
            color = MaterialTheme.colorScheme.surface,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Icon(Icons.Outlined.ShoppingBag, null, tint = MaterialTheme.colorScheme.primary)
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(
                            set.items.joinToString(" + ") { it.ingredient.name },
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold,
                        )
                        Text(
                            "≈${money(set.priceKopecks)} · откроет блюд: ${set.recipeIds.size}",
                            color = MaterialTheme.colorScheme.primary,
                        )
                    }
                }
                set.items.forEach {
                    Text(
                        "${it.ingredient.name}: ${quantityLabel(it.quantity)} · ≈${money(it.priceKopecks)}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                val shown = set.recipeIds.mapNotNull(byId::get).take(MAX_SET_RECIPES)
                shown.forEach { match ->
                    TextButton(onClick = { recipe(match.recipe.id) }, contentPadding = PaddingValues(0.dp)) {
                        Text(
                            "→ ${match.recipe.title} · ${match.recipe.minutes} мин",
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                }
                if (set.recipeIds.size > shown.size)
                    Text(
                        "и ещё ${set.recipeIds.size - shown.size}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                OutlinedButton(
                    onClick = { addSet(set.key) },
                    modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
                    enabled = !action.pending,
                ) {
                    Text("Добавить в покупки")
                }
            }
        }
    }
}

private const val MAX_SET_RECIPES = 4
