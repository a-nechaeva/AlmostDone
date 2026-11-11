package com.example.mobile_android.feature.receipt

import android.app.Application
import androidx.room.Room
import com.example.mobile_android.data.DemoCatalogRepository
import com.example.mobile_android.data.local.HouseholdDatabase
import com.example.mobile_android.data.local.RoomHouseholdRepository
import com.example.mobile_android.domain.PantryItem
import com.example.mobile_android.domain.Quantity
import com.example.mobile_android.domain.QuantityUnit
import com.example.mobile_android.feature.shopping.BudgetPlanAddition
import com.example.mobile_android.feature.shopping.BudgetPlanUndo
import com.example.mobile_android.feature.shopping.ShoppingPackageSelection
import com.example.mobile_android.ui.UiSmoke
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.junit.experimental.categories.Category
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], application = Application::class)
@Category(UiSmoke::class)
class ReceiptRoomTest {
    @Test
    fun receiptRollsBackFirstLineIfAnotherLineOverflowsExistingStock() = runBlocking {
        withRepository { repo ->
            repo.setPantry("hard-cheese", grams(999_999.0))
            val before = repo.household.first()
            try {
                repo.add(linkedMapOf("tomatoes" to grams(50.0), "hard-cheese" to grams(2.0)))
                fail("Expected quantity overflow")
            } catch (_: IllegalArgumentException) {
                assertEquals(before, repo.household.first())
            }
            repo.add(mapOf("tomatoes" to grams(50.0), "hard-cheese" to grams(1.0)))
            assertEquals(
                setOf(PantryItem("tomatoes", grams(50.0)), PantryItem("hard-cheese", grams(1_000_000.0))),
                repo.household.first().pantry.toSet(),
            )
        }
    }

    @Test
    fun receiptCannotDiscardTheImportedAmountOfAnUnknownStock() = runBlocking {
        withRepository { repo ->
            repo.setPantry("hard-cheese", null)
            val before = repo.household.first()
            try {
                repo.add(mapOf("tomatoes" to grams(50.0), "hard-cheese" to grams(200.0)))
                fail("Expected unknown stock to prevent the import")
            } catch (unknown: UnknownReceiptPantryQuantity) {
                assertEquals("hard-cheese", unknown.ingredientId)
                assertEquals(before, repo.household.first())
            }
        }
    }

    @Test
    fun laterManualWriteOfTheSameAmountSupersedesBudgetUndo() = runBlocking {
        withRepository { repo ->
            val quantity = grams(200.0)
            val packageSelection = ShoppingPackageSelection("hard-cheese", "hard-cheese-200g", quantity, 1)
            val added = repo.add(listOf(packageSelection)) as BudgetPlanAddition.Added
            repo.addManualPurchase("hard-cheese", quantity)
            assertEquals(BudgetPlanUndo.PurchasesChanged, repo.undo(added.receipt))
            assertEquals(quantity, repo.household.first().manualPurchases.single().quantity)
        }
    }

    @Test
    fun budgetValidatesAndWritesBothPackagesInOneBatch() = runBlocking {
        withRepository { repo ->
            val cheese = ShoppingPackageSelection("hard-cheese", "hard-cheese-200g", grams(200.0), 1)
            val tomatoes = ShoppingPackageSelection("tomatoes", "tomatoes-500g", grams(500.0), 1)
            try {
                repo.add(listOf(cheese, tomatoes.copy(packageId = "unknown")))
                fail("Expected an invalid package ID")
            } catch (_: IllegalArgumentException) {
                assertTrue(repo.household.first().manualPurchases.isEmpty())
            }
            val added = repo.add(listOf(cheese, tomatoes)) as BudgetPlanAddition.Added
            assertEquals(setOf("hard-cheese", "tomatoes"), repo.household.first().manualPurchases.map {
                it.ingredientId
            }.toSet())
            assertEquals(BudgetPlanUndo.Restored, repo.undo(added.receipt))
            assertTrue(repo.household.first().manualPurchases.isEmpty())
        }
    }

    @Test
    fun budgetUndoPreservesOtherPurchasesAndRejectsAChangedThenRestoredCheck() = runBlocking {
        withRepository { repo ->
            val packageSelection = ShoppingPackageSelection("hard-cheese", "hard-cheese-200g", grams(200.0), 2)
            val first = repo.add(listOf(packageSelection)) as BudgetPlanAddition.Added
            assertEquals(BudgetPlanAddition.AlreadyInList, repo.add(listOf(packageSelection)))
            repo.addManualPurchase("tomatoes", grams(50.0))
            assertEquals(BudgetPlanUndo.Restored, repo.undo(first.receipt))
            assertEquals(listOf("tomatoes"), repo.household.first().manualPurchases.map { it.ingredientId })

            val second = repo.add(listOf(packageSelection)) as BudgetPlanAddition.Added
            repo.toggleCheckedPurchase("hard-cheese")
            repo.toggleCheckedPurchase("hard-cheese")
            assertEquals(BudgetPlanUndo.PurchasesChanged, repo.undo(second.receipt))
            assertEquals(grams(400.0), repo.household.first().manualPurchases.find {
                it.ingredientId == "hard-cheese"
            }?.quantity)
        }
    }

    @Test
    fun budgetAcceptsDefaultPackageOfAnyIngredientWithOffer() = runBlocking {
        withRepository { repo ->
            val milk = ShoppingPackageSelection("milk", "milk-default", Quantity(1000.0, QuantityUnit.MILLILITER), 1)
            repo.add(listOf(milk)) as BudgetPlanAddition.Added
            assertEquals(listOf("milk"), repo.household.first().manualPurchases.map { it.ingredientId })
            try {
                repo.add(listOf(ShoppingPackageSelection("rice", "rice-default", grams(1000.0), 1)))
                fail("rice has no offer")
            } catch (_: IllegalArgumentException) {}
        }
    }

    private suspend fun withRepository(block: suspend (RoomHouseholdRepository) -> Unit) {
        val database = Room.inMemoryDatabaseBuilder(
            RuntimeEnvironment.getApplication(),
            HouseholdDatabase::class.java,
        ).build()
        try {
            block(RoomHouseholdRepository(database, DemoCatalogRepository(), emptyList()))
        } finally {
            database.close()
        }
    }

    private fun grams(value: Double) = Quantity(value, QuantityUnit.GRAM)
}
