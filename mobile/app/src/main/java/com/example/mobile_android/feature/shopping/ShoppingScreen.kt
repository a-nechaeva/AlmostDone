package com.example.mobile_android.feature.shopping

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ShoppingBag
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.createSavedStateHandle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.example.mobile_android.feature.common.ActionState
import com.example.mobile_android.ui.*
import com.example.mobile_android.ui.components.*

@Composable
fun ShoppingScreen(
    state: ShoppingState,
    action: ActionState,
    budget: (Long) -> Unit,
    toggle: (String) -> Unit,
    removeRecipe: (String) -> Unit,
    removeManual: (String) -> Unit,
    checkout: () -> Unit,
    addSuggestion: () -> Unit,
    dishes: () -> Unit,
    dismiss: () -> Unit,
    openRecipe: ((String) -> Unit)? = null,
    openPantry: (() -> Unit)? = null,
    budgetPlanWriter: ShoppingBudgetPlanWriter? = null,
    budgetSource: ShoppingBudgetSource? = null,
) {
    val factory =
        remember(budgetSource, budgetPlanWriter) {
            viewModelFactory {
                initializer {
                    ShoppingBudgetViewModel(
                        createSavedStateHandle(),
                        budgetSource ?: FakeShoppingBudgetSource(),
                        budgetPlanWriter,
                    )
                }
            }
        }
    val budgetVm: ShoppingBudgetViewModel = viewModel(key = "shopping-budget", factory = factory)
    val form by budgetVm.form.collectAsStateWithLifecycle()
    val write by budgetVm.write.collectAsStateWithLifecycle()
    val undoPlan = budgetVm::undoPlan
    var budgetOpen by rememberSaveable { mutableStateOf(false) }
    if (budgetOpen) {
        val back = {
            if (!write.pending) {
                if (form.result != ShoppingBudgetResult.Idle) budgetVm.clearResult()
                else budgetOpen = false
            }
        }
        Dialog(
            onDismissRequest = back,
            properties = DialogProperties(usePlatformDefaultWidth = false),
        ) {
            BackHandler(onBack = back)
            Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                Scaffold(
                    topBar = {
                        BrandTopBar("План покупок", onBack = back.takeUnless { write.pending })
                    },
                ) { padding ->
                    ShoppingBudgetContent(
                        form = form,
                        catalog = state.catalog,
                        modifier = Modifier.padding(padding).consumeWindowInsets(padding),
                        change = budgetVm::textChanged,
                        submit = {
                            if (!budgetVm.write.value.pending) {
                                parseMoney(form.text)?.let(budget)
                                budgetVm.submit()
                            }
                        },
                        retry = budgetVm::retry,
                        edit = budgetVm::clearResult,
                        openRecipe = openRecipe,
                        addPlan = if (budgetPlanWriter != null) budgetVm::addPlan else null,
                        undoPlan = undoPlan,
                        write = write,
                        shoppingBusy = action.pending,
                    )
                }
            }
        }
    }
    ShoppingContent(
        state,
        action,
        toggle,
        removeRecipe,
        removeManual,
        checkout,
        addSuggestion,
        dishes,
        dismiss,
        { budgetOpen = true },
        openRecipe = openRecipe,
        openPantry = openPantry,
        budgetWrite = if (budgetOpen) BudgetPlanWriteState() else write,
        undoBudgetPlan = undoPlan,
    )
}

@Composable
internal fun ShoppingContent(
    state: ShoppingState,
    action: ActionState,
    toggle: (String) -> Unit,
    removeRecipe: (String) -> Unit,
    removeManual: (String) -> Unit,
    checkout: () -> Unit,
    addSuggestion: () -> Unit,
    dishes: () -> Unit,
    dismiss: () -> Unit,
    openBudget: () -> Unit,
    openRecipe: ((String) -> Unit)? = null,
    openPantry: (() -> Unit)? = null,
    budgetWrite: BudgetPlanWriteState = BudgetPlanWriteState(),
    undoBudgetPlan: () -> Unit = {},
) {
    val busy = action.pending || budgetWrite.pending
    val allChecked = state.quote.lines.isNotEmpty() && state.quote.lines.all { it.checked }
    LazyColumn(
        modifier = Modifier.testTag("shopping-ui-list"),
        contentPadding = PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        item {
            PageHeading(
                if (allChecked) "Покупка отмечена" else "Что докупить",
                "Из выбранных рецептов",
            )
        }
        item { DemoNotice() }
        item { ActionMessage(action, dismiss) }
        if (budgetWrite.message != null || budgetWrite.pending || budgetWrite.canUndo)
            item { BudgetPlanFeedback(budgetWrite, undoBudgetPlan, action.pending) }
        if (action.pending) item { LinearProgressIndicator(Modifier.fillMaxWidth()) }
        if (state.planWarnings.isNotEmpty())
            item {
                Text(
                    "Проверьте выбранные рецепты:\n" + state.planWarnings.joinToString("\n"),
                    color = MaterialTheme.colorScheme.error,
                )
            }
        if (state.quote.lines.isEmpty())
            item {
                ShoppingEmpty(
                    "Список пока пуст",
                    "Добавьте недостающие продукты из рецепта или посмотрите пример покупок на свой бюджет.",
                    "Подобрать покупки",
                    openBudget,
                    enabled = !busy,
                )
                TextButton(dishes, Modifier.fillMaxWidth()) { Text("Выбрать блюда") }
            }
        items(state.quote.lines, key = { it.ingredientId }) { line ->
            Card(
                colors =
                    CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                shape = RoundedCornerShape(24.dp),
            ) {
                Row(
                    Modifier.fillMaxWidth()
                        .heightIn(min = 112.dp)
                        .toggleable(
                            line.checked,
                            enabled = !busy && line.buyQuantity != null,
                            role = Role.Checkbox,
                            onValueChange = { toggle(line.ingredientId) },
                        )
                        .padding(16.dp),
                    verticalAlignment = Alignment.Top,
                ) {
                    Checkbox(
                        line.checked,
                        onCheckedChange = null,
                        modifier = Modifier.padding(top = 2.dp),
                        enabled = !busy && line.buyQuantity != null,
                    )
                    Column(
                        Modifier.weight(1f).padding(start = 12.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Text(
                            state.catalog.ingredient(line.ingredientId)?.name
                                ?: "Неизвестный продукт",
                            textDecoration = if (line.checked) TextDecoration.LineThrough else null,
                        )
                        Text(
                            if (line.buyQuantity == null) "Нет сведений об упаковке"
                            else "Купить упаковками: ${quantityLabel(line.buyQuantity)}",
                            style = MaterialTheme.typography.bodySmall,
                        )
                        Text(
                            "Нужно: ${quantityLabel(line.required)}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Text(
                            if (line.priceKopecks == null) "Нет оценки"
                            else "≈${money(line.priceKopecks)}",
                            color = MaterialTheme.colorScheme.primary,
                            fontWeight = FontWeight.Bold,
                        )
                        if (line.checked)
                            Text("Куплено", style = MaterialTheme.typography.labelLarge)
                    }
                }
            }
        }
        if (state.quote.lines.isNotEmpty()) {
            item {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("Итого примерно", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(
                        money(state.quote.totalKopecks),
                        style = MaterialTheme.typography.headlineLarge,
                        fontWeight = FontWeight.Bold,
                    )
                    Text(
                        "Демо-цены за докупаемые упаковки, ₽. В магазине могут отличаться.",
                        style = MaterialTheme.typography.bodySmall,
                    )
                    if (state.quote.totalKopecks == null)
                        Text(
                            "Стоимость и остаток бюджета неизвестны",
                            style = MaterialTheme.typography.bodySmall,
                        )
                }
            }
            item {
                ShoppingNotice(
                    if (allChecked) "Готово" else "Отметка не меняет продукты дома",
                    "Покупки отмечаются только в списке. Перенос домой — отдельное действие.",
                )
            }
            if (allChecked)
                item {
                    OutlinedButton(
                        { state.quote.lines.firstOrNull()?.let { toggle(it.ingredientId) } },
                        Modifier.fillMaxWidth().heightIn(min = 48.dp),
                        enabled = !busy,
                    ) {
                        Text(
                            if (state.quote.lines.size == 1) "Вернуть в список"
                            else "Снять первую отметку"
                        )
                    }
                }
            item {
                PrimaryButton(
                    checkout,
                    Modifier.fillMaxWidth(),
                    enabled = !busy && state.quote.lines.any { it.checked },
                ) {
                    Text("Добавить купленное домой")
                }
            }
            if (allChecked && openPantry != null)
                item {
                    PrimaryButton(openPantry, Modifier.fillMaxWidth(), enabled = !busy) {
                        Text("Мои продукты")
                    }
                }
            item {
                PrimaryButton(openBudget, Modifier.fillMaxWidth(), enabled = !busy) {
                    Text("Подобрать покупки под бюджет")
                }
            }
        }
        if (state.quote.lines.isNotEmpty() || state.suggestion != null)
            item {
                val suggestion = state.suggestion
                Card(
                    Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(18.dp),
                    colors =
                        CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                ) {
                    Column(
                        Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Text("Лучшая одиночная покупка", fontWeight = FontWeight.Bold)
                        Text(
                            "Фиксированный демо-пример, без учёта запасов и профиля.",
                            style = MaterialTheme.typography.bodySmall,
                        )
                        if (suggestion == null)
                            Text(
                                "Подходящей покупки нет. Проверьте бюджет, продукты и ограничения."
                            )
                        else {
                            Text(
                                "${suggestion.ingredient.name} · ${quantityLabel(suggestion.quantity)} · ≈${money(suggestion.priceKopecks)}"
                            )
                            Text(
                                "Вариантов блюд: ${suggestion.recipeIds.size}. Это альтернативы, а не общий план приготовления.",
                                style = MaterialTheme.typography.bodySmall,
                            )
                            suggestion.recipeIds.forEach { id ->
                                val recipe = state.catalog.recipe(id)
                                if (recipe != null && openRecipe != null)
                                    TextButton({ openRecipe(recipe.id) }) { Text(recipe.title) }
                                else Text(recipe?.title ?: "Рецепт недоступен")
                            }
                            PrimaryButton(addSuggestion, Modifier.fillMaxWidth(), enabled = !busy) {
                                Text("Добавить предложенную покупку")
                            }
                        }
                    }
                }
            }
        if (state.household.plan.isNotEmpty())
            item { Text("Выбранные рецепты", style = MaterialTheme.typography.titleMedium) }
        items(state.household.plan, key = { "plan-${it.recipeId}" }) { planned ->
            TextButton({ removeRecipe(planned.recipeId) }, enabled = !busy) {
                Text(
                    "Убрать рецепт: ${state.catalog.recipe(planned.recipeId)?.title ?: "Рецепт недоступен"} · ${planned.servings} порц."
                )
            }
        }
        items(state.household.manualPurchases, key = { "manual-${it.ingredientId}" }) { manual ->
            TextButton({ removeManual(manual.ingredientId) }, enabled = !busy) {
                Text(
                    "Убрать предложение: ${state.catalog.ingredient(manual.ingredientId)?.name.orEmpty()}"
                )
            }
        }
    }
}

@Composable
internal fun ShoppingNotice(title: String, body: String, positive: Boolean = true) {
    val background =
        if (positive) MaterialTheme.colorScheme.tertiaryContainer
        else MaterialTheme.colorScheme.primaryContainer
    val foreground =
        if (positive) MaterialTheme.colorScheme.onTertiaryContainer
        else MaterialTheme.colorScheme.onPrimaryContainer
    Surface(
        shape = RoundedCornerShape(20.dp),
        color = background,
    ) {
        Column(
            Modifier.fillMaxWidth().padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(
                title,
                fontWeight = FontWeight.Bold,
                color = foreground,
            )
            Text(
                body,
                style = MaterialTheme.typography.bodySmall,
                color = foreground,
            )
        }
    }
}

@Composable
internal fun ShoppingEmpty(
    title: String,
    body: String,
    button: String,
    click: () -> Unit,
    enabled: Boolean = true,
) {
    Column(
        Modifier.fillMaxWidth().padding(top = 64.dp, bottom = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(24.dp),
    ) {
        Surface(
            shape = RoundedCornerShape(28.dp),
            color = MaterialTheme.colorScheme.primaryContainer,
        ) {
            Icon(
                Icons.Outlined.ShoppingBag,
                null,
                Modifier.padding(26.dp).size(36.dp),
                tint = MaterialTheme.colorScheme.primary,
            )
        }
        Text(title, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        Text(body, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
        PrimaryButton(click, Modifier.fillMaxWidth(), enabled = enabled) { Text(button) }
    }
}
