package com.example.mobile_android.feature.shopping

import com.example.mobile_android.domain.Catalog
import com.example.mobile_android.domain.CatalogRepository
import com.example.mobile_android.domain.FoodPreferences
import com.example.mobile_android.domain.Household
import com.example.mobile_android.domain.HouseholdRepository
import com.example.mobile_android.domain.PantryItem
import com.example.mobile_android.domain.PreferencesRepository
import com.example.mobile_android.domain.defaultPackageId
import com.example.mobile_android.domain.suggestSinglePurchase
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext

/**
 * Покупки на бюджет по продуктам дома и каталогу.
 *
 * Жадно: берём упаковку, которая открывает больше всего блюд и укладывается в остаток бюджета,
 * «кладём» её домой и повторяем. Это не оптимум, но каждая выбранная упаковка реально открывает
 * хотя бы одно новое блюдо (по расчёту локального движка).
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
        val next =
            suggestSinglePurchase(catalog, household.copy(pantry = pantry), preferences, remaining)
                ?: break
        if (next.recipeIds.all { it in unlocked }) break
        packages +=
            ShoppingBudgetPackage(
                next.ingredient.id,
                next.ingredient.name,
                next.quantity,
                next.priceKopecks,
                packageId = defaultPackageId(next.ingredient.id),
            )
        unlocked += next.recipeIds
        remaining -= next.priceKopecks
        pantry = pantry + PantryItem(next.ingredient.id, next.quantity)
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
