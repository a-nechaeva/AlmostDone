package com.example.mobile_android.feature.shopping

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.example.mobile_android.feature.common.ActionState
import com.example.mobile_android.ui.*
import com.example.mobile_android.ui.components.*

@Composable
fun ShoppingScreen(
    state: ShoppingState,
    action: ActionState,
    budget: (Long) -> Unit,
    toggle: (String) -> Unit,
    removeRecipe: (String) -> Unit,
    removeManual: (String) -> Unit,
    checkout: () -> Unit,
    addSuggestion: () -> Unit,
    dishes: () -> Unit,
    dismiss: () -> Unit,
) {
    var budgetOpen by rememberSaveable { mutableStateOf(false) }
    var budgetText by
        rememberSaveable(state.budgetKopecks) {
            mutableStateOf(money(state.budgetKopecks).removeSuffix(" ₽"))
        }
    if (budgetOpen)
        AlertDialog(
            onDismissRequest = { budgetOpen = false },
            title = { Text("Бюджет покупок") },
            text = {
                OutlinedTextField(
                    budgetText,
                    { budgetText = it.take(16) },
                    label = { Text("Бюджет, ₽") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    isError = parseMoney(budgetText) == null,
                )
            },
            confirmButton = {
                TextButton(
                    {
                        parseMoney(budgetText)?.let(budget)
                        budgetOpen = false
                    },
                    enabled = parseMoney(budgetText) != null,
                ) {
                    Text("Сохранить")
                }
            },
            dismissButton = { TextButton({ budgetOpen = false }) { Text("Отмена") } },
        )
    LazyColumn(
        contentPadding = PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item { PageHeading("Покупки", "Из рецептов и выбранных предложений") }
        item { DemoNotice() }
        item {
            OutlinedButton({ budgetOpen = true }, Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
                Text("Бюджет: ${money(state.budgetKopecks)} · изменить")
            }
        }
        item { ActionMessage(action, dismiss) }
        if (state.planWarnings.isNotEmpty())
            item {
                Text(
                    "Проверьте выбранные рецепты:\n" + state.planWarnings.joinToString("\n"),
                    color = MaterialTheme.colorScheme.error,
                )
            }
        if (state.quote.lines.isEmpty())
            item {
                EmptyPanel(
                    "Список пуст",
                    if (state.household.plan.isEmpty()) "Добавьте рецепт или предложенную покупку."
                    else "Для выбранных рецептов продукты уже есть дома.",
                    "Выбрать блюда",
                    dishes,
                )
            }
        items(state.quote.lines, key = { it.ingredientId }) { line ->
            Card(
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
            ) {
                Row(
                    Modifier.fillMaxWidth()
                        .heightIn(min = 64.dp)
                        .toggleable(
                            line.checked,
                            enabled = !action.pending && line.buyQuantity != null,
                            role = Role.Checkbox,
                            onValueChange = { toggle(line.ingredientId) },
                        )
                        .semantics(mergeDescendants = true) {}
                        .padding(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Checkbox(
                        line.checked,
                        onCheckedChange = null,
                        enabled = !action.pending && line.buyQuantity != null,
                    )
                    Column(Modifier.weight(1f).padding(start = 8.dp)) {
                        Text(
                            state.catalog.ingredient(line.ingredientId)?.name
                                ?: "Неизвестный продукт"
                        )
                        Text(
                            "Нужно: ${quantityLabel(line.required)}",
                            style = MaterialTheme.typography.bodySmall,
                        )
                        Text(
                            if (line.buyQuantity == null) "Нет сведений об упаковке"
                            else "Купить: ${quantityLabel(line.buyQuantity)}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    Text(money(line.priceKopecks), Modifier.padding(start = 8.dp))
                }
            }
        }
        if (state.quote.lines.isNotEmpty()) {
            item {
                val total = state.quote.totalKopecks
                Text(
                    "Итого по демо-ценам: ${money(total)}",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                )
                Text(
                    if (total == null) "Остаток бюджета неизвестен"
                    else if (total <= state.budgetKopecks)
                        "Остаток: ${money(state.budgetKopecks - total)}"
                    else "Выше бюджета на ${money(total - state.budgetKopecks)}"
                )
            }
            item {
                Text(
                    "Отметка покупки не меняет продукты дома. Добавьте купленное отдельной кнопкой.",
                    style = MaterialTheme.typography.bodySmall,
                )
            }
            item {
                PrimaryButton(
                    checkout,
                    Modifier.fillMaxWidth().heightIn(min = 48.dp),
                    enabled = !action.pending && state.quote.lines.any { it.checked },
                ) {
                    Text("Добавить купленное домой")
                }
            }
        }
        if (state.household.plan.isNotEmpty())
            item { Text("Выбранные рецепты", style = MaterialTheme.typography.titleMedium) }
        items(state.household.plan, key = { "plan-${it.recipeId}" }) { planned ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    "${state.catalog.recipe(planned.recipeId)?.title ?: "Рецепт недоступен"} · ${planned.servings} порц.",
                    Modifier.weight(1f),
                )
                IconButton({ removeRecipe(planned.recipeId) }, enabled = !action.pending) {
                    Icon(
                        Icons.Default.Close,
                        "Убрать рецепт из покупок: ${state.catalog.recipe(planned.recipeId)?.title.orEmpty()}",
                    )
                }
            }
        }
        items(state.household.manualPurchases, key = { "manual-${it.ingredientId}" }) { manual ->
            TextButton({ removeManual(manual.ingredientId) }, enabled = !action.pending) {
                Text(
                    "Убрать предложение: ${state.catalog.ingredient(manual.ingredientId)?.name.orEmpty()}"
                )
            }
        }
        item { HorizontalDivider() }
        item {
            Text(
                "Лучшая одиночная покупка",
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
            )
        }
        val suggestion = state.suggestion
        if (suggestion == null)
            item {
                Text(
                    "В пределах бюджета подходящего предложения нет. Проверьте бюджет, продукты и ограничения профиля."
                )
            }
        else {
            item {
                Text(
                    "${suggestion.ingredient.name} · ${quantityLabel(suggestion.quantity)} · ≈${money(suggestion.priceKopecks)}"
                )
            }
            item {
                Text(
                    "Откроет вариантов блюд: ${suggestion.recipeIds.size}. Это альтернативы, а не общий план приготовления."
                )
            }
            item {
                PrimaryButton(
                    addSuggestion,
                    Modifier.fillMaxWidth().heightIn(min = 48.dp),
                    enabled = !action.pending,
                ) {
                    Text("Добавить предложенную покупку")
                }
            }
        }
    }
}
