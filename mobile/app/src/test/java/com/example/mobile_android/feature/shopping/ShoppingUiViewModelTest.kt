package com.example.mobile_android.feature.shopping

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.viewModelScope
import com.example.mobile_android.data.DemoCatalogRepository
import com.example.mobile_android.feature.MainDispatcherRule
import com.example.mobile_android.feature.common.ScreenState
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.test.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class ShoppingUiViewModelTest {
    @get:Rule val main = MainDispatcherRule()
    private val models = mutableListOf<ShoppingViewModel>()

    private fun TestScope.model(repo: ShoppingUiHousehold): ShoppingViewModel =
        ShoppingViewModel(
                DemoCatalogRepository(),
                repo,
                ShoppingUiPreferences(),
                SavedStateHandle(),
            )
            .also {
                models += it
                backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
                    it.state.collect()
                }
            }

    @After
    fun close() {
        models.forEach { it.viewModelScope.cancel() }
    }

    private fun data(vm: ShoppingViewModel) = (vm.state.value as ScreenState.Ready).data

    @Test
    fun checkAndUncheckNeverChangePantryOrCheckout() = runTest {
        val repo = ShoppingUiHousehold()
        val vm = model(repo)
        runCurrent()
        val pantry = repo.values.value.pantry
        vm.toggleChecked("hard-cheese")
        runCurrent()
        assertTrue(data(vm).quote.lines.single().checked)
        vm.toggleChecked("hard-cheese")
        runCurrent()
        assertFalse(data(vm).quote.lines.single().checked)
        assertEquals(pantry, repo.values.value.pantry)
        assertEquals(0, repo.checkoutCalls)
    }

    @Test
    fun pendingWriteBlocksADoubleToggleAndCompletesFromRepositoryFlow() = runTest {
        val gate = CompletableDeferred<Unit>()
        val repo = ShoppingUiHousehold().apply { writeGate = gate }
        val vm = model(repo)
        runCurrent()
        vm.toggleChecked("hard-cheese")
        runCurrent()
        assertTrue(vm.actions.state.value.pending)
        assertFalse(data(vm).quote.lines.single().checked)
        vm.toggleChecked("hard-cheese")
        runCurrent()
        assertEquals(1, repo.toggleCalls)
        gate.complete(Unit)
        runCurrent()
        assertFalse(vm.actions.state.value.pending)
        assertTrue(data(vm).quote.lines.single().checked)
    }

    @Test
    fun failedWritePreservesListAndCanBeRetried() = runTest {
        val repo = ShoppingUiHousehold().apply { failWrite = true }
        val vm = model(repo)
        runCurrent()
        vm.toggleChecked("hard-cheese")
        runCurrent()
        assertTrue(vm.actions.state.value.failed)
        assertFalse(data(vm).quote.lines.single().checked)
        repo.failWrite = false
        vm.toggleChecked("hard-cheese")
        runCurrent()
        assertFalse(vm.actions.state.value.failed)
        assertTrue(data(vm).quote.lines.single().checked)
    }

    @Test
    fun readErrorRetryResubscribesAndCanYieldAnEmptyList() = runTest {
        val repo = ShoppingUiHousehold().apply { failRead = true }
        val vm = model(repo)
        runCurrent()
        assertTrue(vm.state.value is ScreenState.Error)
        repo.failRead = false
        repo.values.value = com.example.mobile_android.domain.Household()
        vm.retry()
        runCurrent()
        assertTrue(data(vm).quote.lines.isEmpty())
    }

    @Test
    fun suggestedPackageAddedByTheExistingActionMatchesTheDisplayedFake() = runTest {
        val repo = ShoppingUiHousehold()
        val vm = model(repo)
        runCurrent()
        val shown = requireNotNull(data(vm).suggestion)
        vm.addSuggestion()
        runCurrent()
        val stored =
            repo.values.value.manualPurchases.single { it.ingredientId == shown.ingredient.id }
        assertEquals(shown.quantity, stored.quantity)
        assertTrue(repo.values.value.pantry.isEmpty())
    }

    @Test
    fun unknownCataloguePriceDoesNotBecomeAKnownRecommendation() {
        val catalog = com.example.mobile_android.data.DemoCatalog.catalog
        val unknown =
            catalog.copy(
                ingredients =
                    catalog.ingredients.map {
                        if (it.id == "hard-cheese") it.copy(offer = null) else it
                    },
            )
        assertNull(FakeShoppingSuggestionSource().suggestion(unknown, 50000))
    }

    @Test
    fun fakeRecommendationIsAbsentBelowItsFixedPackagePrice() {
        val catalog = com.example.mobile_android.data.DemoCatalog.catalog
        assertNull(FakeShoppingSuggestionSource().suggestion(catalog, 20000))
        assertEquals(
            23000L,
            FakeShoppingSuggestionSource().suggestion(catalog, 50000)?.priceKopecks,
        )
    }
}
