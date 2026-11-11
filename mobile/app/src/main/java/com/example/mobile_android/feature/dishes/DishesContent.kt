package com.example.mobile_android.feature.dishes

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.example.mobile_android.feature.common.ScreenState
import com.example.mobile_android.ui.components.LoadContent
import com.example.mobile_android.ui.components.PageHeading
import com.example.mobile_android.ui.components.PrimaryButton

/** Pass the dishes-tab ViewModel to both destinations so hidden dishes use the same result. */
@Composable
fun DishesContent(
    model: DishesViewModel,
    showHidden: Boolean,
    openRecipe: (String) -> Unit,
    openHidden: () -> Unit,
    openPantry: () -> Unit,
) {
    val state by model.state.collectAsStateWithLifecycle()
    val action by model.actions.state.collectAsStateWithLifecycle()
    val viewName by model.view.collectAsStateWithLifecycle()
    val query by model.query.collectAsStateWithLifecycle()
    val filters by model.filters.collectAsStateWithLifecycle()
    val inputRevision by model.inputRevision.collectAsStateWithLifecycle()
    val view = DishesView.valueOf(viewName)
    val content = rememberSaveableStateHolder()

    when (val result = state) {
        is ScreenState.Ready ->
            content.SaveableStateProvider(showHidden) {
                DishesScreen(
                    state = result.data,
                    action = action,
                    showHidden = showHidden,
                    query = model::queryChanged,
                    availability = model::availabilityChanged,
                    minutes = model::maxMinutesChanged,
                    calories = model::maxKcalChanged,
                    method = model::methodChanged,
                    reset = model::resetFilters,
                    favorite = model::favorite,
                    recipe = openRecipe,
                    hidden = openHidden,
                    pantry = openPantry,
                    dismiss = model.actions::dismiss,
                    view = view,
                    changeView = model::viewChanged,
                    addPurchase = model::addPurchase,
                    addPurchaseSet = model::addPurchaseSet,
                    queryText = query,
                    filterSelection = filters,
                    toggleAllergen = model::toggleAllergen,
                    resultsPending = result.data.inputRevision != inputRevision,
                )
            }
        else ->
            Column {
                if (!showHidden) {
                    Box(Modifier.padding(20.dp)) { DishesViewSelector(view, model::viewChanged) }
                }
                Box(Modifier.weight(1f)) {
                    if (!showHidden && view == DishesView.GRAPH) {
                        LoadContent(result, model::retry) {}
                    } else {
                        Box(Modifier.fillMaxSize().padding(horizontal = 20.dp)) {
                            when (result) {
                                ScreenState.Loading -> DishesLoading(showHidden)
                                is ScreenState.Error ->
                                    Column(Modifier.verticalScroll(rememberScrollState())) {
                                        PageHeading(
                                            if (showHidden) "Скрытые блюда" else "Что приготовим?"
                                        )
                                        DishesMessage(
                                            "Блюда не загрузились",
                                            result.message,
                                            "Попробовать снова",
                                            model::retry,
                                            Icons.Outlined.Refresh,
                                        )
                                    }
                                is ScreenState.Ready -> Unit
                            }
                        }
                    }
                }
            }
    }
}

@Composable
private fun DishesLoading(showHidden: Boolean) {
    Column(
        Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).semantics {
            progressBarRangeInfo = ProgressBarRangeInfo.Indeterminate
        },
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        PageHeading(
            if (showHidden) "Загружаем скрытые блюда" else "Подбираем блюда",
            "Учитываем продукты и фильтры",
        )
        repeat(4) {
            Surface(
                shape = MaterialTheme.shapes.medium,
                color = MaterialTheme.colorScheme.surface,
            ) {
                Row(
                    Modifier.fillMaxWidth().padding(12.dp),
                    horizontalArrangement = Arrangement.spacedBy(16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    val shape = MaterialTheme.shapes.small
                    val color = MaterialTheme.colorScheme.surfaceVariant
                    Box(Modifier.size(96.dp).background(color, shape))
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Box(Modifier.fillMaxWidth(0.92f).height(14.dp).background(color, shape))
                        Box(Modifier.fillMaxWidth(0.68f).height(12.dp).background(color, shape))
                        Box(Modifier.fillMaxWidth(0.82f).height(12.dp).background(color, shape))
                    }
                }
            }
        }
    }
}

@Composable
internal fun DishesMessage(
    title: String,
    body: String,
    actionLabel: String? = null,
    action: () -> Unit = {},
    icon: ImageVector = Icons.Outlined.Search,
) {
    Column(
        Modifier.fillMaxWidth().padding(vertical = 28.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Surface(
            modifier = Modifier.size(80.dp),
            color = MaterialTheme.colorScheme.primaryContainer,
            contentColor = MaterialTheme.colorScheme.onPrimaryContainer,
            shape = MaterialTheme.shapes.large,
        ) {
            Box(contentAlignment = Alignment.Center) {
                Icon(icon, contentDescription = null, Modifier.size(28.dp))
            }
        }
        Text(
            title,
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center,
        )
        Text(body, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
        if (actionLabel != null) {
            Spacer(Modifier.height(12.dp))
            PrimaryButton(action, Modifier.fillMaxWidth()) { Text(actionLabel) }
        }
    }
}
