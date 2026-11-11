package com.example.mobile_android.feature.pantry

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.example.mobile_android.domain.*
import com.example.mobile_android.feature.common.ActionState
import com.example.mobile_android.ui.components.*
import com.example.mobile_android.ui.number
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
    val demoData = LocalDemoData.current
    var searching by rememberSaveable { mutableStateOf(state.query.isNotEmpty()) }
    var favoritesOnly by rememberSaveable { mutableStateOf(false) }
    var selectedId by rememberSaveable { mutableStateOf<String?>(null) }
    var editing by rememberSaveable { mutableStateOf(false) }
    var submitted by rememberSaveable { mutableStateOf(false) }
    val focus = LocalFocusManager.current
    val searchFocus = remember { FocusRequester() }
    fun closeSearch() {
        searching = false
        favoritesOnly = false
        queryChanged("")
        focus.clearFocus()
    }
    fun select(id: String, isEditing: Boolean) {
        dismiss()
        selectedId = id
        editing = isEditing
        submitted = false
        focus.clearFocus()
    }
    LaunchedEffect(Unit) {
        // A restored draft can outlive the ViewModel operation after process recreation.
        if (!action.pending && action.message == null) submitted = false
    }
    LaunchedEffect(action.pending, action.failed, action.message, submitted) {
        if (submitted && !action.pending && (action.failed || action.message != null)) {
            if (!action.failed) {
                selectedId = null
                closeSearch()
            }
            submitted = false
        }
    }
    val selected = selectedId?.let(state.catalog::ingredient)
    val current = state.household.pantry.find { it.ingredientId == selectedId }
    var quantityValue by
        rememberSaveable(selectedId, editing) {
            mutableStateOf(
                if (editing) current?.quantity?.let { number(it.value) }.orEmpty() else ""
            )
        }
    var quantityUnknown by
        rememberSaveable(selectedId, editing) {
            mutableStateOf(editing && current?.quantity == null)
        }
    val quantityContent: @Composable () -> Unit = {
        if (selected != null) {
            PantryQuantitySheet(
                ingredient = selected,
                current = current,
                editing = editing,
                value = quantityValue,
                valueChanged = { quantityValue = it },
                unknown = quantityUnknown,
                unknownChanged = { quantityUnknown = it },
                action = action,
                busy = submitted || action.pending,
                onDismiss = {
                    selectedId = null
                    dismiss()
                },
                onSave = { quantity ->
                    if (!submitted && !action.pending) {
                        submitted = true
                        if (editing) edit(selected.id, quantity) else add(selected.id, quantity)
                    }
                },
                onRemove =
                    current?.let { item ->
                        {
                            if (!submitted && !action.pending) {
                                submitted = true
                                remove(item)
                            }
                        }
                    },
            )
        }
    }
    val content: @Composable () -> Unit = {
        val fieldFocus = LocalFocusManager.current
        val keyboard = LocalSoftwareKeyboardController.current
        Column(Modifier.fillMaxSize().imePadding()) {
            if (searching) {
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    IconButton(onClick = { closeSearch() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, "Назад к продуктам")
                    }
                    Text("Добавить продукт", style = MaterialTheme.typography.titleMedium)
                }
            }
            LazyColumn(
                Modifier.weight(1f),
                contentPadding = PaddingValues(20.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                if (!searching) {
                    item {
                        PageHeading("Мои продукты", "${state.added.size} продуктов · всё под рукой")
                    }
                    if (demoData) item { PantryDemoNotice() }
                }
                if (searching || state.added.isNotEmpty()) {
                    item(key = "pantry-search") {
                        LaunchedEffect(searching, selectedId) {
                            if (searching && selectedId == null) searchFocus.requestFocus()
                        }
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            SearchField(
                                state.query,
                                {
                                    searching = true
                                    queryChanged(it)
                                },
                                "Добавить продукт",
                                Modifier.weight(1f).focusRequester(searchFocus).onFocusChanged {
                                    if (it.isFocused) searching = true
                                },
                                !action.pending,
                            )
                            if (searching) {
                                IconButton(
                                    onClick = { queryChanged("") },
                                    enabled = !action.pending,
                                ) {
                                    Icon(Icons.Default.Close, "Очистить поиск")
                                }
                            } else {
                                FilledTonalIconButton(
                                    onClick = receipt,
                                    modifier = Modifier.size(48.dp),
                                ) {
                                    Icon(Icons.Default.CameraAlt, "Добавить по фото чека")
                                }
                            }
                        }
                    }
                }
                if (selected == null) item { ActionMessage(action, dismiss) }
                if (deleted != null)
                    item {
                        TextButton(undo, enabled = !action.pending) { Text("Отменить удаление") }
                    }
                if (searching) {
                    item {
                        Text("Из каталога ингредиентов", style = MaterialTheme.typography.bodySmall)
                    }
                    if (demoData) item { PantryDemoNotice() }
                    val suggestions =
                        (if (state.query.isBlank()) state.catalog.ingredients
                            else state.suggestions)
                            .filter {
                                !favoritesOnly || it.id in state.household.favoriteIngredients
                            }
                    if (suggestions.isEmpty())
                        item {
                            EmptyPanel(
                                "Ничего не найдено",
                                if (favoritesOnly) "Попробуйте поиск по всему каталогу."
                                else "Попробуйте другое название продукта.",
                            )
                        }
                    items(suggestions, key = { "suggestion-${it.id}" }) { ingredient ->
                        val existing =
                            state.household.pantry.find { it.ingredientId == ingredient.id }
                        Card(
                            onClick = {
                                fieldFocus.clearFocus()
                                keyboard?.hide()
                                select(ingredient.id, false)
                            },
                            enabled = !action.pending,
                            colors =
                                CardDefaults.cardColors(
                                    containerColor = MaterialTheme.colorScheme.surface
                                ),
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Row(
                                Modifier.padding(16.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Column(
                                    Modifier.weight(1f),
                                    verticalArrangement = Arrangement.spacedBy(4.dp),
                                ) {
                                    Text(ingredient.name)
                                    Text(
                                        existing?.let { "Есть дома: ${quantityLabel(it.quantity)}" }
                                            ?: "Выбрать продукт",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                                Icon(Icons.Default.Add, "Выбрать ${ingredient.name}")
                            }
                        }
                    }
                    item {
                        Card(
                            onClick = { favoritesOnly = !favoritesOnly },
                            modifier =
                                Modifier.fillMaxWidth().semantics {
                                    stateDescription =
                                        if (favoritesOnly) "Только избранные" else "Весь каталог"
                                },
                            colors =
                                CardDefaults.cardColors(
                                    containerColor = MaterialTheme.colorScheme.surface
                                ),
                        ) {
                            Row(
                                Modifier.padding(16.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Column(
                                    Modifier.weight(1f),
                                    verticalArrangement = Arrangement.spacedBy(4.dp),
                                ) {
                                    Text("Избранные ингредиенты")
                                    Text(
                                        "Быстро добавить привычные продукты",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                                Icon(
                                    if (favoritesOnly) Icons.Default.Star
                                    else Icons.Default.StarBorder,
                                    null,
                                )
                            }
                        }
                    }
                    item {
                        Text(
                            "Выбирайте продукт из подсказок, чтобы одинаковые названия не дублировались.",
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                } else if (state.added.isEmpty()) {
                    item {
                        Column(
                            Modifier.fillMaxWidth().padding(top = 56.dp, bottom = 24.dp),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(20.dp),
                        ) {
                            Surface(
                                shape = RoundedCornerShape(28.dp),
                                color = MaterialTheme.colorScheme.primaryContainer,
                            ) {
                                Icon(
                                    Icons.Default.Kitchen,
                                    null,
                                    Modifier.padding(24.dp).size(40.dp),
                                    tint = MaterialTheme.colorScheme.primary,
                                )
                            }
                            Text(
                                "Что есть на кухне?",
                                style = MaterialTheme.typography.headlineSmall,
                            )
                            Text(
                                "Пока нет продуктов",
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Text(
                                "Добавьте продукты — подберём блюда и покажем, что можно докупить."
                            )
                            PrimaryButton({ searching = true }, Modifier.fillMaxWidth()) {
                                Text("Добавить продукты")
                            }
                            TextButton(receipt) {
                                Icon(Icons.Default.CameraAlt, null)
                                Spacer(Modifier.width(8.dp))
                                Text("Добавить по фото чека")
                            }
                        }
                    }
                } else {
                    items(state.added, key = { it.first.id }) { (ingredient, item) ->
                        Card(
                            colors =
                                CardDefaults.cardColors(
                                    containerColor = MaterialTheme.colorScheme.surface
                                )
                        ) {
                            Row(
                                Modifier.fillMaxWidth()
                                    .padding(start = 12.dp, top = 4.dp, bottom = 4.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Surface(
                                    shape = RoundedCornerShape(12.dp),
                                    color = MaterialTheme.colorScheme.surfaceVariant,
                                ) {
                                    Icon(
                                        Icons.Default.ShoppingBag,
                                        null,
                                        Modifier.padding(8.dp).size(20.dp),
                                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                                Column(Modifier.weight(1f).padding(start = 12.dp)) {
                                    Text(ingredient.name)
                                    Text(
                                        quantityLabel(item.quantity),
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                                val isFavorite =
                                    ingredient.id in state.household.favoriteIngredients
                                IconButton(
                                    { favorite(ingredient.id) },
                                    enabled = !action.pending,
                                    modifier =
                                        Modifier.semantics {
                                            stateDescription =
                                                if (isFavorite) "В избранном" else "Не в избранном"
                                        },
                                ) {
                                    Icon(
                                        if (isFavorite) Icons.Default.Favorite
                                        else Icons.Default.FavoriteBorder,
                                        "Избранный ингредиент: ${ingredient.name}",
                                        tint = MaterialTheme.colorScheme.primary,
                                    )
                                }
                                IconButton(
                                    { select(ingredient.id, true) },
                                    enabled = !action.pending,
                                ) {
                                    Icon(
                                        Icons.Default.Edit,
                                        "Изменить количество: ${ingredient.name}",
                                    )
                                }
                            }
                        }
                    }
                }
            }
            if (!searching) {
                Box(Modifier.verticalScroll(rememberScrollState())) {
                    PrimaryButton(
                        dishes,
                        Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 12.dp),
                    ) {
                        Text("Подобрать блюда")
                    }
                }
            }
        }
        quantityContent()
    }
    if (searching) {
        Dialog(
            onDismissRequest = { if (selectedId == null && !action.pending) closeSearch() },
            properties =
                DialogProperties(
                    dismissOnBackPress = selectedId == null && !action.pending,
                    dismissOnClickOutside = false,
                    usePlatformDefaultWidth = false,
                    decorFitsSystemWindows = false,
                ),
        ) {
            Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                Box(Modifier.windowInsetsPadding(WindowInsets.safeDrawing)) { content() }
            }
        }
    } else content()
}

@Composable
private fun PantryDemoNotice() {
    if (LocalDemoData.current) {
        Text(
            "Демо · локальный каталог и продукты на устройстве",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
