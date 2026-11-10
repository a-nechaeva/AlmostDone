package com.example.mobile_android.feature.recipe

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.viewModelScope
import com.example.mobile_android.data.DemoCatalog
import com.example.mobile_android.domain.*
import com.example.mobile_android.feature.common.ScreenState
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.test.*
import org.junit.Assert.*
import org.junit.After
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class RecipeUiViewModelTest {
    private val dispatcher = StandardTestDispatcher()
    private val models = mutableListOf<RecipeViewModel>()
    @Before fun setup() { Dispatchers.setMain(dispatcher) }
    @After fun close() { models.forEach { it.viewModelScope.cancel() }; Dispatchers.resetMain() }

    private fun TestScope.model(
        household: RecipeUiHousehold = RecipeUiHousehold(),
        preferences: RecipeUiPreferences = RecipeUiPreferences(),
        saved: SavedStateHandle = SavedStateHandle(mapOf("recipeId" to "cheese")),
        source: Flow<Catalog> = flowOf(DemoCatalog.catalog),
    ): RecipeViewModel {
        val vm = RecipeViewModel(object : CatalogRepository { override val catalog = source }, household, preferences, saved)
        models += vm
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { vm.state.collect() }
        return vm
    }
    private fun ready(vm: RecipeViewModel) = (vm.state.value as ScreenState.Ready).data

    @Test fun sameRecipeUpdatesFromMissingToReadyToUnknown() = runTest(dispatcher) {
        val h = RecipeUiHousehold()
        val vm = model(h)
        assertEquals(ScreenState.Loading, vm.state.value)
        runCurrent()
        assertEquals(listOf("hard-cheese"), ready(vm).match!!.missing.map { it.ingredientId })
        assertEquals(23000L, ready(vm).match!!.purchaseKopecks)
        h.setPantry("hard-cheese", Quantity(200.0, QuantityUnit.GRAM)); runCurrent()
        assertTrue(ready(vm).match!!.ready)
        h.setPantry("hard-cheese", null); runCurrent()
        assertEquals(setOf("hard-cheese"), ready(vm).match!!.uncertainQuantityIds)
        assertNull(ready(vm).match!!.purchaseKopecks)
        assertFalse(ready(vm).canAddToShopping)
        vm.addToShopping(); runCurrent()
        assertEquals(0, h.shoppingCalls)
    }

    @Test fun retryResubscribesAndMissingRecipeCannotBeWritten() = runTest(dispatcher) {
        val h = RecipeUiHousehold().apply { failRead = true }
        val vm = model(h)
        runCurrent(); assertTrue(vm.state.value is ScreenState.Error)
        h.failRead = false; vm.retry(); runCurrent()
        assertNotNull(ready(vm).match)
        val missing = model(h, saved = SavedStateHandle(mapOf("recipeId" to "absent")))
        runCurrent(); assertNull(ready(missing).match)
        missing.favorite(); missing.addToShopping(); runCurrent()
        assertEquals(0, h.favoriteCalls); assertEquals(0, h.shoppingCalls)
    }

    @Test fun favoriteAndPurchaseUseRepositoryOnceWhilePendingAndCanRetry() = runTest(dispatcher) {
        val h = RecipeUiHousehold().apply { gate = CompletableDeferred() }
        val vm = model(h); runCurrent()
        vm.favorite(); vm.favorite(); vm.addToShopping(); runCurrent()
        assertTrue(vm.actions.state.value.pending)
        assertEquals(1, h.favoriteCalls); assertEquals(0, h.shoppingCalls)
        h.gate!!.complete(Unit); runCurrent()
        assertTrue(ready(vm).favorite)
        h.failWrite = true; vm.addToShopping(); runCurrent()
        assertTrue(vm.actions.state.value.failed); assertFalse(ready(vm).planned)
        h.failWrite = false; h.gate = CompletableDeferred()
        vm.addToShopping(); vm.addToShopping(); runCurrent()
        assertEquals(2, h.shoppingCalls)
        h.gate!!.complete(Unit); runCurrent()
        assertTrue(ready(vm).planned)
        assertEquals(listOf(PlannedRecipe("cheese", 2)), h.values.value.plan)
        assertFalse(vm.actions.state.value.failed)
    }

    @Test fun portionsRestoreAndUpdateRequirementsWithoutChangingPerServingNutrition() = runTest(dispatcher) {
        val saved = SavedStateHandle(mapOf("recipeId" to "cheese"))
        val vm = model(saved = saved); runCurrent()
        vm.servingsChanged(4); runCurrent()
        assertEquals(160.0, ready(vm).requirements.first { it.ingredientId == "hard-cheese" }.quantity!!.value, 0.0)
        assertEquals(549, ready(vm).match!!.recipe.nutritionPerServing!!.kcal)
        val restored = model(saved = SavedStateHandle(saved.keys().associateWith { saved.get<Any?>(it) }))
        runCurrent(); assertEquals(4, ready(restored).match!!.servings)
        restored.servingsChanged(20); runCurrent(); assertEquals(12, ready(restored).match!!.servings)
    }

    @Test fun unknownEstimatesStayUnknownAndDietaryWarningBlocksPurchase() = runTest(dispatcher) {
        val unknown = DemoCatalog.catalog.copy(
            ingredients = DemoCatalog.catalog.ingredients.map { it.copy(offer = null) },
            recipes = DemoCatalog.catalog.recipes.map { it.copy(nutritionPerServing = null, allergenDataComplete = false) },
        )
        val h = RecipeUiHousehold()
        val p = RecipeUiPreferences()
        val vm = model(h, p, source = flowOf(unknown)); runCurrent()
        assertNull(ready(vm).match!!.purchaseKopecks)
        assertNull(ready(vm).match!!.recipe.nutritionPerServing)
        assertFalse(ready(vm).match!!.recipe.allergenDataComplete)
        p.update { it.copy(excludedAllergens = setOf(Allergen.MILK)) }; runCurrent()
        vm.addToShopping(); runCurrent()
        assertEquals(Suitability.HIDDEN, ready(vm).match!!.dietary.status)
        assertEquals(0, h.shoppingCalls)
    }

    @Test fun cancellationReleasesPendingWithoutSuccessOrFailure() = runTest(dispatcher) {
        val h = RecipeUiHousehold().apply { gate = CompletableDeferred() }
        val vm = model(h); runCurrent(); vm.favorite(); runCurrent()
        vm.viewModelScope.cancel(); runCurrent()
        assertFalse(vm.actions.state.value.pending)
        assertFalse(vm.actions.state.value.failed)
        assertFalse(h.values.value.favoriteRecipes.contains("cheese"))
    }
}
