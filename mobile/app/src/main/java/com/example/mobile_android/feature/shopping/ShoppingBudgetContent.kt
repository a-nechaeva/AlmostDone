package com.example.mobile_android.feature.shopping

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.example.mobile_android.domain.Catalog
import com.example.mobile_android.ui.components.*
import com.example.mobile_android.ui.money

@Composable
internal fun ShoppingBudgetContent(
    form: ShoppingBudgetForm,
    catalog: Catalog,
    change: (String) -> Unit,
    submit: () -> Unit,
    retry: () -> Unit,
    edit: () -> Unit,
    modifier: Modifier = Modifier,
    openRecipe: ((String) -> Unit)? = null,
    addExample: ((ShoppingBudgetExample) -> Unit)? = null,
    action: com.example.mobile_android.feature.common.ActionState =
        com.example.mobile_android.feature.common.ActionState(),
    dismissAction: () -> Unit = {},
) {
    val keyboard = LocalSoftwareKeyboardController.current
    val request = {
        keyboard?.hide()
        submit()
    }
    LazyColumn(
        modifier.fillMaxSize().imePadding().testTag("shopping-ui-budget"),
        contentPadding = PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(24.dp),
    ) {
        item {
            Text(
                "Демо · фиксированный пример, без расчёта плана",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        when (val result = form.result) {
            ShoppingBudgetResult.Idle -> {
                item { PageHeading("Сколько потратим?", "Пример покупок к продуктам дома") }
                item {
                    OutlinedTextField(
                        form.text,
                        change,
                        Modifier.fillMaxWidth(),
                        label = { Text("Бюджет, ₽") },
                        singleLine = true,
                        shape = RoundedCornerShape(16.dp),
                        colors =
                            OutlinedTextFieldDefaults.colors(
                                focusedContainerColor = MaterialTheme.colorScheme.surface,
                                unfocusedContainerColor = MaterialTheme.colorScheme.surface,
                                unfocusedBorderColor = Color.Transparent,
                            ),
                        isError = form.invalid,
                        supportingText = {
                            Text(
                                if (form.invalid)
                                    "Введите сумму от 0 до 1 000 000 ₽, не более двух знаков после запятой"
                                else "Цены и бюджет — в рублях",
                            )
                        },
                        keyboardOptions =
                            KeyboardOptions(
                                keyboardType = KeyboardType.Decimal,
                                imeAction = ImeAction.Done,
                            ),
                        keyboardActions = KeyboardActions(onDone = { request() }),
                    )
                }
                item {
                    Row(
                        Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        listOf("200", "500", "1000").forEach { amount ->
                            Box(Modifier.weight(1f)) {
                                ChoiceChip(
                                    selected = form.text == amount,
                                    onClick = { change(amount) },
                                    label = {
                                        Text(if (amount == "1000") "1 000 ₽" else "$amount ₽")
                                    },
                                )
                            }
                        }
                    }
                }
                item {
                    ShoppingNotice(
                        "Примерные цены",
                        "Показываем стоимость докупаемых упаковок. Фактическая сумма зависит от магазина.",
                        positive = false,
                    )
                }
                item {
                    PrimaryButton(
                        request,
                        Modifier.fillMaxWidth(),
                        enabled = !form.invalid && form.text.isNotBlank(),
                    ) {
                        Text("Подобрать план")
                    }
                }
            }
            ShoppingBudgetResult.Loading ->
                item {
                    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                        CircularProgressIndicator()
                        Text("Загружаем демонстрационный план…")
                    }
                }
            ShoppingBudgetResult.Error ->
                item {
                    EmptyPanel(
                        "План недоступен",
                        "Не удалось загрузить пример. Повторите попытку.",
                        "Повторить",
                        retry,
                    )
                }
            ShoppingBudgetResult.Empty -> {
                item { PageHeading("Бюджет ${form.text} ₽") }
                item {
                    ShoppingEmpty(
                        "Пока нет подходящего плана",
                        "Для этого примера план не найден. Измените бюджет.",
                        "Изменить бюджет",
                        edit,
                    )
                }
            }
            is ShoppingBudgetResult.Ready -> {
                val within = result.estimate == ShoppingBudgetEstimate.WITHIN_EXAMPLE_BUDGET
                item {
                    PageHeading(
                        when (result.estimate) {
                            ShoppingBudgetEstimate.WITHIN_EXAMPLE_BUDGET -> "В пределах бюджета"
                            ShoppingBudgetEstimate.ABOVE_EXAMPLE_BUDGET -> "Пример дороже бюджета"
                            ShoppingBudgetEstimate.UNKNOWN -> "Стоимость неизвестна"
                        },
                        "Бюджет ${form.text} ₽",
                    )
                }
                item {
                    ShoppingNotice(
                        if (within)
                            "≈${money(result.example.totalKopecks)} · вариантов блюд: ${result.example.alternativeRecipeIds.size}"
                        else "Пригодность бюджета не подтверждена",
                        if (result.estimate == ShoppingBudgetEstimate.UNKNOWN)
                            "Неизвестная цена не равна нулю. Стоимость и остаток бюджета неизвестны."
                        else
                            (result.remainingKopecks?.let {
                                "По демо-оценке останется ≈${money(it)}.\n"
                            } ?: "") +
                                "Цены за докупаемые упаковки. Это фиксированный пример, а не результат оптимизации.",
                        positive = within,
                    )
                }
                items(result.example.packages, key = { it.ingredientId }) { pack ->
                    Card(
                        Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(18.dp),
                        colors =
                            CardDefaults.cardColors(
                                containerColor = MaterialTheme.colorScheme.surface,
                            ),
                    ) {
                        Column(
                            Modifier.padding(16.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp),
                        ) {
                            Text(pack.label, fontWeight = FontWeight.Bold)
                            Text(pack.packageLabel)
                            Text(
                                pack.priceKopecks?.let { "≈${money(it)} за упаковку" }
                                    ?: "Нет оценки",
                                style = MaterialTheme.typography.bodySmall,
                            )
                        }
                    }
                }
                item {
                    Text(
                        "Альтернативы блюд",
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                    )
                }
                items(result.example.alternativeRecipeIds) { id ->
                    val recipe = catalog.recipe(id)
                    if (recipe != null) {
                        Card(
                            Modifier.fillMaxWidth(),
                            shape = RoundedCornerShape(24.dp),
                            colors =
                                CardDefaults.cardColors(
                                    containerColor = MaterialTheme.colorScheme.surface,
                                ),
                        ) {
                            Row(
                                Modifier.padding(12.dp),
                                horizontalArrangement = Arrangement.spacedBy(12.dp),
                            ) {
                                RecipePhoto(recipe.photo, Modifier.size(100.dp))
                                Column(Modifier.weight(1f)) {
                                    Text(
                                        recipe.title,
                                        style = MaterialTheme.typography.titleMedium,
                                        fontWeight = FontWeight.Bold,
                                    )
                                    Text(
                                        "${recipe.minutes} мин · ${recipe.nutritionPerServing?.kcal?.let { "$it ккал / порц." } ?: "КБЖУ неизвестно"}",
                                        style = MaterialTheme.typography.bodySmall,
                                    )
                                    if (openRecipe != null)
                                        TextButton({ openRecipe(id) }) { Text("Открыть рецепт") }
                                }
                            }
                        }
                    }
                }
                item {
                    Text(
                        "Блюда — отдельные варианты приготовления. Пример не проверяет ваши запасы и ограничения профиля.",
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
                if (addExample == null)
                    item {
                        Text(
                            "Покупки из примера не добавляются в список.",
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                else {
                    item { ActionMessage(action, dismissAction) }
                    if (action.pending) item { LinearProgressIndicator(Modifier.fillMaxWidth()) }
                    item {
                        PrimaryButton(
                            { addExample(result.example) },
                            Modifier.fillMaxWidth(),
                            enabled = within && !action.pending,
                        ) {
                            Text("Добавить план в покупки")
                        }
                    }
                }
                item { PrimaryButton(edit, Modifier.fillMaxWidth()) { Text("Изменить бюджет") } }
            }
        }
    }
}
