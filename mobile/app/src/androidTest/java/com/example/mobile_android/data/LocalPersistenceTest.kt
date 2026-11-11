package com.example.mobile_android.data

import android.content.Context
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.room.Room
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.example.mobile_android.data.local.*
import com.example.mobile_android.domain.*
import java.io.File
import java.util.UUID
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.first
import org.junit.After
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class LocalPersistenceTest {
    private val context: Context = InstrumentationRegistry.getInstrumentation().targetContext
    private val databases = mutableListOf<HouseholdDatabase>()
    private val names = mutableListOf<String>()

    private fun database(name: String = "test-${UUID.randomUUID()}.db"): HouseholdDatabase {
        names += name
        return Room.databaseBuilder(context, HouseholdDatabase::class.java, name).build().also {
            databases += it
        }
    }

    private fun repository(db: HouseholdDatabase) =
        RoomHouseholdRepository(db, DemoCatalogRepository(), DemoCatalog.initialPantry)

    @After
    fun cleanup() {
        databases.forEach { it.close() }
        names.forEach { context.deleteDatabase(it) }
    }

    @Test
    fun householdSurvivesDatabaseReopenAndEmptyPantryIsNotReseeded() = runBlocking {
        val name = "test-${UUID.randomUUID()}.db"
        val db = database(name)
        val first = repository(db)
        first.household.first()
        first.setPantry("tomatoes", Quantity(700.0, QuantityUnit.GRAM))
        first.toggleFavorite("cheese", false)
        first.toggleFavorite("tomatoes", true)
        first.planRecipe("cheese", 2)
        first.toggleCheckedPurchase("hard-cheese")
        db.close()
        val second = repository(database(name))
        val data = second.household.first()
        assertEquals(
            700.0,
            data.pantry.first { it.ingredientId == "tomatoes" }.quantity!!.value,
            0.0,
        )
        assertTrue("cheese" in data.favoriteRecipes)
        assertTrue("tomatoes" in data.favoriteIngredients)
        assertEquals(listOf(PlannedRecipe("cheese", 2)), data.plan)
        assertTrue("hard-cheese" in data.checkedPurchases)
        data.pantry.forEach { second.removePantry(it.ingredientId) }
        assertTrue(second.household.first().pantry.isEmpty())
    }

    @Test
    fun checkingAndTransferringAreSeparateAndTransferAddsWholePackage() = runBlocking {
        val repo = repository(database())
        repo.household.first()
        repo.planRecipe("cheese", 2)
        repo.toggleCheckedPurchase("hard-cheese")
        assertFalse(repo.household.first().pantry.any { it.ingredientId == "hard-cheese" })
        repo.addCheckedPurchasesToPantry()
        val after = repo.household.first()
        assertEquals(
            200.0,
            after.pantry.first { it.ingredientId == "hard-cheese" }.quantity!!.value,
            0.0,
        )
        assertTrue(after.plan.isEmpty())
        assertTrue(after.checkedPurchases.isEmpty())
    }

    @Test
    fun invalidTransferRollsBackAllChanges() = runBlocking {
        val repo = repository(database())
        repo.household.first()
        repo.addManualPurchase("hard-cheese", Quantity(200.0, QuantityUnit.GRAM))
        repo.addManualPurchase("rice", Quantity(100.0, QuantityUnit.GRAM))
        repo.toggleCheckedPurchase("hard-cheese")
        repo.toggleCheckedPurchase("rice")
        val before = repo.household.first()
        try {
            repo.addCheckedPurchasesToPantry()
            fail("Unknown offer must prevent transfer")
        } catch (_: IllegalArgumentException) {}
        assertEquals(before, repo.household.first())
    }

    @Test
    fun concurrentAddsDoNotLoseAmountsOrDuplicateIngredientIds() = runBlocking {
        val repo = repository(database())
        repo.household.first()
        coroutineScope {
            repeat(20) { launch { repo.addPantry("tomatoes", Quantity(10.0, QuantityUnit.GRAM)) } }
        }
        val rows = repo.household.first().pantry.filter { it.ingredientId == "tomatoes" }
        assertEquals(1, rows.size)
        assertEquals(700.0, rows.single().quantity!!.value, 0.0)
    }

    @Test
    fun unknownAndIncompatibleQuantitiesArePreservedOrRejected() = runBlocking {
        val repo = repository(database())
        repo.household.first()
        repo.setPantry("tomatoes", null)
        repo.addPantry("tomatoes", Quantity(100.0, QuantityUnit.GRAM))
        assertNull(repo.household.first().pantry.first { it.ingredientId == "tomatoes" }.quantity)
        repo.setPantry("tomatoes", Quantity(100.0, QuantityUnit.GRAM))
        try {
            repo.addPantry("tomatoes", Quantity(100.0, QuantityUnit.MILLILITER))
            fail("Units must not be converted")
        } catch (_: IllegalArgumentException) {}
        assertEquals(
            Quantity(100.0, QuantityUnit.GRAM),
            repo.household.first().pantry.first { it.ingredientId == "tomatoes" }.quantity,
        )
    }

    @Test
    fun changingPlanPreservesOnlyStillValidPurchaseMarks() = runBlocking {
        val repo = repository(database())
        repo.household.first()
        repo.planRecipe("cheese", 2)
        repo.toggleCheckedPurchase("hard-cheese")
        repo.planRecipe("cheeseEgg", 1)
        assertTrue("hard-cheese" in repo.household.first().checkedPurchases)
        repo.planRecipe("cheese", 12)
        assertFalse("hard-cheese" in repo.household.first().checkedPurchases)
    }

    @Test
    fun aWriteBeforeObservationCannotBeOverwrittenByDemoSeeding() = runBlocking {
        val repo = repository(database())
        repo.setPantry("tomatoes", Quantity(700.0, QuantityUnit.GRAM))
        assertEquals(
            700.0,
            repo.household.first().pantry.first { it.ingredientId == "tomatoes" }.quantity!!.value,
            0.0,
        )
    }

    @Test
    fun foodPreferencesAreAtomicAndPersistAcrossReopen() = runBlocking {
        val file = File(context.cacheDir, "test-${UUID.randomUUID()}.preferences_pb")
        val firstScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        val secondScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        try {
            val store =
                PreferenceDataStoreFactory.create(scope = firstScope, produceFile = { file })
            val prefs = LocalPreferences(store)
            coroutineScope {
                launch { prefs.update { it.copy(glutenFree = true) } }
                launch { prefs.update { it.copy(lactoseFree = true) } }
            }
            assertTrue(prefs.preferences.first().glutenFree)
            assertTrue(prefs.preferences.first().lactoseFree)
            firstScope.coroutineContext.job.cancelAndJoin()
            val restored =
                LocalPreferences(
                    PreferenceDataStoreFactory.create(scope = secondScope, produceFile = { file })
                )
            assertTrue(restored.preferences.first().glutenFree)
            assertTrue(restored.preferences.first().lactoseFree)
        } finally {
            firstScope.coroutineContext.job.cancelAndJoin()
            secondScope.coroutineContext.job.cancelAndJoin()
            file.delete()
        }
    }
}
