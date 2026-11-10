package com.example.mobile_android.feature.profile

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.Eco
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.DialogProperties
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
            .heightIn(min = 52.dp)
            .toggleable(checked, enabled = enabled, role = Role.Checkbox, onValueChange = onChange)
            .semantics(mergeDescendants = true) {}
            .padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Checkbox(checked, onCheckedChange = null, enabled = enabled)
        Text(
            label,
            Modifier.weight(1f).padding(start = 12.dp),
            style = MaterialTheme.typography.bodyMedium,
        )
    }
}

/** Legacy callbacks stay source-compatible; the host must supply onSave for atomic writes. */
@Suppress("UNUSED_PARAMETER")
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
    onSave: ((FoodPreferences) -> Unit)? = null,
) {
    ProfileContent(
        preferences,
        action,
        logoutAction,
        favorites,
        logout,
        dismiss,
        dismissLogout,
        onSave,
    )
}

private enum class ProfilePage {
    HOME,
    PREFERENCES,
    ALLERGENS,
    TABLE,
}

private val PreferencesSaver =
    listSaver<FoodPreferences, Any>(
        save = {
            listOf(
                it.foodType.name,
                it.excludedAllergens.joinToString(",") { a -> a.name },
                it.glutenFree,
                it.lactoseFree,
                it.diabetes,
                it.dietTable,
            )
        },
        restore = {
            FoodPreferences(
                FoodType.valueOf(it[0] as String),
                (it[1] as String)
                    .split(',')
                    .filter(String::isNotEmpty)
                    .map(Allergen::valueOf)
                    .toSet(),
                it[2] as Boolean,
                it[3] as Boolean,
                it[4] as Boolean,
                it[5] as String,
            )
        },
    )

@Composable
fun ProfileContent(
    preferences: FoodPreferences,
    action: ActionState,
    logoutAction: ActionState,
    favorites: () -> Unit,
    logout: () -> Unit,
    dismiss: () -> Unit,
    dismissLogout: () -> Unit,
    onSave: ((FoodPreferences) -> Unit)?,
) {
    var page by rememberSaveable { mutableStateOf(ProfilePage.HOME) }
    var draft by rememberSaveable(stateSaver = PreferencesSaver) { mutableStateOf(preferences) }
    var nestedBaseline by
        rememberSaveable(stateSaver = PreferencesSaver) { mutableStateOf(preferences) }
    var submitted by remember { mutableStateOf(false) }
    var confirmLogout by rememberSaveable { mutableStateOf(false) }
    val keyboard = LocalSoftwareKeyboardController.current
    val busy = action.pending || logoutAction.pending || submitted

    fun cancel() {
        if (busy) return
        keyboard?.hide()
        when (page) {
            ProfilePage.ALLERGENS,
            ProfilePage.TABLE -> {
                draft = nestedBaseline
                page = ProfilePage.PREFERENCES
            }
            ProfilePage.PREFERENCES -> {
                draft = preferences
                page = ProfilePage.HOME
            }
            ProfilePage.HOME -> confirmLogout = false
        }
    }

    BackHandler(page != ProfilePage.HOME || confirmLogout) { cancel() }
    LaunchedEffect(action, preferences, submitted) {
        if (action.pending && page == ProfilePage.PREFERENCES) submitted = true
        if (submitted && !action.pending) {
            if (action.failed) submitted = false
            else if (preferences == draft.copy(dietTable = draft.dietTable.trim())) {
                submitted = false
                page = ProfilePage.HOME
            }
        }
    }

    Column(Modifier.fillMaxSize().imePadding()) {
        if (page != ProfilePage.HOME) {
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconButton(onClick = ::cancel, enabled = !busy) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, "Назад")
                }
                Text(
                    when (page) {
                        ProfilePage.ALLERGENS -> "Аллергены"
                        ProfilePage.TABLE -> "Диетический стол"
                        else -> "Питание и аллергены"
                    },
                    Modifier.weight(1f),
                    style = MaterialTheme.typography.titleMedium,
                )
                TextButton(onClick = ::cancel, enabled = !busy) { Text("Отмена") }
            }
        }
        // Each form has its own scroll position; long labels and large fonts grow naturally.
        key(page) {
            Column(
                Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(20.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                ActionMessage(action, dismiss)
                if (!confirmLogout) ActionMessage(logoutAction, dismissLogout)
                when (page) {
                    ProfilePage.HOME -> {
                        ProfileHeading("Профиль")
                        Row(
                            Modifier.padding(vertical = 20.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(20.dp),
                        ) {
                            Surface(
                                shape = MaterialTheme.shapes.large,
                                color = MaterialTheme.colorScheme.primaryContainer,
                            ) {
                                Box(Modifier.size(64.dp), contentAlignment = Alignment.Center) {
                                    Icon(
                                        Icons.Default.PersonOutline,
                                        null,
                                        tint = MaterialTheme.colorScheme.primary,
                                    )
                                }
                            }
                            Column {
                                Text(
                                    "Демо-профиль",
                                    style = MaterialTheme.typography.titleLarge,
                                    fontWeight = FontWeight.Bold,
                                )
                                Text(
                                    "Логин: demo",
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    style =
                                        MaterialTheme.typography.bodySmall.copy(fontSize = 13.sp),
                                )
                            }
                        }
                        ProfileRow(
                            "Питание и аллергены",
                            preferenceSummary(preferences),
                            Icons.Outlined.Eco,
                            !busy,
                        ) {
                            dismiss()
                            draft = preferences
                            page = ProfilePage.PREFERENCES
                        }
                        ProfileRow(
                            "Избранное",
                            "Блюда и ингредиенты",
                            Icons.Default.FavoriteBorder,
                            !busy,
                            favorites,
                        )
                        Spacer(Modifier.height(16.dp))
                        ProfileRow(
                            "Выйти из демо",
                            "Завершить текущую сессию",
                            Icons.AutoMirrored.Filled.KeyboardArrowRight,
                            !busy,
                        ) {
                            dismissLogout()
                            confirmLogout = true
                        }
                        Text(
                            "Демонстрационный режим. Настройки хранятся на этом устройстве.",
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            style = MaterialTheme.typography.bodySmall,
                        )
                        Text(
                            "При ограничениях питания проверяйте состав. Сведения могут быть неполными.",
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                    ProfilePage.PREFERENCES -> {
                        ProfileHeading("Предпочтения питания")
                        Text("Тип питания", style = MaterialTheme.typography.titleMedium)
                        Column(Modifier.selectableGroup()) {
                            FoodType.entries.forEach { type ->
                                Row(
                                    Modifier.fillMaxWidth()
                                        .heightIn(min = 48.dp)
                                        .selectable(
                                            draft.foodType == type,
                                            enabled = !busy,
                                            role = Role.RadioButton,
                                            onClick = { draft = draft.copy(foodType = type) },
                                        )
                                        .semantics(mergeDescendants = true) {},
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    RadioButton(
                                        draft.foodType == type,
                                        onClick = null,
                                        enabled = !busy,
                                    )
                                    Text(
                                        type.profileLabel,
                                        Modifier.weight(1f).padding(start = 12.dp),
                                        style = MaterialTheme.typography.bodyMedium,
                                    )
                                }
                            }
                        }
                        ProfileRow(
                            "Аллергены",
                            allergenSummary(draft),
                            Icons.AutoMirrored.Filled.KeyboardArrowRight,
                            !busy,
                        ) {
                            nestedBaseline = draft
                            page = ProfilePage.ALLERGENS
                        }
                        Column {
                            PreferenceToggle("Без глютена", draft.glutenFree, !busy) {
                                draft = draft.copy(glutenFree = it)
                            }
                            PreferenceToggle("Без лактозы", draft.lactoseFree, !busy) {
                                draft = draft.copy(lactoseFree = it)
                            }
                            PreferenceToggle("Диабет", draft.diabetes, !busy) {
                                draft = draft.copy(diabetes = it)
                            }
                        }
                        ProfileRow(
                            "Диетический стол",
                            draft.dietTable.ifBlank { "Не выбран" },
                            Icons.AutoMirrored.Filled.KeyboardArrowRight,
                            !busy,
                        ) {
                            nestedBaseline = draft
                            page = ProfilePage.TABLE
                        }
                        ProfileNotice(
                            "Проверяйте сведения",
                            "При неполных данных покажем предупреждение о составе.",
                        )
                        if (draft.diabetes || draft.dietTable.isNotBlank())
                            ProfileNotice(
                                "Соответствие не подтверждено",
                                "Правила для диабета и диетических столов ещё не согласованы. Рецепты не проверяются на соответствие этим назначениям.",
                            )
                        if (onSave == null)
                            ProfileNotice(
                                "Сохранение пока недоступно",
                                "Подключение сохранения настроек запланировано на следующий этап. Черновик можно просмотреть и отменить.",
                            )
                        PrimaryButton(
                            onClick = {
                                keyboard?.hide()
                                dismiss()
                                submitted = true
                                onSave?.invoke(draft.copy(dietTable = draft.dietTable.trim()))
                            },
                            modifier = Modifier.fillMaxWidth(),
                            enabled =
                                onSave != null &&
                                    !busy &&
                                    draft.copy(dietTable = draft.dietTable.trim()) != preferences,
                        ) {
                            Text(if (busy) "Сохраняем…" else "Сохранить предпочтения")
                        }
                    }
                    ProfilePage.ALLERGENS -> {
                        ProfileHeading("Что исключить?", "Выберите нужные аллергены")
                        Column {
                            Allergen.entries.forEach { allergen ->
                                PreferenceToggle(
                                    allergen.profileLabel,
                                    allergen in draft.excludedAllergens,
                                    !busy,
                                ) {
                                    draft =
                                        draft.copy(
                                            excludedAllergens =
                                                if (it) draft.excludedAllergens + allergen
                                                else draft.excludedAllergens - allergen
                                        )
                                }
                            }
                        }
                        PrimaryButton(
                            { page = ProfilePage.PREFERENCES },
                            Modifier.fillMaxWidth(),
                            !busy,
                        ) {
                            Text("Сохранить выбор")
                        }
                        ProfileNotice(
                            "Сведения могут быть неполными",
                            "Отсутствие записи об аллергене не подтверждает его отсутствие.",
                        )
                        Text(
                            "Без лактозы — отдельное ограничение. Оно не заменяет исключение молочного белка.",
                            style = MaterialTheme.typography.bodySmall,
                        )
                        Text(
                            "Выбор войдёт в черновик. Примените его кнопкой «Сохранить предпочтения».",
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                    ProfilePage.TABLE -> {
                        ProfileHeading("Диетический стол")
                        TextField(
                            draft.dietTable,
                            { draft = draft.copy(dietTable = it.take(100)) },
                            Modifier.fillMaxWidth(),
                            enabled = !busy,
                            label = { Text("Название из назначения") },
                            supportingText = { Text("До 100 символов") },
                            placeholder = { Text("Не выбран") },
                            shape = RoundedCornerShape(16.dp),
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
                        ProfileNotice(
                            "Соответствие не подтверждено",
                            "Рецепты пока не проверяются на соответствие диетическому столу.",
                        )
                        Text(
                            "Сохраняем указанное название. Это не подтверждает, что рецепты соответствуют назначению."
                        )
                        PrimaryButton(
                            {
                                keyboard?.hide()
                                page = ProfilePage.PREFERENCES
                            },
                            Modifier.fillMaxWidth(),
                            !busy,
                        ) {
                            Text("Сохранить")
                        }
                        Text(
                            "Название войдёт в черновик. Примените его кнопкой «Сохранить предпочтения».",
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                }
            }
        }
    }
    if (confirmLogout)
        BasicAlertDialog(
            onDismissRequest = { if (!logoutAction.pending) confirmLogout = false },
            modifier = Modifier.padding(horizontal = 28.dp).widthIn(max = 560.dp).fillMaxWidth(),
            properties = DialogProperties(usePlatformDefaultWidth = false),
        ) {
            Surface(
                shape = MaterialTheme.shapes.large,
                color = MaterialTheme.colorScheme.background,
            ) {
                Column(
                    Modifier.verticalScroll(rememberScrollState()).padding(24.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    Text(
                        "Выйти из демо?",
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                    )
                    Text(
                        "Продукты, покупки и настройки останутся на этом устройстве. Для входа используйте demo / demo.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    ActionMessage(logoutAction, dismissLogout)
                    PrimaryButton(logout, Modifier.fillMaxWidth(), !logoutAction.pending) {
                        Text(if (logoutAction.pending) "Выходим…" else "Выйти")
                    }
                    FilledTonalButton(
                        { confirmLogout = false },
                        Modifier.fillMaxWidth().heightIn(min = 48.dp),
                        enabled = !logoutAction.pending,
                        shape = RoundedCornerShape(16.dp),
                    ) {
                        Text("Отмена")
                    }
                }
            }
        }
}

private val FoodType.profileLabel: String
    get() =
        when (this) {
            FoodType.ANY -> "Без ограничений"
            FoodType.VEGETARIAN -> "Вегетарианство"
            FoodType.VEGAN -> "Веганство"
        }
private val Allergen.profileLabel: String
    get() =
        when (this) {
            Allergen.MILK -> "Молоко (молочный белок)"
            Allergen.GLUTEN -> "Глютен"
            else -> label
        }

private fun allergenSummary(p: FoodPreferences) =
    Allergen.entries
        .filter { it in p.excludedAllergens }
        .joinToString { it.profileLabel }
        .ifBlank { "Не выбраны" }

private fun preferenceSummary(p: FoodPreferences): String =
    buildList {
            if (p.foodType != FoodType.ANY) add(p.foodType.profileLabel)
            if (p.excludedAllergens.isNotEmpty()) add("Аллергены: ${p.excludedAllergens.size}")
            if (p.glutenFree) add("Без глютена")
            if (p.lactoseFree) add("Без лактозы")
            if (p.diabetes) add("Диабет")
            if (p.dietTable.isNotBlank()) add(p.dietTable)
        }
        .joinToString(" · ")
        .ifBlank { "Предпочтения и предупреждения" }

@Composable
private fun ProfileRow(
    title: String,
    subtitle: String,
    icon: ImageVector,
    enabled: Boolean,
    onClick: () -> Unit,
) {
    Card(
        onClick,
        Modifier.fillMaxWidth(),
        enabled = enabled,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        shape = RoundedCornerShape(18.dp),
    ) {
        Row(
            Modifier.padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(title, style = MaterialTheme.typography.bodyMedium.copy(fontSize = 15.sp))
                Text(
                    subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Icon(icon, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun ProfileHeading(title: String, subtitle: String? = null) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(
            title,
            style =
                MaterialTheme.typography.headlineMedium.copy(fontSize = 30.sp, lineHeight = 36.sp),
            fontWeight = FontWeight.Bold,
        )
        if (subtitle != null)
            Text(
                subtitle,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
    }
}

@Composable
private fun ProfileNotice(title: String, body: String) {
    val dark = isSystemInDarkTheme()
    val container = if (dark) MaterialTheme.colorScheme.surfaceVariant else Color(0xFFFAEED7)
    val foreground = if (dark) MaterialTheme.colorScheme.onSurfaceVariant else Color(0xFF855A18)
    Surface(color = container, contentColor = foreground, shape = RoundedCornerShape(20.dp)) {
        Row(Modifier.padding(16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Icon(Icons.Outlined.Info, null, Modifier.size(20.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    title,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Bold,
                )
                Text(
                    body,
                    style =
                        MaterialTheme.typography.bodySmall.copy(
                            fontSize = 13.sp,
                            lineHeight = 19.sp,
                        ),
                )
            }
        }
    }
}
