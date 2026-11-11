package com.example.mobile_android.ui.components

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.example.mobile_android.R
import com.example.mobile_android.domain.*
import com.example.mobile_android.feature.common.*
import com.example.mobile_android.ui.*

@Composable
fun BrandTopBar(
    title: String = "почти готово",
    onBack: (() -> Unit)? = null,
    onFavorites: (() -> Unit)? = null,
    topBarActions: @Composable RowScope.() -> Unit = {},
) {
    TopAppBar(
        title = { Text(title, fontWeight = FontWeight.Bold) },
        navigationIcon = {
            if (onBack != null)
                IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Назад") }
            else
                Icon(
                    painterResource(R.drawable.ic_bowl),
                    null,
                    Modifier.padding(start = 20.dp),
                    tint = MaterialTheme.colorScheme.primary,
                )
        },
        actions = {
            topBarActions()
            if (onFavorites != null)
                IconButton(onClick = onFavorites) {
                    Icon(Icons.Default.FavoriteBorder, "Избранное")
                }
        },
        colors =
            TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
    )
}

@Composable
fun DemoNotice() {
    Text(
        "Демо · цены и КБЖУ приведены для примера",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

@Composable
fun PageHeading(title: String, subtitle: String? = null) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(title, style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
        if (subtitle != null) Text(subtitle, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
fun <T> LoadContent(state: ScreenState<T>, retry: () -> Unit, content: @Composable (T) -> Unit) {
    // Keep local form drafts when a screen's data stream restarts after a lifecycle pause.
    val savedContent = rememberSaveableStateHolder()
    when (state) {
        ScreenState.Loading ->
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        is ScreenState.Error -> EmptyPanel("Данные недоступны", state.message, "Повторить", retry)
        is ScreenState.Ready ->
            savedContent.SaveableStateProvider("ready-content") { content(state.data) }
    }
}

@Composable
fun EmptyPanel(title: String, body: String, button: String? = null, onClick: () -> Unit = {}) {
    Column(
        Modifier.fillMaxWidth().padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
        Text(body, color = MaterialTheme.colorScheme.onSurfaceVariant)
        if (button != null)
            Button(onClick = onClick, modifier = Modifier.heightIn(min = 48.dp)) { Text(button) }
    }
}

@Composable
fun ActionMessage(state: ActionState, dismiss: () -> Unit) {
    if (state.message != null)
        Surface(
            shape = RoundedCornerShape(16.dp),
            color =
                if (state.failed) MaterialTheme.colorScheme.errorContainer
                else MaterialTheme.colorScheme.surfaceVariant,
        ) {
            Row(Modifier.padding(start = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    state.message,
                    Modifier.weight(1f),
                    color =
                        if (state.failed) MaterialTheme.colorScheme.onErrorContainer
                        else MaterialTheme.colorScheme.onSurfaceVariant,
                )
                IconButton(onClick = dismiss) { Icon(Icons.Default.Close, "Скрыть сообщение") }
            }
        }
}

@Composable
fun RecipePhoto(
    photo: String,
    modifier: Modifier = Modifier,
    contentDescription: String? = null,
    corner: Dp = 22.dp,
) {
    if (photo == "pasta" || photo == "omelette") {
        Image(
            painterResource(if (photo == "pasta") R.drawable.recipe_pasta else R.drawable.recipe_omelette),
            contentDescription,
            modifier.clip(RoundedCornerShape(corner)),
            contentScale = ContentScale.Crop,
        )
    } else {
        Box(
            modifier.clip(RoundedCornerShape(corner))
                .background(MaterialTheme.colorScheme.surfaceVariant)
                .then(if (contentDescription != null) Modifier.semantics { this.contentDescription = contentDescription } else Modifier)
        )
    }
}

@Composable
fun RecipeCard(
    match: RecipeMatch,
    favorite: Boolean,
    onClick: () -> Unit,
    onFavorite: () -> Unit,
    favoriteEnabled: Boolean = true,
) {
    Card(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
    ) {
        Row(
            Modifier.padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            RecipePhoto(match.recipe.photo, Modifier.size(100.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    match.recipe.title,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                )
                Text(
                    "${match.recipe.minutes} мин · ${match.recipe.nutritionPerServing?.kcal?.let { "$it ккал / порц." } ?: "КБЖУ неизвестно"}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                val status =
                    when {
                        match.dietary.status == Suitability.HIDDEN ->
                            match.dietary.reasons.firstOrNull()
                                ?: "Не соответствует выбранным ограничениям"
                        match.dietary.status == Suitability.UNKNOWN ->
                            match.dietary.reasons.firstOrNull() ?: "Сведения требуют проверки"
                        match.uncertainQuantityIds.isNotEmpty() -> "Проверьте количество продуктов"
                        match.ready -> "Все продукты есть"
                        else ->
                            "Докупить ${match.missing.size} · ${if (match.purchaseKopecks == null) "нет оценки" else "≈${money(match.purchaseKopecks)}"}"
                    }
                Text(
                    status,
                    style = MaterialTheme.typography.bodySmall,
                    color =
                        if (match.ready && match.dietary.status == Suitability.ALLOWED)
                            MaterialTheme.colorScheme.onSurface
                        else MaterialTheme.colorScheme.primary,
                )
            }
            IconButton(
                onClick = onFavorite,
                enabled = favoriteEnabled,
                colors = IconButtonDefaults.iconButtonColors(contentColor = MaterialTheme.colorScheme.primary),
                modifier = Modifier.sizeIn(minWidth = 48.dp, minHeight = 48.dp),
            ) {
                Icon(
                    if (favorite) Icons.Default.Favorite else Icons.Default.FavoriteBorder,
                    if (favorite) "Убрать ${match.recipe.title} из избранного"
                    else "В избранное: ${match.recipe.title}",
                )
            }
        }
    }
}

@Composable
fun QuantityDialog(
    ingredient: Ingredient,
    current: Quantity?,
    editing: Boolean,
    onDismiss: () -> Unit,
    onSave: (Quantity?) -> Unit,
) {
    var value by
        rememberSaveable(ingredient.id, editing) {
            mutableStateOf(
                current?.takeIf { it.unit == ingredient.unit }?.let { number(it.value) }.orEmpty()
            )
        }
    val parsed = parseQuantity(value, ingredient.unit)
    val valid = value.isBlank() || parsed != null
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(ingredient.name) },
        text = {
            Column(
                Modifier.verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                OutlinedTextField(
                    value,
                    { value = it.take(20) },
                    label = { Text("Количество, ${ingredient.unit.label}") },
                    singleLine = true,
                    isError = !valid,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                )
                Text(
                    if (valid) "Оставьте поле пустым, если количество неизвестно."
                    else "Введите число от 0 до 1 000 000.",
                    style = MaterialTheme.typography.bodySmall,
                )
                if (editing)
                    Text(
                        "Сохранение нулевого количества удалит продукт.",
                        style = MaterialTheme.typography.bodySmall,
                    )
            }
        },
        confirmButton = {
            TextButton(onClick = { onSave(parsed) }, enabled = valid) {
                Text(if (editing) "Сохранить" else "Добавить")
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Отмена") } },
    )
}

@Composable
fun PrimaryButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    content: @Composable RowScope.() -> Unit,
) {
    Button(
        onClick = onClick,
        modifier = modifier.heightIn(min = 48.dp),
        enabled = enabled,
        shape = RoundedCornerShape(16.dp),
        content = content,
    )
}

@Composable
fun ChoiceChip(selected: Boolean, onClick: () -> Unit, label: @Composable () -> Unit) {
    FilterChip(
        selected = selected,
        onClick = onClick,
        label = label,
        shape = RoundedCornerShape(24.dp),
        border = null,
        colors =
            FilterChipDefaults.filterChipColors(
                containerColor = MaterialTheme.colorScheme.surface,
                selectedContainerColor = MaterialTheme.colorScheme.primaryContainer,
                labelColor = MaterialTheme.colorScheme.onSurfaceVariant,
                selectedLabelColor = MaterialTheme.colorScheme.onPrimaryContainer,
            ),
    )
}

@Composable
fun SearchField(
    value: String,
    onChange: (String) -> Unit,
    label: String,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    val keyboard = LocalSoftwareKeyboardController.current
    TextField(
        value = value,
        onValueChange = onChange,
        modifier = modifier.semantics { contentDescription = label },
        placeholder = { Text(label) },
        leadingIcon = { Icon(Icons.Default.Search, null) },
        singleLine = true,
        enabled = enabled,
        shape = RoundedCornerShape(24.dp),
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
        keyboardActions = KeyboardActions(onSearch = { keyboard?.hide() }),
        colors =
            TextFieldDefaults.colors(
                focusedContainerColor = MaterialTheme.colorScheme.surface,
                unfocusedContainerColor = MaterialTheme.colorScheme.surface,
                disabledContainerColor = MaterialTheme.colorScheme.surface,
                focusedIndicatorColor = Color.Transparent,
                unfocusedIndicatorColor = Color.Transparent,
                disabledIndicatorColor = Color.Transparent,
            ),
    )
}
