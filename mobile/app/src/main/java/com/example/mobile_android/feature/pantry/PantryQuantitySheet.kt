package com.example.mobile_android.feature.pantry

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.example.mobile_android.domain.*
import com.example.mobile_android.feature.common.ActionState
import com.example.mobile_android.ui.components.PrimaryButton
import com.example.mobile_android.ui.parseQuantity
import com.example.mobile_android.ui.quantityLabel

@Composable
internal fun PantryQuantitySheet(
    ingredient: Ingredient,
    current: PantryItem?,
    editing: Boolean,
    value: String,
    valueChanged: (String) -> Unit,
    unknown: Boolean,
    unknownChanged: (Boolean) -> Unit,
    action: ActionState,
    busy: Boolean,
    onDismiss: () -> Unit,
    onSave: (Quantity?) -> Unit,
    onRemove: (() -> Unit)?,
) {
    val parsed = parseQuantity(value, ingredient.unit)
    val valid = unknown || parsed != null
    val preview =
        if (!editing && !unknown && parsed != null) {
            current
                ?.quantity
                ?.takeIf { it.unit == parsed.unit }
                ?.let { runCatching { Quantity(it.value + parsed.value, parsed.unit) }.getOrNull() }
        } else null
    val keyboard = LocalSoftwareKeyboardController.current
    val latestBusy by rememberUpdatedState(busy)
    val sheet =
        rememberModalBottomSheetState(
            skipPartiallyExpanded = true,
            confirmValueChange = { target -> target != SheetValue.Hidden || !latestBusy },
        )
    ModalBottomSheet(
        onDismissRequest = { if (!busy) onDismiss() },
        sheetState = sheet,
        containerColor = MaterialTheme.colorScheme.background,
    ) {
        Column(
            Modifier.fillMaxWidth()
                .imePadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    ingredient.name,
                    Modifier.weight(1f),
                    style = MaterialTheme.typography.headlineSmall,
                )
                IconButton(onDismiss, enabled = !busy) {
                    Icon(Icons.Default.Close, "Закрыть количество")
                }
            }
            if (current != null)
                Text(
                    "Уже дома: ${quantityLabel(current.quantity)}",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            Text(
                if (editing) "Количество дома" else "Добавить количество",
                style = MaterialTheme.typography.bodyMedium,
            )
            OutlinedTextField(
                value = value,
                onValueChange = { valueChanged(it.take(20)) },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Количество, ${ingredient.unit.label}") },
                enabled = !busy && !unknown,
                singleLine = true,
                isError = !unknown && value.isNotBlank() && parsed == null,
                keyboardOptions =
                    KeyboardOptions(
                        keyboardType = KeyboardType.Decimal,
                        imeAction = ImeAction.Done,
                    ),
                keyboardActions = KeyboardActions(onDone = { keyboard?.hide() }),
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                QuantityUnit.entries.forEach { unit ->
                    FilterChip(
                        selected = unit == ingredient.unit,
                        onClick = {},
                        enabled = !busy && unit == ingredient.unit,
                        label = { Text(unit.label) },
                    )
                }
            }
            Text(
                "Единица задана каталогом. Пересчёт единиц пока недоступен.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Row(
                Modifier.fillMaxWidth()
                    .toggleable(
                        value = unknown,
                        enabled = !busy,
                        role = Role.Checkbox,
                        onValueChange = unknownChanged,
                    ),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Checkbox(unknown, null, enabled = !busy)
                Text("Количество неизвестно", Modifier.weight(1f))
            }
            if (!valid)
                Text(
                    "Введите число от 0 до 1 000 000 или укажите, что количество неизвестно.",
                    style = MaterialTheme.typography.bodySmall,
                )
            if (preview != null)
                Text(
                    "Станет дома: ${quantityLabel(preview)}",
                    color = MaterialTheme.colorScheme.tertiary,
                )
            if (editing)
                Text(
                    "Новое значение заменит количество дома. Ноль удалит продукт.",
                    style = MaterialTheme.typography.bodySmall,
                )
            else if (current != null)
                Text(
                    if (unknown || current.quantity == null)
                        "Итоговое количество останется неизвестным."
                    else "Количество добавится к запасу дома.",
                    color = MaterialTheme.colorScheme.tertiary,
                )
            if (action.failed && action.message != null)
                Text(action.message, color = MaterialTheme.colorScheme.error)
            if (busy) LinearProgressIndicator(Modifier.fillMaxWidth())
            PrimaryButton(
                {
                    keyboard?.hide()
                    onSave(if (unknown) null else parsed)
                },
                Modifier.fillMaxWidth(),
                enabled = valid && !busy,
            ) {
                Text(
                    if (busy) "Сохранение…"
                    else if (action.failed && action.message != null) "Повторить сохранение"
                    else if (editing) "Сохранить" else "Добавить к продуктам"
                )
            }
            if (onRemove != null)
                FilledTonalButton(
                    onRemove,
                    Modifier.fillMaxWidth().heightIn(min = 48.dp),
                    enabled = !busy,
                ) {
                    Text("Удалить ${ingredient.name.lowercase()}")
                }
            TextButton(onDismiss, Modifier.fillMaxWidth(), enabled = !busy) { Text("Отмена") }
        }
    }
}
