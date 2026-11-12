package com.example.mobile_android.feature.shopping

import com.example.mobile_android.data.DemoCatalog
import com.example.mobile_android.domain.Catalog
import com.example.mobile_android.domain.DietaryFacts
import com.example.mobile_android.domain.FoodPreferences
import com.example.mobile_android.domain.Household
import com.example.mobile_android.domain.Nutrition
import com.example.mobile_android.domain.Quantity
import com.example.mobile_android.domain.QuantityUnit
import com.example.mobile_android.domain.Recipe
import com.example.mobile_android.domain.RecipeIngredient
import org.junit.Assert.*
import org.junit.Test

class EngineShoppingBudgetSourceTest {
    private val catalog = DemoCatalog.catalog
    private val pantry = DemoCatalog.initialPantry

    @Test
    fun cheeseUnlocksTwoDishesWithinBudget() {
        val plan = budgetPlan(catalog, Household(pantry = pantry), FoodPreferences(), 50000)!!
        assertTrue(plan.computed)
        assertEquals(listOf("hard-cheese"), plan.packages.map { it.ingredientId })
        assertEquals("hard-cheese-default", plan.packages.single().packageId)
        assertEquals(Quantity(200.0, QuantityUnit.GRAM), plan.packages.single().quantity)
        assertEquals(setOf("cheese", "cheeseEgg"), plan.alternativeRecipeIds.toSet())
        assertEquals(23000L, plan.totalKopecks)
    }

    @Test
    fun buysSeveralPackagesWhileBudgetLasts() {
        val noTomatoes = pantry.filter { it.ingredientId != "tomatoes" }
        val plan = budgetPlan(catalog, Household(pantry = noTomatoes), FoodPreferences(), 50000)!!
        assertEquals(listOf("tomatoes", "hard-cheese"), plan.packages.map { it.ingredientId })
        assertEquals(setOf("omelette", "pasta", "cheese", "cheeseEgg"), plan.alternativeRecipeIds.toSet())
        assertEquals(16000L + 23000L, plan.totalKopecks)

        val onlyTomatoes = budgetPlan(catalog, Household(pantry = noTomatoes), FoodPreferences(), 20000)!!
        assertEquals(listOf("tomatoes"), onlyTomatoes.packages.map { it.ingredientId })
    }

    @Test
    fun nothingFitsTheBudget() {
        assertNull(budgetPlan(catalog, Household(pantry = pantry), FoodPreferences(), 10000))
    }

    @Test
    fun plansFromEmptyPantryWhenDishesNeedSeveralProducts() {
        // Раньше план собирался только из блюд с одним недостающим продуктом, поэтому
        // с пустыми запасами подбор отвечал «нечего покупать» при любом бюджете.
        val plan = budgetPlan(catalog, Household(), FoodPreferences(), 100000)!!
        assertTrue(plan.computed)
        assertEquals(
            listOf("eggs", "tomatoes", "milk", "butter", "hard-cheese"),
            plan.packages.map { it.ingredientId },
        )
        assertEquals(setOf("omelette", "cheeseEgg"), plan.alternativeRecipeIds.toSet())
        assertEquals(85000L, plan.totalKopecks)
    }

    @Test
    fun emptyPantryPlanRespectsTheBudget() {
        val plan = budgetPlan(catalog, Household(), FoodPreferences(), 65000)!!
        assertEquals(
            listOf("eggs", "tomatoes", "milk", "butter"),
            plan.packages.map { it.ingredientId },
        )
        assertEquals(setOf("omelette"), plan.alternativeRecipeIds.toSet())
        assertEquals(62000L, plan.totalKopecks)
        assertTrue(plan.totalKopecks!! <= 65000)
    }

    @Test
    fun buysSeveralPackagesOfOneProductWhenShortageExceedsPack() {
        val salad =
            Recipe(
                "big-salad",
                "Большой салат",
                listOf(RecipeIngredient("tomatoes", Quantity(600.0, QuantityUnit.GRAM))),
                listOf("Нарежьте томаты."),
                5,
                2,
                Nutrition(60, 3, 0, 12),
                emptySet(),
                true,
                DietaryFacts(true, true, true, true),
                emptySet(),
                "",
            )
        val plan =
            budgetPlan(
                Catalog(catalog.ingredients, listOf(salad)),
                Household(),
                FoodPreferences(),
                50000,
            )!!
        val pack = plan.packages.single()
        assertEquals("tomatoes", pack.ingredientId)
        assertEquals(2, pack.packageCount)
        assertEquals(Quantity(500.0, QuantityUnit.GRAM), pack.quantity)
        assertEquals(32000L, pack.priceKopecks)
        assertEquals(listOf("big-salad"), plan.alternativeRecipeIds)
        assertEquals(32000L, plan.totalKopecks)
    }
}
