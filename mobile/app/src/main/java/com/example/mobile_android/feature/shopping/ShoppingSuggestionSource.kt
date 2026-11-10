package com.example.mobile_android.feature.shopping

import com.example.mobile_android.domain.Catalog
import com.example.mobile_android.domain.PurchaseSuggestion

fun interface ShoppingSuggestionSource {
    fun suggestion(catalog: Catalog, budgetKopecks: Long): PurchaseSuggestion?
}

/** A fixed UI example; does not assess pantry contents or dietary preferences. */
class FakeShoppingSuggestionSource : ShoppingSuggestionSource {
    override fun suggestion(catalog: Catalog, budgetKopecks: Long): PurchaseSuggestion? {
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
