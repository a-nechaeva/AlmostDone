package com.example.mobile_android.feature.pantry

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.example.mobile_android.domain.*
import com.example.mobile_android.feature.common.ActionState
import com.example.mobile_android.ui.components.*
import com.example.mobile_android.ui.quantityLabel

@Composable
fun PantryScreen(
    state: PantryState,
    action: ActionState,
    deleted: PantryItem?,
    queryChanged: (String) -> Unit,
    add: (String, Quantity?) -> Unit,
    edit: (String, Quantity?) -> Unit,
    remove: (PantryItem) -> Unit,
    undo: () -> Unit,
    favorite: (String) -> Unit,
    dismiss: () -> Unit,
    dishes: () -> Unit,
    receipt: () -> Unit,
) {
    var selectedId by rememberSaveable { mutableStateOf<String?>(null) }
    var editing by rememberSaveable { mutableStateOf(false) }
    val selected = selectedId?.let(state.catalog::ingredient)
    if (selected != null)
        QuantityDialog(
            selected,
            if (editing) state.household.pantry.find { it.ingredientId == selected.id }?.quantity
            else null,
            editing,
            onDismiss = { selectedId = null },
            onSave = { quantity ->
                if (editing) edit(selected.id, quantity) else add(selected.id, quantity)
                selectedId = null
            },
        )
    LazyColumn(
        contentPadding = PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item { PageHeading("Мои продукты", "${state.added.size} продуктов дома") }
        item { DemoNotice() }
        item {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                SearchField(
                    state.query,
                    queryChanged,
                    "Добавить продукт",
                    Modifier.weight(1f),
                    !action.pending,
                )
                IconButton(
                    onClick = receipt,
                    colors =
                        IconButtonDefaults.iconButtonColors(
                            containerColor = MaterialTheme.colorScheme.primaryContainer,
                            contentColor = MaterialTheme.colorScheme.onPrimaryContainer,
                        ),
                ) {
                    Icon(Icons.Default.CameraAlt, "Добавить по фото чека")
                }
            }
        }
        item { ActionMessage(action, dismiss) }
        if (deleted != null)
            item { TextButton(undo, enabled = !action.pending) { Text("Отменить удаление") } }
        items(state.suggestions, key = { "suggestion-${it.id}" }) { ingredient ->
            TextButton(
                onClick = {
                    selectedId = ingredient.id
                    editing = false
                },
                enabled = !action.pending,
                modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
            ) {
                Text("+ ${ingredient.name}")
            }
        }
        if (state.query.isNotBlank() && state.suggestions.isEmpty())
            item { Text("В демо-каталоге ничего не найдено. Попробуйте «сыр» или «томаты».") }
        if (state.added.isEmpty())
            item {
                EmptyPanel("Пока нет продуктов", "Добавьте продукты выше, чтобы подобрать блюда.")
            }
        items(state.added, key = { it.first.id }) { (ingredient, item) ->
            Card(
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
            ) {
                Row(
                    Modifier.fillMaxWidth().padding(start = 16.dp, top = 4.dp, bottom = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(ingredient.name)
                        Text(
                            quantityLabel(item.quantity),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    IconButton({ favorite(ingredient.id) }, enabled = !action.pending) {
                        Icon(
                            if (ingredient.id in state.household.favoriteIngredients)
                                Icons.Default.Favorite
                            else Icons.Default.FavoriteBorder,
                            "Избранный ингредиент: ${ingredient.name}",
                            tint = MaterialTheme.colorScheme.primary,
                        )
                    }
                    IconButton(
                        {
                            selectedId = ingredient.id
                            editing = true
                        },
                        enabled = !action.pending,
                    ) {
                        Icon(Icons.Default.Edit, "Изменить количество: ${ingredient.name}")
                    }
                    IconButton({ remove(item) }, enabled = !action.pending) {
                        Icon(Icons.Default.DeleteOutline, "Удалить ${ingredient.name}")
                    }
                }
            }
        }
        item {
            PrimaryButton(dishes, Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
                Text("Подобрать блюда")
            }
        }
    }
}
