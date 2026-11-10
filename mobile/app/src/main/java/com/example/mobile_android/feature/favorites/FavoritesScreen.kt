package com.example.mobile_android.feature.favorites

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.DialogProperties
import com.example.mobile_android.domain.Ingredient
import com.example.mobile_android.domain.Quantity
import com.example.mobile_android.feature.common.ActionState
import com.example.mobile_android.ui.components.*
import com.example.mobile_android.ui.parseQuantity
import com.example.mobile_android.ui.quantityLabel

data class FavoritesIngredientSelection(val ingredientId: String, val quantity: Quantity?)

@Composable
fun FavoritesScreen(
    state: FavoritesState,
    action: ActionState,
    favorite: (String, Boolean) -> Unit,
    recipe: (String) -> Unit,
    dismiss: () -> Unit,
) {
    FavoritesContent(state, action, favorite, recipe, dismiss)
}

@Composable
fun FavoritesContent(
    state: FavoritesState,
    action: ActionState,
    favorite: (String, Boolean) -> Unit,
    recipe: (String) -> Unit,
    dismiss: () -> Unit,
    onIngredientQuantity: ((FavoritesIngredientSelection) -> Unit)? = null,
) {
    var ingredients by rememberSaveable { mutableStateOf(false) }
    var selectedId by rememberSaveable { mutableStateOf<String?>(null) }
    val largeText = LocalDensity.current.fontScale > 1.2f
    val recipeScroll = rememberLazyListState()
    val ingredientScroll = rememberLazyListState()
    val selected = state.ingredients.find { it.id == selectedId }
    if (selected != null) {
        FavoritesQuantityDialog(
            selected,
            action.pending,
            onDismiss = { selectedId = null },
            onSave = onIngredientQuantity?.let { callback ->
                { quantity ->
                    selectedId = null
                    callback(FavoritesIngredientSelection(selected.id, quantity))
                }
            },
        )
    }
    Column(Modifier.fillMaxSize()) {
        Column(
            Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, top = 16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            PageHeading("Избранное")
            DemoNotice()
            Row(
                Modifier.fillMaxWidth().selectableGroup()
                    .background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(24.dp))
                    .padding(4.dp),
            ) {
                listOf("Блюда", "Ингредиенты").forEachIndexed { index, title ->
                    val active = ingredients == (index == 1)
                    Tab(
                        selected = active,
                        onClick = { ingredients = index == 1 },
                        modifier = Modifier.weight(if (largeText) { if (index == 0) 0.4f else 0.6f } else 1f)
                            .heightIn(min = 48.dp).clip(RoundedCornerShape(20.dp))
                            .background(if (active) MaterialTheme.colorScheme.surface else androidx.compose.ui.graphics.Color.Transparent),
                        selectedContentColor = MaterialTheme.colorScheme.onSurface,
                        unselectedContentColor = MaterialTheme.colorScheme.onSurfaceVariant,
                    ) {
                        Text(
                            title,
                            Modifier.padding(horizontal = 8.dp, vertical = 12.dp),
                            style = MaterialTheme.typography.labelLarge,
                            fontWeight = if (active) FontWeight.Bold else FontWeight.Normal,
                        )
                    }
                }
            }
            ActionMessage(action, dismiss)
            if (action.pending) {
                LinearProgressIndicator(Modifier.fillMaxWidth())
                Text("Сохраняем изменения…", style = MaterialTheme.typography.bodySmall)
            }
        }
        LazyColumn(
            modifier = Modifier.weight(1f).testTag("favorites-list"),
            state = if (ingredients) ingredientScroll else recipeScroll,
            contentPadding = PaddingValues(20.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            if (ingredients) {
                if (state.ingredients.isEmpty()) {
                    item {
                        EmptyPanel(
                            "Нет избранных ингредиентов",
                            "Отметьте сердечком продукт в разделе «Продукты».",
                        )
                    }
                }
                items(state.ingredients, key = { "ingredient-${it.id}" }) { ingredient ->
                    Surface(shape = MaterialTheme.shapes.medium) {
                        Row(
                            Modifier.fillMaxWidth().heightIn(min = 64.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Column(
                                Modifier.weight(1f)
                                    .clickable(enabled = !action.pending, role = Role.Button) {
                                        selectedId = ingredient.id
                                    }
                                    .heightIn(min = 64.dp)
                                    .padding(16.dp),
                                verticalArrangement = Arrangement.Center,
                            ) {
                                Text(ingredient.name, style = MaterialTheme.typography.titleMedium)
                                Text(
                                    state.household.pantry.find { it.ingredientId == ingredient.id }?.let {
                                        "Есть дома: ${quantityLabel(it.quantity)}"
                                    } ?: "Добавить количество",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                            IconButton(
                                onClick = { selectedId = ingredient.id },
                                enabled = !action.pending,
                                modifier = Modifier.size(48.dp),
                            ) {
                                Icon(Icons.Default.Add, "Указать количество: ${ingredient.name}")
                            }
                            IconButton(
                                onClick = { favorite(ingredient.id, true) },
                                enabled = !action.pending,
                                modifier = Modifier.size(48.dp),
                            ) {
                                Icon(
                                    Icons.Default.Favorite,
                                    "Убрать ${ingredient.name} из избранных ингредиентов",
                                    tint = MaterialTheme.colorScheme.primary,
                                )
                            }
                        }
                    }
                }
                if (state.ingredients.isNotEmpty()) item {
                    Text("Сохраняйте ингредиенты сердечком в разделе «Продукты».",
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        style = MaterialTheme.typography.bodyMedium)
                }
            } else {
                if (state.recipes.isEmpty()) {
                    item {
                        EmptyPanel(
                            "Нет избранных блюд",
                            "Отметьте сердечком понравившийся рецепт.",
                        )
                    }
                }
                items(state.recipes, key = { "recipe-${it.recipe.id}" }) { match ->
                    RecipeCard(
                        match,
                        true,
                        { recipe(match.recipe.id) },
                        { if (!action.pending) favorite(match.recipe.id, false) },
                    )
                }
                if (state.recipes.isNotEmpty()) item {
                    Text("Сохраняйте блюда сердечком в рецепте.",
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        style = MaterialTheme.typography.bodyMedium)
                }
            }
        }
    }
}

@Composable
private fun FavoritesQuantityDialog(
    ingredient: Ingredient,
    pending: Boolean,
    onDismiss: () -> Unit,
    onSave: ((Quantity?) -> Unit)?,
) {
    var value by rememberSaveable(ingredient.id) { mutableStateOf("") }
    var submitted by remember { mutableStateOf(false) }
    val quantity = parseQuantity(value, ingredient.unit)
    val valid = value.isBlank() || quantity != null
    val keyboard = LocalSoftwareKeyboardController.current
    BackHandler(onBack = onDismiss)
    AlertDialog(
        modifier = Modifier.widthIn(max = 560.dp).fillMaxWidth().padding(horizontal = 24.dp),
        properties = DialogProperties(usePlatformDefaultWidth = false),
        containerColor = MaterialTheme.colorScheme.surface,
        onDismissRequest = onDismiss,
        title = { Text(ingredient.name) },
        text = {
            Column(
                Modifier.verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                OutlinedTextField(
                    value = value,
                    onValueChange = { value = it.take(20) },
                    label = { Text("Количество, ${ingredient.unit.label}") },
                    singleLine = true,
                    isError = !valid,
                    enabled = !pending && !submitted,
                    keyboardOptions = KeyboardOptions(
                        keyboardType = KeyboardType.Decimal,
                        imeAction = ImeAction.Done,
                    ),
                    keyboardActions = KeyboardActions(onDone = { keyboard?.hide() }),
                )
                Text(
                    if (valid) "Оставьте поле пустым, если количество неизвестно."
                    else "Введите число от 0 до 1 000 000.",
                    style = MaterialTheme.typography.bodySmall,
                )
                if (onSave == null) {
                    Text("Добавление в продукты здесь пока недоступно.")
                }
            }
        },
        confirmButton = {
            if (onSave != null) {
                TextButton(
                    onClick = {
                        if (!submitted && !pending && valid) {
                            submitted = true
                            keyboard?.hide()
                            onSave(quantity)
                        }
                    },
                    enabled = valid && !pending && !submitted,
                ) { Text("Добавить в продукты") }
            } else {
                TextButton(onClick = onDismiss) { Text("Закрыть") }
            }
        },
        dismissButton = {
            if (onSave != null) TextButton(onClick = onDismiss) { Text("Отмена") }
        },
    )
}
