package com.example.mobile_android.feature.shopping

import com.example.mobile_android.data.DemoCatalog
import com.example.mobile_android.domain.FoodPreferences
import com.example.mobile_android.domain.Household
import com.example.mobile_android.domain.Quantity
import com.example.mobile_android.domain.QuantityUnit
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
}
