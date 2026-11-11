package com.example.mobile_android.feature.dishes

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.outlined.Microwave
import androidx.compose.material.icons.outlined.NoMeals
import androidx.compose.material.icons.outlined.OutdoorGrill
import androidx.compose.material.icons.outlined.SoupKitchen
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.example.mobile_android.domain.Allergen
import com.example.mobile_android.domain.CookingMethod
import com.example.mobile_android.ui.components.ChoiceChip
import com.example.mobile_android.ui.components.PrimaryButton

@Composable
internal fun DishesFilterSheet(
    filters: DishFilters,
    visibleCount: Int?,
    graph: Boolean,
    minutes: (Int) -> Unit,
    calories: (Int) -> Unit,
    method: (String) -> Unit,
    toggleAllergen: ((Allergen) -> Unit)?,
    reset: () -> Unit,
    close: () -> Unit,
) {
    val defaults = DishFilters()
    ModalBottomSheet(
        onDismissRequest = close,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = !graph),
        containerColor = MaterialTheme.colorScheme.background,
    ) {
        Column(Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, bottom = 12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    "Фильтры",
                    Modifier.weight(1f),
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.Bold,
                )
                TextButton(reset) { Text("Сбросить") }
                IconButton(close) { Icon(Icons.Default.Close, "Закрыть фильтры") }
            }
            Column(
                Modifier.fillMaxWidth()
                    .weight(1f, fill = false)
                    .verticalScroll(rememberScrollState())
                    .padding(vertical = 12.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                if (graph) {
                    GraphFilterLimits(filters, defaults, minutes, calories)
                } else {
                    LimitPresets(
                        "Время приготовления",
                        filters.maxMinutes,
                        listOf(
                            defaults.maxMinutes to "Любое",
                            15 to "До 15 мин",
                            30 to "До 30 мин",
                        ),
                        minutes,
                    )
                    LimitPresets(
                        "Калорийность на порцию",
                        filters.maxKcal,
                        listOf(defaults.maxKcal to "Любая", 400 to "До 400", 600 to "До 600"),
                        calories,
                    )
                }
                if (toggleAllergen != null) {
                    AllergenOptions(filters.excludedAllergens, toggleAllergen)
                } else {
                    Text(
                        "Действуют ограничения питания из профиля.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                if (graph) {
                    FilterHeading("Способ приготовления")
                    Row(
                        Modifier.horizontalScroll(rememberScrollState()),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        ChoiceChip(filters.method.isBlank(), { method("") }) { Text("Любой") }
                        CookingMethod.entries.forEach { option ->
                            ChoiceChip(filters.method == option.name, { method(option.name) }) {
                                Text(option.label)
                            }
                        }
                    }
                } else {
                    EquipmentFilter(filters.method, method)
                }
            }
            PrimaryButton(close, Modifier.fillMaxWidth()) {
                Text(
                    if (graph || visibleCount == null || visibleCount == 0) "Показать блюда"
                    else
                        "Показать $visibleCount ${countForm(visibleCount, "блюдо", "блюда", "блюд")}"
                )
            }
        }
    }
}

@Composable
private fun AllergenOptions(selected: Set<Allergen>, toggle: (Allergen) -> Unit) {
    Column {
        FilterHeading("Исключить аллергены")
        Text(
            "Для этого подбора. Ограничения из профиля тоже действуют.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            listOf(
                    listOf(Allergen.MILK, Allergen.GLUTEN, Allergen.EGGS),
                    listOf(Allergen.NUTS, Allergen.FISH, Allergen.SOY),
                )
                .forEach { allergens ->
                    Column(Modifier.weight(1f)) {
                        allergens.forEach { allergen ->
                            val checked = allergen in selected
                            Row(
                                Modifier.fillMaxWidth().heightIn(min = 48.dp).toggleable(
                                    checked,
                                    role = Role.Checkbox,
                                ) {
                                    toggle(allergen)
                                },
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Checkbox(checked, onCheckedChange = null)
                                Text(allergen.label, style = MaterialTheme.typography.bodyMedium)
                            }
                        }
                    }
                }
        }
    }
}

@Composable
private fun LimitPresets(
    title: String,
    selected: Int,
    options: List<Pair<Int, String>>,
    select: (Int) -> Unit,
) {
    Column {
        FilterHeading(title)
        Row(
            Modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            options.forEach { (value, label) ->
                ChoiceChip(selected == value, { select(value) }) { Text(label) }
            }
            if (options.none { it.first == selected }) {
                ChoiceChip(true, { select(options.first().first) }) { Text("До $selected") }
            }
        }
    }
}

@Composable
private fun GraphFilterLimits(
    filters: DishFilters,
    defaults: DishFilters,
    minutes: (Int) -> Unit,
    calories: (Int) -> Unit,
) {
    Column {
        val unlimited = (MAX_MINUTES + 1).toFloat()
        Text(
            if (filters.hasTimeLimit) "Время: до ${filters.maxMinutes} мин"
            else "Время: без ограничения"
        )
        Slider(
            if (filters.hasTimeLimit) filters.maxMinutes.toFloat() else unlimited,
            { minutes(if (it == unlimited) ANY_MINUTES else it.toInt()) },
            modifier =
                Modifier.semantics {
                    contentDescription = "Максимальное время приготовления, минуты"
                },
            valueRange = 5f..unlimited,
        )
        Text(
            if (filters.hasCalorieLimit) "Калорийность: до ${filters.maxKcal} ккал на порцию"
            else "Калорийность: без ограничения"
        )
        Slider(
            filters.maxKcal.toFloat(),
            { calories(it.toInt()) },
            modifier =
                Modifier.semantics { contentDescription = "Максимальная калорийность на порцию" },
            valueRange = 100f..defaults.maxKcal.toFloat(),
        )
    }
}

@Composable
private fun EquipmentFilter(selected: String, select: (String) -> Unit) {
    val options =
        listOf(
            Triple(CookingMethod.STOVE, "Плита", Icons.Outlined.SoupKitchen),
            Triple(CookingMethod.OVEN, "Духовка", Icons.Outlined.OutdoorGrill),
            Triple(CookingMethod.MICROWAVE, "СВЧ", Icons.Outlined.Microwave),
            Triple(CookingMethod.NO_COOK, CookingMethod.NO_COOK.label, Icons.Outlined.NoMeals),
        )
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        FilterHeading("Оборудование")
        Row(
            Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            options.forEach { (option, label, icon) ->
                val active = selected == option.name
                Surface(
                    selected = active,
                    onClick = { select(if (active) "" else option.name) },
                    modifier = Modifier.widthIn(min = 100.dp),
                    shape = MaterialTheme.shapes.small,
                    color =
                        if (active) MaterialTheme.colorScheme.primaryContainer
                        else MaterialTheme.colorScheme.surface,
                    contentColor =
                        if (active) MaterialTheme.colorScheme.onPrimaryContainer
                        else MaterialTheme.colorScheme.onSurfaceVariant,
                ) {
                    Column(
                        Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Icon(icon, contentDescription = null)
                        Text(label, style = MaterialTheme.typography.labelMedium)
                    }
                }
            }
        }
        if (selected.isEmpty()) {
            Text("Подходит любое оборудование", style = MaterialTheme.typography.bodySmall)
        }
    }
}

@Composable
private fun FilterHeading(title: String) {
    Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
}

internal fun DishFilters.activeLabels(): List<String> = buildList {
    if (hasTimeLimit) add("До $maxMinutes мин")
    if (hasCalorieLimit) add("До $maxKcal ккал")
    CookingMethod.entries.firstOrNull { it.name == method }?.let { add(it.label) }
    excludedAllergens.forEach { allergen ->
        add(
            when (allergen) {
                Allergen.MILK -> "Без молока"
                Allergen.GLUTEN -> "Без глютена"
                Allergen.EGGS -> "Без яиц"
                Allergen.NUTS -> "Без орехов"
                Allergen.PEANUTS -> "Без арахиса"
                Allergen.SESAME -> "Без кунжута"
                Allergen.FISH -> "Без рыбы"
                Allergen.SOY -> "Без сои"
            }
        )
    }
}
