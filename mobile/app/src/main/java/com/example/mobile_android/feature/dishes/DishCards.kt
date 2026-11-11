package com.example.mobile_android.feature.dishes

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.example.mobile_android.domain.*
import com.example.mobile_android.ui.components.RecipePhoto
import com.example.mobile_android.ui.money

internal enum class DishGroup(val title: String) {
    READY("Можно сейчас"),
    BUY_ONE("Докупить 1 продукт"),
    BUY_TWO("Докупить 2 продукта"),
    BUY_THREE("Докупить 3 продукта"),
    ABOVE_LIMIT("Не хватает 4 продуктов или больше"),
    QUANTITY_UNKNOWN("Проверьте количество"),
    DIET_UNKNOWN("Сведения требуют проверки"),
}

internal fun dishGroup(match: RecipeMatch): DishGroup =
    when {
        // Неполные сведения об аллергенах важны, только когда аллергены исключены: тогда
        // движок уже вернул UNKNOWN (см. assess). Без исключений блюдо оценивается как обычно.
        match.dietary.status == Suitability.UNKNOWN -> DishGroup.DIET_UNKNOWN
        match.uncertainQuantityIds.isNotEmpty() -> DishGroup.QUANTITY_UNKNOWN
        else ->
            when (match.missing.size) {
                0 -> DishGroup.READY
                1 -> DishGroup.BUY_ONE
                2 -> DishGroup.BUY_TWO
                3 -> DishGroup.BUY_THREE
                else -> DishGroup.ABOVE_LIMIT
            }
    }

@Composable
internal fun LocalDishCard(
    match: RecipeMatch,
    ingredients: Map<String, String>,
    favorite: Boolean,
    open: () -> Unit,
    toggleFavorite: () -> Unit,
) {
    val recipe = match.recipe
    val hidden = match.dietary.status == Suitability.HIDDEN
    val group = dishGroup(match)
    val status =
        when {
            hidden -> "Не соответствует ограничениям"
            group == DishGroup.DIET_UNKNOWN -> "Сведения требуют проверки"
            group == DishGroup.QUANTITY_UNKNOWN -> "Проверьте количество продуктов"
            group == DishGroup.READY -> "Все продукты есть"
            group == DishGroup.ABOVE_LIMIT -> "Не хватает ${match.missing.size} продуктов"
            else -> {
                val name = match.missing.singleOrNull()?.let { ingredients[it.ingredientId] }
                val price = match.purchaseKopecks?.let { "≈${money(it)}" } ?: "нет оценки"
                if (name == null) "${group.title} · $price" else "Докупить: $name · $price"
            }
        }
    val statusColor =
        when {
            !hidden && group == DishGroup.READY -> MaterialTheme.colorScheme.tertiary
            hidden || group == DishGroup.QUANTITY_UNKNOWN || group == DishGroup.DIET_UNKNOWN ->
                MaterialTheme.colorScheme.onSurfaceVariant
            else -> MaterialTheme.colorScheme.primary
        }
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Card(
            onClick = open,
            modifier = Modifier.fillMaxWidth(),
            shape = MaterialTheme.shapes.medium,
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        ) {
            Row(
                Modifier.fillMaxWidth()
                    .padding(start = 12.dp, top = 12.dp, bottom = 12.dp, end = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                RecipePhoto(recipe.photo, Modifier.size(96.dp))
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        recipe.title,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                    )
                    val calories =
                        recipe.nutritionPerServing?.let { "${it.kcal} ккал / порц." }
                            ?: "КБЖУ неизвестно"
                    Text(
                        "${recipe.minutes} мин · $calories",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(status, style = MaterialTheme.typography.bodySmall, color = statusColor)
                }
                IconButton(toggleFavorite) {
                    Icon(
                        if (favorite) Icons.Default.Favorite else Icons.Default.FavoriteBorder,
                        if (favorite) "Убрать ${recipe.title} из избранного"
                        else "В избранное: ${recipe.title}",
                        tint = MaterialTheme.colorScheme.primary,
                    )
                }
            }
        }
        if (hidden || group == DishGroup.DIET_UNKNOWN) {
            dishWarnings(match).forEach { reason ->
                Text(
                    reason,
                    Modifier.padding(horizontal = 4.dp),
                    style = MaterialTheme.typography.bodySmall,
                    color = statusColor,
                )
            }
        }
    }
}

internal fun dishWarnings(match: RecipeMatch): List<String> =
    if (match.recipe.allergenDataComplete) match.dietary.reasons
    else (match.dietary.reasons + "Сведения об аллергенах неполные").distinct()

@Composable
internal fun HiddenExplanation(filters: DishFilters) {
    Surface(
        color = MaterialTheme.colorScheme.primaryContainer,
        contentColor = MaterialTheme.colorScheme.onPrimaryContainer,
        shape = MaterialTheme.shapes.medium,
    ) {
        Row(
            Modifier.fillMaxWidth().padding(16.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Icon(Icons.Outlined.Info, null, Modifier.size(20.dp))
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("Действуют ограничения питания", fontWeight = FontWeight.Bold)
                Text(
                    if (filters.excludedAllergens.isEmpty()) "Блюда скрыты по настройкам профиля."
                    else "Учитываются настройки профиля и временные исключения.",
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
        }
    }
}

internal fun countForm(count: Int, one: String, few: String, many: String): String =
    when {
        count % 100 in 11..14 -> many
        count % 10 == 1 -> one
        count % 10 in 2..4 -> few
        else -> many
    }
