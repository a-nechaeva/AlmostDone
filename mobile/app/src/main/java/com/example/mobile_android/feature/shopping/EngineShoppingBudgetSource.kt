package com.example.mobile_android.feature.shopping

import com.example.mobile_android.domain.Catalog
import com.example.mobile_android.domain.CatalogRepository
import com.example.mobile_android.domain.FoodPreferences
import com.example.mobile_android.domain.Household
import com.example.mobile_android.domain.HouseholdRepository
import com.example.mobile_android.domain.Ingredient
import com.example.mobile_android.domain.PantryItem
import com.example.mobile_android.domain.PreferencesRepository
import com.example.mobile_android.domain.Quantity
import com.example.mobile_android.domain.Suitability
import com.example.mobile_android.domain.defaultPackageId
import com.example.mobile_android.domain.matchRecipe
import com.example.mobile_android.domain.quotePackage
import kotlin.math.ceil
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext

/**
 * Покупки на бюджет по продуктам дома и каталогу.
 *
 * Жадно, как `best_purchases` серверного движка: на каждом шаге смотрим на все подходящие
 * блюда, которым чего-то не хватает (а не только на блюда с одним недостающим продуктом),
 * считаем для каждого набор упаковок «что докупить прямо сейчас» и берём вариант с лучшим
 * соотношением «новые блюда / рубли» в пределах остатка бюджета. Купленное «кладём» домой
 * и повторяем: ранее купленные упаковки учитываются, недостающее пересчитывается. Упаковки
 * берутся целыми, поэтому одна позиция может состоять из нескольких упаковок.
 */
class EngineShoppingBudgetSource(
    private val catalog: CatalogRepository,
    private val household: HouseholdRepository,
    private val preferences: PreferencesRepository,
) : ShoppingBudgetSource {
    override suspend fun example(budgetKopecks: Long): ShoppingBudgetExample? {
        val c = catalog.catalog.first()
        val h = household.household.first()
        val p = preferences.preferences.first()
        return withContext(Dispatchers.Default) { budgetPlan(c, h, p, budgetKopecks) }
    }
}

internal const val MAX_BUDGET_PACKAGES = 8

/** Одна позиция шага плана: упаковка продукта и сколько таких упаковок нужно. */
private data class BudgetStepItem(
    val ingredient: Ingredient,
    val packageQuantity: Quantity,
    val packageCount: Int,
    val priceKopecks: Long,
) {
    val purchasedQuantity: Quantity
        get() = Quantity(packageQuantity.value * packageCount, packageQuantity.unit)
}

private data class BudgetStep(
    val items: List<BudgetStepItem>,
    val costKopecks: Long,
    val unlockedRecipeIds: List<String>,
)

internal fun budgetPlan(
    catalog: Catalog,
    household: Household,
    preferences: FoodPreferences,
    budgetKopecks: Long,
): ShoppingBudgetExample? {
    var pantry = household.pantry
    var remaining = budgetKopecks
    val packages = mutableListOf<ShoppingBudgetPackage>()
    val unlocked = linkedSetOf<String>()
    while (packages.size < MAX_BUDGET_PACKAGES) {
        val step =
            bestBudgetStep(
                catalog,
                pantry,
                preferences,
                remaining,
                maxEntries = MAX_BUDGET_PACKAGES - packages.size,
            ) ?: break
        for (item in step.items) {
            packages +=
                ShoppingBudgetPackage(
                    item.ingredient.id,
                    item.ingredient.name,
                    item.packageQuantity,
                    item.priceKopecks,
                    packageId = defaultPackageId(item.ingredient.id),
                    packageCount = item.packageCount,
                )
            pantry = pantry + PantryItem(item.ingredient.id, item.purchasedQuantity)
        }
        unlocked += step.unlockedRecipeIds
        remaining -= step.costKopecks
    }
    if (packages.isEmpty()) return null
    return ShoppingBudgetExample(
        title = "Покупки, которые откроют новые блюда",
        packages = packages,
        alternativeRecipeIds = unlocked.toList(),
        totalKopecks = budgetKopecks - remaining,
        computed = true,
    )
}

/**
 * Лучший шаг плана: набор упаковок (по числу недостающих продуктов одного блюда), который
 * открывает больше всего новых блюд на рубль и укладывается в [remainingKopecks]. Продукты без
 * цены или с несовместимыми единицами пропускаем — гадать по цене нельзя.
 */
private fun bestBudgetStep(
    catalog: Catalog,
    pantry: List<PantryItem>,
    preferences: FoodPreferences,
    remainingKopecks: Long,
    maxEntries: Int,
): BudgetStep? {
    if (maxEntries <= 0) return null
    val locked =
        catalog.recipes
            .map { matchRecipe(it, pantry, catalog, preferences) }
            .filter {
                it.dietary.status == Suitability.ALLOWED &&
                    it.uncertainQuantityIds.isEmpty() &&
                    it.missing.isNotEmpty()
            }
    var best: BudgetStep? = null
    var bestRatio = 0.0
    for (match in locked) {
        if (match.missing.size > maxEntries) continue
        val items = mutableListOf<BudgetStepItem>()
        var cost = 0L
        var priced = true
        for (shortage in match.missing) {
            val ingredient = catalog.ingredient(shortage.ingredientId)
            val offer = ingredient?.offer
            val quote = quotePackage(shortage.quantity, offer)
            if (ingredient == null || offer == null || quote == null) {
                priced = false
                break
            }
            val count = ceil(shortage.quantity!!.value / offer.quantity.value).toInt()
            items += BudgetStepItem(ingredient, offer.quantity, count, quote.second)
            cost =
                try {
                    Math.addExact(cost, quote.second)
                } catch (overflow: ArithmeticException) {
                    priced = false
                    break
                }
        }
        if (!priced || cost > remainingKopecks) continue
        val bought = items.associate { it.ingredient.id to it.purchasedQuantity }
        val gained =
            locked.filter { other ->
                other.missing.all { s ->
                    val q = bought[s.ingredientId]
                    q != null && s.quantity != null && s.quantity.unit == q.unit &&
                        s.quantity.value <= q.value + 1e-9
                }
            }
        if (gained.isEmpty()) continue
        val ratio = if (cost > 0) gained.size.toDouble() / cost else Double.POSITIVE_INFINITY
        val current = best
        if (
            current == null ||
                ratio > bestRatio ||
                (ratio == bestRatio && gained.size > current.unlockedRecipeIds.size) ||
                (ratio == bestRatio &&
                    gained.size == current.unlockedRecipeIds.size &&
                    cost < current.costKopecks)
        ) {
            bestRatio = ratio
            best = BudgetStep(items, cost, gained.map { it.recipe.id })
        }
    }
    return best
}
