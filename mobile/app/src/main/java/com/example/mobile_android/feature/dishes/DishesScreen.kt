package com.example.mobile_android.feature.dishes

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.outlined.Kitchen
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.example.mobile_android.domain.*
import com.example.mobile_android.feature.common.ActionState
import com.example.mobile_android.ui.components.*

@Composable
fun DishesScreen(
    state: DishesState,
    action: ActionState,
    showHidden: Boolean,
    query: (String) -> Unit,
    availability: (Availability) -> Unit,
    minutes: (Int) -> Unit,
    calories: (Int) -> Unit,
    method: (String) -> Unit,
    reset: () -> Unit,
    favorite: (String) -> Unit,
    recipe: (String) -> Unit,
    hidden: () -> Unit,
    pantry: () -> Unit,
    dismiss: () -> Unit,
    view: DishesView,
    changeView: (DishesView) -> Unit,
    addPurchase: () -> Unit,
    addPurchaseSet: (String) -> Unit = {},
    queryText: String = state.filters.query,
    filterSelection: DishFilters = state.filters,
    toggleAllergen: ((Allergen) -> Unit)? = null,
    resultsPending: Boolean = false,
) {
    var filtersOpen by rememberSaveable { mutableStateOf(false) }
    val graph = !showHidden && view == DishesView.GRAPH
    val pending =
        resultsPending || filterSelection != state.filters || queryText != state.filters.query
    if (filtersOpen) {
        DishesFilterSheet(
            filterSelection,
            state.visible.size.takeIf { !showHidden && !pending },
            graph,
            minutes,
            calories,
            method,
            toggleAllergen,
            reset,
            close = { filtersOpen = false },
        )
    }

    LazyColumn(
        modifier = Modifier.testTag("dishes-results"),
        contentPadding = PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (showHidden) {
            item {
                PageHeading("Почему блюда скрыты")
                if (!pending && state.hidden.isNotEmpty()) {
                    Spacer(Modifier.height(16.dp))
                    HiddenExplanation(state.filters)
                }
            }
            if (pending) {
                item { PendingDishesResults() }
                return@LazyColumn
            }
            item { ActionMessage(action, dismiss) }
            items(state.hidden, key = { it.recipe.id }) { match ->
                LocalDishCard(
                    match,
                    state.ingredientNames,
                    match.recipe.id in state.household.favoriteRecipes,
                    { recipe(match.recipe.id) },
                    { favorite(match.recipe.id) },
                )
            }
            if (state.hidden.isEmpty())
                item {
                    DishesMessage("Скрытых блюд нет", "Для этих фильтров нет исключённых блюд.")
                }
            item {
                FilledTonalButton(
                    onClick = { filtersOpen = true },
                    modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
                    shape = MaterialTheme.shapes.small,
                ) {
                    Text("Изменить фильтры")
                }
            }
        } else {
            item {
                if (graph) {
                    PageHeading(
                        "Больше блюд с одной покупкой",
                        pantryCount(state.household.pantry.size),
                    )
                } else {
                    DishesHeading(state.household.pantry.size, pantry)
                }
            }
            item {
                if (graph) DishesViewSelector(view, changeView)
                else DishesListViewSelector(view, changeView)
            }
            if (graph) {
                item { DemoNotice() }
                item { TextButton(pantry) { Text("Изменить продукты дома") } }
            }
            item {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    SearchField(queryText, query, "Найти блюдо", Modifier.weight(1f))
                    IconButton(
                        { filtersOpen = true },
                        colors =
                            IconButtonDefaults.iconButtonColors(
                                containerColor = MaterialTheme.colorScheme.primaryContainer,
                                contentColor = MaterialTheme.colorScheme.onPrimaryContainer,
                            ),
                    ) {
                        Icon(Icons.Default.Tune, "Открыть фильтры")
                    }
                }
            }
            item { AvailabilityChoices(filterSelection.availability, availability, graph) }
            if (!graph && filterSelection.activeLabels().isNotEmpty()) {
                item { ActiveDishFilters(filterSelection, { filtersOpen = true }, reset) }
            }
            if (pending) {
                item { PendingDishesResults() }
                return@LazyColumn
            }
            if (graph) {
                if (state.visible.isEmpty())
                    item {
                        EmptyPanel(
                            "Подходящих блюд нет",
                            "Попробуйте изменить фильтры или продукты дома.",
                            "Сбросить фильтры",
                            reset,
                        )
                    }
                purchaseGraph(state, action, recipe, addPurchase, reset, dismiss, addPurchaseSet)
            } else {
                if (action.message != null) item { ActionMessage(action, dismiss) }
                state.visible.groupBy(::dishGroup).toSortedMap().forEach { (group, matches) ->
                    item(key = "group-${group.name}") {
                        DishGroupHeading(group.title, matches.size)
                    }
                    items(matches, key = { it.recipe.id }) { match ->
                        LocalDishCard(
                            match,
                            state.ingredientNames,
                            match.recipe.id in state.household.favoriteRecipes,
                            { recipe(match.recipe.id) },
                            { favorite(match.recipe.id) },
                        )
                    }
                }
            }
            if (state.hidden.isNotEmpty()) {
                item {
                    if (graph) {
                        OutlinedButton(hidden, Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
                            Text("Скрытые блюда (${state.hidden.size})")
                        }
                    } else {
                        HiddenDishesLink(state.hidden.size, hidden)
                    }
                }
            }
            if (!graph && state.visible.isEmpty())
                item {
                    DishesMessage(
                        "Подходящих блюд нет",
                        "Уберите часть фильтров или добавьте другие продукты.",
                        "Сбросить фильтры",
                        reset,
                    )
                }
            if (!graph && state.visible.isNotEmpty()) item { DemoNotice() }
        }
    }
}

@Composable
private fun PendingDishesResults() {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("Уточняем подбор", color = MaterialTheme.colorScheme.onSurfaceVariant)
        LinearProgressIndicator(Modifier.fillMaxWidth())
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun AvailabilityChoices(
    selected: Availability,
    select: (Availability) -> Unit,
    graph: Boolean,
) {
    val choices: @Composable () -> Unit = {
        Availability.entries.forEach { option ->
            ChoiceChip(selected == option, { select(option) }) { Text(option.label) }
        }
    }
    if (graph) {
        Row(
            Modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            choices()
        }
    } else {
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) { choices() }
    }
}

@Composable
private fun DishesHeading(count: Int, pantry: () -> Unit) {
    Column {
        PageHeading("Что приготовим?")
        Row(
            Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(
                Icons.Outlined.Kitchen,
                null,
                Modifier.size(20.dp),
                MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                pantryCount(count),
                Modifier.weight(1f),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.bodyMedium,
            )
            TextButton(pantry) { Text("Изменить") }
        }
    }
}

@Composable
internal fun DishesListViewSelector(view: DishesView, change: (DishesView) -> Unit) {
    Surface(shape = MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.surfaceVariant) {
        Row(Modifier.fillMaxWidth().padding(4.dp).selectableGroup()) {
            DishesView.entries.forEach { option ->
                val selected = view == option
                Surface(
                    selected = selected,
                    onClick = { change(option) },
                    modifier = Modifier.weight(1f).heightIn(min = 48.dp),
                    shape = MaterialTheme.shapes.large,
                    color = if (selected) MaterialTheme.colorScheme.surface else Color.Transparent,
                    contentColor =
                        if (selected) MaterialTheme.colorScheme.onSurface
                        else MaterialTheme.colorScheme.onSurfaceVariant,
                ) {
                    Box(
                        Modifier.padding(horizontal = 8.dp, vertical = 8.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            option.label,
                            style = MaterialTheme.typography.labelLarge,
                            fontWeight = if (selected) FontWeight.Bold else FontWeight.Normal,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun ActiveDishFilters(filters: DishFilters, edit: () -> Unit, reset: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Row(
            Modifier.weight(1f).horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            filters.activeLabels().forEach { label -> ChoiceChip(true, edit) { Text(label) } }
        }
        IconButton(reset) { Icon(Icons.Default.Close, "Сбросить фильтры") }
    }
}

@Composable
private fun HiddenDishesLink(count: Int, onClick: () -> Unit) {
    Card(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.medium,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
    ) {
        Row(
            Modifier.padding(16.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text("Скрытые блюда ($count)", style = MaterialTheme.typography.titleMedium)
                Text(
                    "Причины и предупреждения",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Icon(
                Icons.Outlined.VisibilityOff,
                null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun DishGroupHeading(title: String, count: Int) {
    Row(
        Modifier.fillMaxWidth().semantics { heading() },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            title,
            Modifier.weight(1f),
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
        )
        Text(count.toString(), color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

private fun pantryCount(count: Int): String =
    "$count ${countForm(count, "продукт", "продукта", "продуктов")} дома"
