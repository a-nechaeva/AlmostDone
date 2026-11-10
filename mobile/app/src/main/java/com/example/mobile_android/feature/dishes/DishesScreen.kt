package com.example.mobile_android.feature.dishes

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
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
) {
    var filtersOpen by rememberSaveable { mutableStateOf(false) }
    if (filtersOpen)
        ModalBottomSheet(onDismissRequest = { filtersOpen = false }) {
            Column(
                Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(20.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text("Фильтры", style = MaterialTheme.typography.headlineSmall)
                Text("Время: до ${state.filters.maxMinutes} мин")
                Slider(
                    state.filters.maxMinutes.toFloat(),
                    { minutes(it.toInt()) },
                    modifier =
                        Modifier.semantics {
                            contentDescription = "Максимальное время приготовления, минуты"
                        },
                    valueRange = 5f..180f,
                )
                Text(
                    if (state.filters.maxKcal == 3000) "Калорийность: без ограничения"
                    else "Калорийность: до ${state.filters.maxKcal} ккал на порцию"
                )
                Slider(
                    state.filters.maxKcal.toFloat(),
                    { calories(it.toInt()) },
                    modifier =
                        Modifier.semantics {
                            contentDescription = "Максимальная калорийность на порцию"
                        },
                    valueRange = 100f..3000f,
                )
                Text("Способ приготовления")
                Row(
                    Modifier.horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    ChoiceChip(state.filters.method.isBlank(), { method("") }, { Text("Любой") })
                    CookingMethod.entries.forEach {
                        ChoiceChip(
                            state.filters.method == it.name,
                            { method(it.name) },
                            { Text(it.label) },
                        )
                    }
                }
                Text(
                    "Аллергены и питание учитываются из профиля.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                TextButton(reset) { Text("Сбросить фильтры") }
                PrimaryButton(
                    { filtersOpen = false },
                    Modifier.fillMaxWidth().heightIn(min = 48.dp),
                ) {
                    Text("Показать блюда")
                }
            }
        }
    val matches = if (showHidden) state.hidden else state.visible
    val groups =
        if (showHidden) listOf("Не соответствуют ограничениям" to matches)
        else
            listOf(
                "Можно сейчас" to
                    matches.filter { it.ready && it.dietary.status == Suitability.ALLOWED },
                "Докупить продукты" to
                    matches.filter {
                        !it.ready &&
                            it.uncertainQuantityIds.isEmpty() &&
                            it.dietary.status == Suitability.ALLOWED
                    },
                "Проверьте количество" to
                    matches.filter {
                        it.uncertainQuantityIds.isNotEmpty() &&
                            it.dietary.status == Suitability.ALLOWED
                    },
                "Сведения требуют проверки" to
                    matches.filter { it.dietary.status == Suitability.UNKNOWN },
            )
    LazyColumn(
        contentPadding = PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            PageHeading(
                if (showHidden) "Скрытые блюда" else "Что приготовим?",
                "${state.household.pantry.size} продуктов дома",
            )
        }
        item { DemoNotice() }
        if (!showHidden) item { TextButton(pantry) { Text("Изменить продукты дома") } }
        item {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                SearchField(state.filters.query, query, "Найти блюдо", Modifier.weight(1f))
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
        item {
            Row(
                Modifier.horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Availability.entries.forEach { option ->
                    ChoiceChip(
                        state.filters.availability == option,
                        { availability(option) },
                        { Text(option.label) },
                    )
                }
            }
        }
        item { ActionMessage(action, dismiss) }
        if (matches.isEmpty())
            item {
                EmptyPanel(
                    "Подходящих блюд нет",
                    if (showHidden) "Скрытых блюд сейчас нет."
                    else "Попробуйте изменить фильтры или продукты дома.",
                    "Сбросить фильтры",
                    reset,
                )
            }
        groups
            .filter { it.second.isNotEmpty() }
            .forEach { (title, values) ->
                item(key = "heading-$title") {
                    Text(
                        "$title · ${values.size}",
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                    )
                }
                items(values, key = { it.recipe.id }) { match ->
                    RecipeCard(
                        match,
                        match.recipe.id in state.household.favoriteRecipes,
                        { recipe(match.recipe.id) },
                        { favorite(match.recipe.id) },
                    )
                }
            }
        if (!showHidden && state.hidden.isNotEmpty())
            item {
                OutlinedButton(hidden, Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
                    Text("Скрытые блюда (${state.hidden.size})")
                }
            }
    }
}
