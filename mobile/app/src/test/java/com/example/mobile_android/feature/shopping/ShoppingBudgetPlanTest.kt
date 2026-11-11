package com.example.mobile_android.feature.shopping

import com.example.mobile_android.domain.Household
import com.example.mobile_android.domain.ManualPurchase
import com.example.mobile_android.domain.Quantity
import com.example.mobile_android.domain.QuantityUnit
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ShoppingBudgetPlanTest {
    @Test
    fun invalidPackageIdInSecondPositionRejectsTheWholeBatch() = runTest {
        val household = ShoppingUiHousehold().apply { values.value = Household() }
        val writer = ShoppingBudgetPlanFake(household)
        val (cheese, tomatoes) = twoPackageBudgetExample.packages.map { it.selection() }

        val result = runCatching {
            writer.add(listOf(cheese, tomatoes.copy(packageId = cheese.packageId)))
        }

        assertTrue(result.exceptionOrNull() is IllegalArgumentException)
        assertEquals(Household(), household.values.value)
    }

    @Test
    fun undoLeavesAnEditedPurchaseIntact() = runTest {
        val household = ShoppingUiHousehold().apply { values.value = Household() }
        val writer = ShoppingBudgetPlanFake(household)
        val (cheese, tomatoes) = twoPackageBudgetExample.packages.map { it.selection() }
        val addition = writer.add(listOf(cheese, tomatoes)) as BudgetPlanAddition.Added
        household.toggleCheckedPurchase(cheese.ingredientId)
        val edited = household.values.value

        assertEquals(BudgetPlanUndo.PurchasesChanged, writer.undo(addition.receipt))
        assertEquals(edited, household.values.value)
    }

    @Test
    fun undoPreservesUnrelatedPurchaseAndItsCheckedFlag() = runTest {
        val household = ShoppingUiHousehold().apply { values.value = Household() }
        val writer = ShoppingBudgetPlanFake(household)
        val packages = twoPackageBudgetExample.packages.map { it.selection() }
        val addition = writer.add(packages) as BudgetPlanAddition.Added
        val eggs = ManualPurchase("eggs", Quantity(10.0, QuantityUnit.PIECE))
        household.addManualPurchase(eggs.ingredientId, eggs.quantity)
        household.toggleCheckedPurchase(eggs.ingredientId)

        assertEquals(BudgetPlanUndo.Restored, writer.undo(addition.receipt))
        assertEquals(
            Household(manualPurchases = listOf(eggs), checkedPurchases = setOf(eggs.ingredientId)),
            household.values.value,
        )
    }

    @Test
    fun undoRestoresPreviousQuantityAndCheckedFlagAfterIncreasingPackageCount() = runTest {
        val household = ShoppingUiHousehold()
        val cheese = FakeShoppingBudgetSource.READY.packages.single().selection()
        household.toggleCheckedPurchase(cheese.ingredientId)
        val before = household.values.value
        val writer = ShoppingBudgetPlanFake(household)
        val addition = writer.add(listOf(cheese.copy(packageCount = 2))) as BudgetPlanAddition.Added

        assertEquals(
            Quantity(400.0, QuantityUnit.GRAM),
            household.values.value.manualPurchases.single().quantity,
        )
        assertTrue(household.values.value.checkedPurchases.isEmpty())
        assertEquals(BudgetPlanUndo.Restored, writer.undo(addition.receipt))
        assertEquals(before, household.values.value)
    }
}
