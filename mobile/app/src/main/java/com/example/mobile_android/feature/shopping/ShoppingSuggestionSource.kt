package com.example.mobile_android.feature.shopping

import com.example.mobile_android.domain.Catalog
import com.example.mobile_android.domain.FoodPreferences
import com.example.mobile_android.domain.Household
import com.example.mobile_android.domain.PurchaseSuggestion
import com.example.mobile_android.domain.suggestSinglePurchase

interface ShoppingSuggestionSource {
    fun suggestion(
        catalog: Catalog,
        budgetKopecks: Long,
        household: Household = Household(),
        preferences: FoodPreferences = FoodPreferences(),
    ): PurchaseSuggestion?
}

/** Одна упаковка в пределах бюджета, которая открывает больше всего блюд (локальный движок). */
class EngineShoppingSuggestionSource : ShoppingSuggestionSource {
    override fun suggestion(
        catalog: Catalog,
        budgetKopecks: Long,
        household: Household,
        preferences: FoodPreferences,
    ) = suggestSinglePurchase(catalog, household, preferences, budgetKopecks)
}

/** A fixed UI example; does not assess pantry contents or dietary preferences. */
class FakeShoppingSuggestionSource : ShoppingSuggestionSource {
    override fun suggestion(
        catalog: Catalog,
        budgetKopecks: Long,
        household: Household,
        preferences: FoodPreferences,
    ): PurchaseSuggestion? {
        val example = FakeShoppingBudgetSource.READY
        val pack = example.packages.single()
        val ingredient = catalog.ingredient(pack.ingredientId) ?: return null
        if (ingredient.offer == null) return null
        val price = pack.priceKopecks ?: return null
        if (price > budgetKopecks) return null
        val recipes = example.alternativeRecipeIds.filter { catalog.recipe(it) != null }.toSet()
        if (recipes.isEmpty()) return null
        return PurchaseSuggestion(ingredient, pack.quantity, price, recipes)
    }
}
