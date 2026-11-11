package com.example.mobile_android.feature.recipe

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.mobile_android.domain.*
import com.example.mobile_android.feature.common.ActionState
import com.example.mobile_android.ui.*
import com.example.mobile_android.ui.components.*
import kotlinx.coroutines.launch

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun RecipeScreen(
    state: RecipeState,
    action: ActionState,
    servings: (Int) -> Unit,
    favorite: () -> Unit,
    addToShopping: () -> Unit,
    shopping: () -> Unit,
    dismiss: () -> Unit,
    showFavoriteInCard: Boolean = true,
) {
    val match = state.match
    if (match == null) {
        EmptyPanel("Рецепт не найден", "В демонстрационном каталоге такого рецепта нет.")
        return
    }
    val recipe = match.recipe
    // A new recipe starts at its photo; changes in pantry or portions keep the scroll position.
    key(recipe.id) {
        val list = rememberLazyListState()
        val scope = rememberCoroutineScope()
        Column(Modifier.fillMaxSize()) {
            LazyColumn(
                state = list,
                modifier = Modifier.weight(1f).testTag("recipe-ui-content"),
                contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 12.dp, bottom = 24.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                item(key = "photo") {
                    if (recipe.photo in setOf("pasta", "omelette") || RemoteImages.isRemote(recipe.photo)) {
                        RecipePhoto(
                            recipe.photo,
                            Modifier.fillMaxWidth().height(206.dp),
                            "Пример подачи: ${recipe.title}",
                            corner = 24.dp,
                        )
                    } else {
                        Surface(
                            Modifier.fillMaxWidth().height(206.dp),
                            shape = RoundedCornerShape(24.dp),
                            color = MaterialTheme.colorScheme.surfaceVariant,
                        ) {
                            Column(
                                verticalArrangement = Arrangement.Center,
                                horizontalAlignment = Alignment.CenterHorizontally,
                            ) {
                                Icon(Icons.Default.ImageNotSupported, null)
                                Text("Фото отсутствует")
                            }
                        }
                    }
                }
                item(key = "title") {
                    Row(verticalAlignment = Alignment.Top) {
                        Text(
                            recipe.title,
                            Modifier.weight(1f).semantics { heading() },
                            style = MaterialTheme.typography.headlineMedium,
                            fontSize = 26.sp,
                            lineHeight = 32.sp,
                            fontWeight = FontWeight.Bold,
                        )
                        if (showFavoriteInCard) {
                            RecipeFavoriteButton(state, action, favorite)
                        }
                    }
                }
                item(key = "availability") {
                    val uncertain = match.uncertainQuantityIds.isNotEmpty()
                    Surface(
                        shape = RoundedCornerShape(10.dp),
                        color = if (match.ready) MaterialTheme.colorScheme.tertiaryContainer
                            else MaterialTheme.colorScheme.primaryContainer,
                        contentColor = if (match.ready) MaterialTheme.colorScheme.onTertiaryContainer
                            else MaterialTheme.colorScheme.onPrimaryContainer,
                    ) {
                        Row(Modifier.padding(horizontal = 10.dp, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Icon(
                                if (uncertain) Icons.Default.HelpOutline
                                else if (match.ready) Icons.Default.Check else Icons.Default.ShoppingBag,
                                null, Modifier.size(18.dp),
                            )
                            Text(
                                if (uncertain) "Количество продуктов требует проверки"
                                else if (match.ready) "Все продукты есть дома"
                                else "Нужно докупить: ${match.missing.size}",
                                style = MaterialTheme.typography.labelMedium,
                            )
                        }
                    }
                }
                item(key = "metrics") {
                    FlowRow(
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        RecipeMetric("${recipe.minutes} мин", "всего")
                        RecipeMetric(recipe.nutritionPerServing?.let { "${it.kcal} ккал" } ?: "Нет оценки", "на порцию")
                        RecipeMetric("${match.servings}", "порции")
                    }
                }
                item(key = "nutrition") {
                    Text(
                        recipe.nutritionPerServing?.let { "На порцию: Б ${it.protein} · Ж ${it.fat} · У ${it.carbs} г" }
                            ?: "КБЖУ на порцию: нет оценки",
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        style = MaterialTheme.typography.bodyMedium,
                    )
                    Text(recipe.methods.joinToString { it.label }, style = MaterialTheme.typography.bodySmall)
                }
                item(key = "allergens") {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(
                            "Аллергены",
                            Modifier.semantics { heading() },
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.Bold,
                        )
                        if (recipe.allergens.isNotEmpty()) {
                            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                recipe.allergens.forEach {
                                    Surface(shape = RoundedCornerShape(18.dp)) {
                                        Text(it.label, Modifier.padding(horizontal = 16.dp, vertical = 10.dp), style = MaterialTheme.typography.bodySmall)
                                    }
                                }
                            }
                        }
                        if (!recipe.allergenDataComplete) Text("Сведения об аллергенах неполные. Нет полной оценки.")
                        else if (recipe.allergens.isEmpty()) Text("По демо-данным аллергены не указаны")
                        if (match.dietary.status != Suitability.ALLOWED || match.dietary.reasons.isNotEmpty()) {
                            Text(
                                match.dietary.reasons.joinToString("\n").ifBlank { "Соответствие ограничениям не подтверждено" },
                                color = MaterialTheme.colorScheme.error,
                            )
                        }
                        DemoNotice()
                    }
                }
                item(key = "ingredients-heading") {
                    Column {
                        FlowRow(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            RecipeHeading("Ингредиенты")
                            TextButton(onClick = {
                                // Six header items precede this heading, then one item per ingredient.
                                scope.launch { list.animateScrollToItem(7 + state.requirements.size) }
                            }) { Text("К шагам →") }
                        }
                        Text("На ${match.servings} порц.", color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall)
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("Изменить порции", Modifier.weight(1f), style = MaterialTheme.typography.bodySmall)
                            IconButton({ servings(match.servings - 1) }, enabled = match.servings > 1 && !action.pending) {
                                Icon(Icons.Default.Remove, "Уменьшить число порций")
                            }
                            Text("${match.servings}")
                            IconButton({ servings(match.servings + 1) }, enabled = match.servings < 12 && !action.pending) {
                                Icon(Icons.Default.Add, "Увеличить число порций")
                            }
                        }
                    }
                }
                items(state.requirements, key = { "ingredient-${it.ingredientId}" }) { need ->
                    val shortage = match.missing.find { it.ingredientId == need.ingredientId }
                    val unknown = need.ingredientId in match.uncertainQuantityIds
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
                        Icon(
                            if (unknown) Icons.Default.HelpOutline else if (shortage != null) Icons.Default.Add else Icons.Default.Check,
                            null,
                            tint = if (unknown || shortage != null) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.tertiary,
                        )
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(state.catalog.ingredient(need.ingredientId)?.name ?: "Неизвестный продукт", fontWeight = FontWeight.Medium)
                            Text(
                                if (unknown) "Количество или единицы неизвестны"
                                else if (shortage != null) "Докупить: ${quantityLabel(shortage.quantity)}"
                                else "Есть дома",
                                color = if (unknown || shortage != null) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                                style = MaterialTheme.typography.bodySmall,
                            )
                        }
                        Text(
                            quantityLabel(need.quantity),
                            Modifier.widthIn(max = 100.dp),
                            style = MaterialTheme.typography.bodyMedium,
                        )
                    }
                }
                item(key = "steps-heading") { RecipeHeading("Как приготовить") }
                if (recipe.steps.isEmpty()) item { Text("Шаги приготовления пока отсутствуют") }
                items(recipe.steps.withIndex().toList(), key = { "step-${it.index}" }) { (index, step) ->
                    Surface(shape = RoundedCornerShape(22.dp)) {
                        Row(Modifier.fillMaxWidth().padding(16.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                            Surface(shape = RoundedCornerShape(16.dp), color = MaterialTheme.colorScheme.primaryContainer, contentColor = MaterialTheme.colorScheme.onPrimaryContainer) {
                                Text("${index + 1}", Modifier.padding(horizontal = 12.dp, vertical = 6.dp), fontWeight = FontWeight.Bold)
                            }
                            Text(step, Modifier.weight(1f), color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
            Surface(color = MaterialTheme.colorScheme.background) {
                Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    ActionMessage(action, dismiss)
                    if (action.pending) Text("Сохраняем изменения…", style = MaterialTheme.typography.bodySmall)
                    if (!state.canAddToShopping) Text(
                        "Перед добавлением проверьте количество продуктов и ограничения питания.",
                        style = MaterialTheme.typography.bodySmall,
                    )
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Column {
                            Text("Докупка упаковок", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Text(match.purchaseKopecks?.let { "≈${money(it)}" } ?: "Нет оценки", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                        }
                        PrimaryButton(addToShopping, enabled = !action.pending && state.canAddToShopping) {
                            Text(if (state.planned) "Обновить список покупок" else "Добавить в покупки")
                        }
                    }
                    if (state.planned) TextButton(shopping, Modifier.fillMaxWidth()) { Text("Открыть покупки") }
                }
            }
        }
    }
}

@Composable
private fun RecipeMetric(value: String, label: String) {
    Surface(shape = RoundedCornerShape(18.dp), color = MaterialTheme.colorScheme.surfaceVariant) {
        Column(Modifier.widthIn(min = 100.dp).padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                value,
                style = MaterialTheme.typography.titleMedium,
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Text(label, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun RecipeHeading(text: String) {
    Text(text, Modifier.semantics { heading() }, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
}
