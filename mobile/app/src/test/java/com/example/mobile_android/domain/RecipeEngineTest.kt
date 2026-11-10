package com.example.mobile_android.domain

import com.example.mobile_android.data.DemoCatalog
import org.junit.Assert.*
import org.junit.Test

class RecipeEngineTest {
    private val catalog = DemoCatalog.catalog
    private val pantry = DemoCatalog.initialPantry
    private val preferences = FoodPreferences()
    private val cheese = catalog.recipe("cheese")!!

    private fun match(
        recipe: Recipe = cheese,
        items: List<PantryItem> = pantry,
        prefs: FoodPreferences = preferences,
        c: Catalog = catalog,
    ) = matchRecipe(recipe, items, c, prefs)

    @Test
    fun availableRecipeNeedsNoPurchase() {
        val result = match(catalog.recipe("omelette")!!)
        assertTrue(result.ready)
        assertEquals(0L, result.purchaseKopecks)
    }

    @Test
    fun missingCountsAreUniqueForZeroOneThreeAndFourIngredients() {
        val requirements =
            catalog.ingredients.take(4).map { RecipeIngredient(it.id, Quantity(1.0, it.unit)) }
        val recipe = cheese.copy(ingredients = requirements)
        for (count in listOf(0, 1, 3, 4)) {
            val available =
                requirements.drop(count).map { PantryItem(it.ingredientId, it.quantity) }
            val result = match(recipe, available)
            assertEquals(count, result.missing.size)
            assertEquals(count == 0, result.ready)
        }
    }

    @Test
    fun duplicateRecipeIdsAreAggregatedBeforeMatchingAndPricing() {
        val recipe =
            cheese.copy(
                ingredients =
                    listOf(
                        RecipeIngredient("hard-cheese", Quantity(10.0, QuantityUnit.GRAM)),
                        RecipeIngredient("hard-cheese", Quantity(20.0, QuantityUnit.GRAM)),
                    )
            )
        val result = match(recipe)
        assertEquals(1, result.missing.size)
        assertEquals(30.0, result.missing.single().quantity!!.value, 0.0)
        assertEquals(23000L, result.purchaseKopecks)
    }

    @Test
    fun duplicatePantryRowsDoNotCreateDuplicateShortages() {
        val result =
            match(
                items =
                    pantry +
                        listOf(
                            PantryItem("hard-cheese", Quantity(25.0, QuantityUnit.GRAM)),
                            PantryItem("hard-cheese", Quantity(55.0, QuantityUnit.GRAM)),
                        )
            )
        assertTrue(result.ready)
    }

    @Test
    fun priceIsForAWholePackageRatherThanConsumedGrams() {
        val result = match()
        assertEquals(80.0, result.missing.single().quantity!!.value, 0.0)
        assertEquals(23000L, result.purchaseKopecks)
    }

    @Test
    fun unknownQuantityCannotBeTreatedAsEnoughOrZero() {
        val result = match(items = pantry + PantryItem("hard-cheese", null))
        assertFalse(result.ready)
        assertNull(result.purchaseKopecks)
        assertEquals(setOf("hard-cheese"), result.uncertainQuantityIds)
    }

    @Test
    fun incompatibleUnitsAreNotConvertedImplicitly() {
        val result =
            match(
                items = pantry + PantryItem("hard-cheese", Quantity(200.0, QuantityUnit.MILLILITER))
            )
        assertFalse(result.ready)
        assertNull(result.purchaseKopecks)
    }

    @Test
    fun duplicateIngredientWithDifferentUnitsNeedsClarification() {
        val recipe =
            cheese.copy(
                ingredients =
                    listOf(
                        RecipeIngredient("hard-cheese", Quantity(10.0, QuantityUnit.GRAM)),
                        RecipeIngredient("hard-cheese", Quantity(10.0, QuantityUnit.PIECE)),
                    )
            )
        assertEquals(setOf("hard-cheese"), match(recipe).uncertainQuantityIds)
    }

    @Test
    fun unknownOfferHasNoPriceInsteadOfZero() {
        val recipe =
            cheese.copy(
                ingredients = listOf(RecipeIngredient("rice", Quantity(100.0, QuantityUnit.GRAM)))
            )
        assertNull(match(recipe).purchaseKopecks)
    }

    @Test
    fun unknownIngredientIsNotSilentlySkipped() {
        val recipe =
            cheese.copy(
                ingredients =
                    listOf(RecipeIngredient("unknown-id", Quantity(100.0, QuantityUnit.GRAM)))
            )
        val result = match(recipe)
        assertFalse(result.ready)
        assertNull(result.purchaseKopecks)
        assertTrue("unknown-id" in result.uncertainQuantityIds)
    }

    @Test
    fun portionsScaleIngredientsAndPreservePerServingNutrition() {
        val result =
            matchRecipe(
                cheese.copy(
                    ingredients =
                        listOf(RecipeIngredient("hard-cheese", Quantity(80.0, QuantityUnit.GRAM)))
                ),
                pantry,
                catalog,
                preferences,
                4,
            )
        assertEquals(160.0, result.missing.single().quantity!!.value, 0.0)
        assertEquals(549, result.recipe.nutritionPerServing!!.kcal)
    }

    @Test(expected = IllegalArgumentException::class)
    fun invalidPortionCountIsRejected() {
        matchRecipe(cheese, pantry, catalog, preferences, 0)
    }

    @Test
    fun declaredAllergenHidesTheRecipe() {
        assertEquals(
            Suitability.HIDDEN,
            match(prefs = preferences.copy(excludedAllergens = setOf(Allergen.MILK))).dietary.status,
        )
    }

    @Test
    fun incompleteAllergenDataDoesNotMeanSafe() {
        assertEquals(
            Suitability.UNKNOWN,
            match(
                    cheese.copy(allergens = emptySet(), allergenDataComplete = false),
                    prefs = preferences.copy(excludedAllergens = setOf(Allergen.MILK)),
                )
                .dietary
                .status,
        )
    }

    @Test
    fun unverifiedVegetarianCheeseIsNotRecommendedAsVegetarian() {
        assertEquals(
            Suitability.UNKNOWN,
            match(prefs = preferences.copy(foodType = FoodType.VEGETARIAN)).dietary.status,
        )
    }

    @Test
    fun medicalRulesAreUnknownUntilAgreed() {
        assertEquals(
            Suitability.UNKNOWN,
            match(prefs = preferences.copy(diabetes = true)).dietary.status,
        )
        assertEquals(
            Suitability.UNKNOWN,
            match(prefs = preferences.copy(dietTable = "9")).dietary.status,
        )
    }

    @Test
    fun sharedPantryIsSubtractedOnceAcrossPlannedRecipes() {
        val recipes =
            listOf(
                cheese.copy(
                    id = "one",
                    ingredients =
                        listOf(RecipeIngredient("tomatoes", Quantity(300.0, QuantityUnit.GRAM))),
                ),
                cheese.copy(
                    id = "two",
                    ingredients =
                        listOf(RecipeIngredient("tomatoes", Quantity(300.0, QuantityUnit.GRAM))),
                ),
            )
        val quote =
            shoppingQuote(
                catalog.copy(recipes = recipes),
                Household(
                    pantry = pantry,
                    plan = listOf(PlannedRecipe("one", 2), PlannedRecipe("two", 2)),
                ),
            )
        assertEquals(100.0, quote.lines.single().required!!.value, 0.0)
        assertEquals(500.0, quote.lines.single().buyQuantity!!.value, 0.0)
    }

    @Test
    fun manualPackageAndRecipeDemandDoNotDuplicatePurchase() {
        val quote =
            shoppingQuote(
                catalog,
                Household(
                    pantry = pantry,
                    plan = listOf(PlannedRecipe("cheese", 2)),
                    manualPurchases =
                        listOf(ManualPurchase("hard-cheese", Quantity(200.0, QuantityUnit.GRAM))),
                ),
            )
        assertEquals(23000L, quote.totalKopecks)
        assertEquals(200.0, quote.lines.single().buyQuantity!!.value, 0.0)
    }

    @Test
    fun checkedPurchaseDoesNotChangePantryUntilExplicitTransfer() {
        val household =
            Household(
                pantry = pantry,
                plan = listOf(PlannedRecipe("cheese", 2)),
                checkedPurchases = setOf("hard-cheese"),
            )
        assertTrue(shoppingQuote(catalog, household).lines.single().checked)
        assertEquals(pantry, household.pantry)
    }

    @Test
    fun unknownQuantityInShoppingPreventsKnownTotal() {
        val quote =
            shoppingQuote(
                catalog,
                Household(
                    pantry = pantry + PantryItem("hard-cheese", null),
                    plan = listOf(PlannedRecipe("cheese", 2)),
                ),
            )
        assertNull(quote.totalKopecks)
        assertNull(quote.lines.single().buyQuantity)
    }

    @Test
    fun oneCheesePackageUnlocksTwoAlternativeRecipesWithinBudget() {
        val suggestion =
            suggestSinglePurchase(catalog, Household(pantry = pantry), preferences, 50000)!!
        assertEquals("hard-cheese", suggestion.ingredient.id)
        assertEquals(setOf("cheese", "cheeseEgg"), suggestion.recipeIds)
        assertEquals(23000L, suggestion.priceKopecks)
    }

    @Test
    fun unavailableBudgetOrExcludedAllergensProduceNoSuggestion() {
        assertNull(suggestSinglePurchase(catalog, Household(pantry = pantry), preferences, 20000))
        assertNull(
            suggestSinglePurchase(
                catalog,
                Household(pantry = pantry),
                preferences.copy(excludedAllergens = setOf(Allergen.MILK)),
                50000,
            )
        )
    }

    @Test
    fun unknownAmountCannotUnlockARecipeInBudgetRecommendation() {
        assertNull(
            suggestSinglePurchase(
                catalog,
                Household(pantry = pantry + PantryItem("hard-cheese", null)),
                preferences,
                50000,
            )
        )
    }

    @Test
    fun overflowingPackagePriceBecomesUnknown() {
        assertNull(
            quotePackage(
                Quantity(2.0, QuantityUnit.PIECE),
                PackageOffer(Quantity(1.0, QuantityUnit.PIECE), Long.MAX_VALUE),
            )
        )
    }

    @Test
    fun overflowingBasketTotalBecomesUnknown() {
        val q = Quantity(1.0, QuantityUnit.PIECE)
        assertNull(
            ShoppingQuote(
                    listOf(
                        ShoppingLine("a", q, q, Long.MAX_VALUE, false),
                        ShoppingLine("b", q, q, 1, false),
                    )
                )
                .totalKopecks
        )
    }

    @Test(expected = IllegalArgumentException::class)
    fun nonFiniteQuantityIsRejected() {
        Quantity(Double.NaN, QuantityUnit.GRAM)
    }

    @Test(expected = IllegalArgumentException::class)
    fun negativeQuantityIsRejected() {
        Quantity(-1.0, QuantityUnit.GRAM)
    }
}
