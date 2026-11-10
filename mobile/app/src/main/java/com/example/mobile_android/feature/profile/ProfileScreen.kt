package com.example.mobile_android.feature.profile

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.example.mobile_android.domain.*
import com.example.mobile_android.feature.common.ActionState
import com.example.mobile_android.ui.components.*

@Composable
fun PreferenceToggle(
    label: String,
    checked: Boolean,
    enabled: Boolean,
    onChange: (Boolean) -> Unit,
) {
    Row(
        Modifier.fillMaxWidth()
            .heightIn(min = 48.dp)
            .toggleable(checked, enabled = enabled, role = Role.Checkbox, onValueChange = onChange)
            .semantics(mergeDescendants = true) {}
            .padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Checkbox(checked, onCheckedChange = null, enabled = enabled)
        Text(label, Modifier.weight(1f).padding(start = 8.dp))
    }
}

@Composable
fun ProfileScreen(
    preferences: FoodPreferences,
    action: ActionState,
    logoutAction: ActionState,
    foodType: (FoodType) -> Unit,
    allergen: (Allergen) -> Unit,
    gluten: (Boolean) -> Unit,
    lactose: (Boolean) -> Unit,
    diabetes: (Boolean) -> Unit,
    table: (String) -> Unit,
    favorites: () -> Unit,
    logout: () -> Unit,
    dismiss: () -> Unit,
    dismissLogout: () -> Unit,
) {
    var tableText by
        rememberSaveable(preferences.dietTable) { mutableStateOf(preferences.dietTable) }
    LazyColumn(
        contentPadding = PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item { PageHeading("Профиль", "Демонстрационный режим · demo") }
        item { DemoNotice() }
        item { ActionMessage(action, dismiss) }
        item { ActionMessage(logoutAction, dismissLogout) }
        item {
            OutlinedButton(favorites, Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
                Text("Избранные блюда и ингредиенты")
            }
        }
        item { Text("Предпочтения питания", style = MaterialTheme.typography.titleLarge) }
        item {
            Column {
                FoodType.entries.forEach { type ->
                    Row(
                        Modifier.fillMaxWidth()
                            .heightIn(min = 48.dp)
                            .selectable(
                                type == preferences.foodType,
                                enabled = !action.pending,
                                role = Role.RadioButton,
                                onClick = { foodType(type) },
                            )
                            .semantics(mergeDescendants = true) {},
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        RadioButton(
                            type == preferences.foodType,
                            onClick = null,
                            enabled = !action.pending,
                        )
                        Text(type.label, Modifier.padding(start = 8.dp))
                    }
                }
            }
        }
        item { Text("Исключить аллергены", style = MaterialTheme.typography.titleLarge) }
        item {
            Column {
                Allergen.entries.forEach { value ->
                    PreferenceToggle(
                        value.label,
                        value in preferences.excludedAllergens,
                        !action.pending,
                    ) {
                        allergen(value)
                    }
                }
            }
        }
        item {
            Column {
                PreferenceToggle("Без глютена", preferences.glutenFree, !action.pending, gluten)
                PreferenceToggle("Без лактозы", preferences.lactoseFree, !action.pending, lactose)
                PreferenceToggle(
                    "Учитывать диабет",
                    preferences.diabetes,
                    !action.pending,
                    diabetes,
                )
            }
        }
        item {
            Text(
                "Критерии для диабета и диетических столов ещё не согласованы. При их выборе соответствие блюд остаётся неизвестным.",
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        item {
            OutlinedTextField(
                tableText,
                { tableText = it.take(100) },
                Modifier.fillMaxWidth(),
                label = { Text("Диетический стол") },
                supportingText = {
                    Text("Сохранится как ваше указание; автоматическая проверка недоступна.")
                },
            )
        }
        item {
            TextButton({ table(tableText) }, enabled = !action.pending) {
                Text("Сохранить название стола")
            }
        }
        item {
            OutlinedButton(
                logout,
                Modifier.fillMaxWidth().heightIn(min = 48.dp),
                enabled = !action.pending && !logoutAction.pending,
            ) {
                Text("Выйти из демо")
            }
        }
        item {
            Text(
                "При выходе продукты, покупки и настройки остаются на этом устройстве.",
                style = MaterialTheme.typography.bodySmall,
            )
        }
    }
}
