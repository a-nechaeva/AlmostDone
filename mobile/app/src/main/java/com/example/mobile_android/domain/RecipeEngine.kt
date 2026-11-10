package com.example.mobile_android.domain

private fun assess(recipe: Recipe, preferences: FoodPreferences): DietaryAssessment {
    val violations = mutableListOf<String>()
    val unknown = mutableListOf<String>()
    val excluded = recipe.allergens.intersect(preferences.excludedAllergens)
    if (excluded.isNotEmpty()) violations += "Содержит: ${excluded.joinToString { it.label }}"
    if (preferences.excludedAllergens.isNotEmpty() && !recipe.allergenDataComplete)
        unknown += "Сведения об аллергенах неполные"
    fun check(enabled: Boolean, fact: Boolean?, label: String) {
        if (enabled)
            when (fact) {
                false -> violations += label
                null -> unknown += "Неизвестно: $label"
                true -> Unit
            }
    }
    check(
        preferences.foodType == FoodType.VEGETARIAN,
        recipe.dietaryFacts.vegetarian,
        "Вегетарианское питание",
    )
    check(preferences.foodType == FoodType.VEGAN, recipe.dietaryFacts.vegan, "Веганское питание")
    check(preferences.glutenFree, recipe.dietaryFacts.glutenFree, "Без глютена")
    check(preferences.lactoseFree, recipe.dietaryFacts.lactoseFree, "Без лактозы")
    if (preferences.diabetes || preferences.dietTable.isNotBlank())
        unknown += "Правила для диабета и диетического стола ещё не согласованы"
    return when {
        violations.isNotEmpty() -> DietaryAssessment(Suitability.HIDDEN, violations + unknown)
        unknown.isNotEmpty() -> DietaryAssessment(Suitability.UNKNOWN, unknown.distinct())
        else -> DietaryAssessment(Suitability.ALLOWED, emptyList())
    }
}

fun recipeRequirements(recipe: Recipe, servings: Int): List<Shortage> {
    require(servings in 1..12)
    return recipe.ingredients
        .groupBy { it.ingredientId }
        .map { (id, items) ->
            val units = items.map { it.quantity.unit }.distinct()
            val amount = items.sumOf { it.quantity.value } * servings / recipe.servings
            Shortage(
                id,
                if (units.size == 1 && amount <= 1_000_000) Quantity(amount, units.single())
                else null,
            )
        }
}

fun matchRecipe(
    recipe: Recipe,
    pantry: List<PantryItem>,
    catalog: Catalog,
    preferences: FoodPreferences,
    servings: Int = recipe.servings,
): RecipeMatch {
    val missing = mutableListOf<Shortage>()
    val uncertain = mutableSetOf<String>()
    for (need in recipeRequirements(recipe, servings)) {
        val entries = pantry.filter { it.ingredientId == need.ingredientId }
        if (need.quantity == null || catalog.ingredient(need.ingredientId) == null) {
            uncertain += need.ingredientId
        } else if (entries.isEmpty()) {
            missing += need
        } else if (entries.any { it.quantity == null || it.quantity.unit != need.quantity.unit }) {
            uncertain += need.ingredientId
        } else {
            val available = entries.sumOf { it.quantity!!.value }
            val difference = need.quantity.value - available
            if (difference > 0.000001)
                missing += Shortage(need.ingredientId, Quantity(difference, need.quantity.unit))
        }
    }
    val prices =
        missing.map {
            quotePackage(it.quantity, catalog.ingredient(it.ingredientId)?.offer)?.second
        }
    val cost = if (uncertain.isNotEmpty()) null else sumMoney(prices)
    return RecipeMatch(recipe, servings, missing, uncertain, cost, assess(recipe, preferences))
}

fun shoppingQuote(catalog: Catalog, household: Household): ShoppingQuote {
    val needs =
        household.plan
            .flatMap { plan ->
                val recipe = catalog.recipe(plan.recipeId)
                if (recipe == null) listOf(Shortage(plan.recipeId, null))
                else recipeRequirements(recipe, plan.servings)
            }
            .groupBy { it.ingredientId }
            .map { (id, values) ->
                val q = values.mapNotNull { it.quantity }
                val sum = q.sumOf { it.value }
                Shortage(
                    id,
                    if (
                        q.size == values.size &&
                            q.map { it.unit }.distinct().size == 1 &&
                            sum <= 1_000_000
                    )
                        Quantity(sum, q.first().unit)
                    else null,
                )
            }
    val shortages =
        needs.mapNotNull { need ->
            val existing = household.pantry.filter { it.ingredientId == need.ingredientId }
            when {
                need.quantity == null -> need
                existing.any { it.quantity == null || it.quantity.unit != need.quantity.unit } ->
                    Shortage(need.ingredientId, null)
                else -> {
                    val left = need.quantity.value - existing.sumOf { it.quantity!!.value }
                    if (left > 0.000001)
                        Shortage(need.ingredientId, Quantity(left, need.quantity.unit))
                    else null
                }
            }
        }
    // A manual package is a minimum shopping quantity, not an additional copy of a recipe shortage.
    val combined =
        (shortages + household.manualPurchases.map { Shortage(it.ingredientId, it.quantity) })
            .groupBy { it.ingredientId }
    val lines =
        combined.map { (id, entries) ->
            val quantities = entries.mapNotNull { it.quantity }
            val required =
                if (
                    quantities.size == entries.size &&
                        quantities.map { it.unit }.distinct().size == 1
                )
                    quantities.maxByOrNull { it.value }
                else null
            val quote = quotePackage(required, catalog.ingredient(id)?.offer)
            ShoppingLine(
                id,
                required,
                quote?.first,
                quote?.second,
                id in household.checkedPurchases,
            )
        }
    return ShoppingQuote(
        lines.sortedBy { catalog.ingredient(it.ingredientId)?.name ?: it.ingredientId }
    )
}

fun suggestSinglePurchase(
    catalog: Catalog,
    household: Household,
    preferences: FoodPreferences,
    budgetKopecks: Long,
): PurchaseSuggestion? {
    require(budgetKopecks >= 0)
    val matches =
        catalog.recipes
            .map { matchRecipe(it, household.pantry, catalog, preferences) }
            .filter {
                it.dietary.status == Suitability.ALLOWED &&
                    it.uncertainQuantityIds.isEmpty() &&
                    it.missing.size == 1
            }
    return matches
        .groupBy { it.missing.single().ingredientId }
        .mapNotNull { (id, options) ->
            val ingredient = catalog.ingredient(id) ?: return@mapNotNull null
            val offer = ingredient.offer ?: return@mapNotNull null
            if (offer.priceKopecks > budgetKopecks) return@mapNotNull null
            val unlocked =
                options
                    .filter {
                        it.missing.single().quantity?.let { q ->
                            q.unit == offer.quantity.unit && q.value <= offer.quantity.value
                        } == true
                    }
                    .map { it.recipe.id }
                    .toSet()
            if (unlocked.isEmpty()) null
            else PurchaseSuggestion(ingredient, offer.quantity, offer.priceKopecks, unlocked)
        }
        .sortedWith(
            compareByDescending<PurchaseSuggestion> { it.recipeIds.size }
                .thenBy { it.priceKopecks }
                .thenBy { it.ingredient.id }
        )
        .firstOrNull()
}
