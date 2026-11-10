package com.example.mobile_android.feature.favorites.localwiring

import androidx.lifecycle.viewModelScope
import com.example.mobile_android.domain.Quantity
import com.example.mobile_android.domain.QuantityUnit
import com.example.mobile_android.feature.favorites.FavoritesIngredientSelection
import com.example.mobile_android.feature.favorites.FavoritesPantryWrite.Phase
import com.example.mobile_android.feature.favorites.FavoritesViewModel
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.cancel
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class FavoritesLocalWiringViewModelTest {
    private val dispatcher = StandardTestDispatcher()
    private val fixture = FavoritesLocalWiringFixture()
    private val selection = FavoritesIngredientSelection("eggs", Quantity(2.0, QuantityUnit.PIECE))
    private lateinit var viewModel: FavoritesViewModel

    @Before fun setUp() {
        Dispatchers.setMain(dispatcher)
        viewModel = FavoritesViewModel(fixture.catalog, fixture.household, fixture.preferences)
    }

    @After fun tearDown() {
        viewModel.viewModelScope.cancel()
        Dispatchers.resetMain()
    }

    @Test fun guardsPendingAndCompletedConfirmationUntilTheDialogCloses() = runTest(dispatcher) {
        val gate = CompletableDeferred<Unit>()
        fixture.household.pantryGate = gate
        val revision = viewModel.pantryWrite.value.revision
        repeat(3) { viewModel.addIngredientToPantry(selection, revision) }
        viewModel.favorite("eggs", true)
        assertFalse(viewModel.tryDismissPantryWrite())
        runCurrent()
        assertEquals(Phase.Saving, viewModel.pantryWrite.value.phase)
        assertEquals(listOf(selection), fixture.household.pantryAdds)
        assertTrue("eggs" in fixture.household.values.value.favoriteIngredients)

        gate.complete(Unit)
        runCurrent()
        assertEquals(Phase.Added, viewModel.pantryWrite.value.phase)
        confirm()
        runCurrent()
        assertEquals(listOf(selection), fixture.household.pantryAdds)

        assertTrue(viewModel.tryDismissPantryWrite())
        confirm()
        runCurrent()
        assertEquals(listOf(selection, selection), fixture.household.pantryAdds)
    }

    @Test fun doesNotStartPantryWriteDuringFavoriteRemoval() = runTest(dispatcher) {
        viewModel.favorite("omelette", false)
        confirm()
        runCurrent()
        assertTrue(fixture.household.pantryAdds.isEmpty())
        assertEquals(Phase.Idle, viewModel.pantryWrite.value.phase)
    }

    @Test fun cancellationClearsPendingWithoutShowingFailure() = runTest(dispatcher) {
        fixture.household.pantryGate = CompletableDeferred()
        val before = fixture.household.values.value
        confirm()
        runCurrent()
        assertEquals(Phase.Saving, viewModel.pantryWrite.value.phase)
        viewModel.viewModelScope.cancel()
        runCurrent()
        assertEquals(Phase.Idle, viewModel.pantryWrite.value.phase)
        assertEquals(before, fixture.household.values.value)
    }

    private fun confirm() {
        viewModel.addIngredientToPantry(selection, viewModel.pantryWrite.value.revision)
    }
}
