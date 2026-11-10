package com.example.mobile_android.feature.pantry

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.viewModelScope
import com.example.mobile_android.data.DemoCatalogRepository
import com.example.mobile_android.domain.*
import com.example.mobile_android.feature.common.ScreenState
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.test.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class PantryUiViewModelTest {
    private val dispatcher = StandardTestDispatcher()
    private val created = mutableListOf<PantryViewModel>()

    @Before
    fun setup() {
        Dispatchers.setMain(dispatcher)
    }

    @After
    fun teardown() {
        created.forEach { it.viewModelScope.cancel() }
        Dispatchers.resetMain()
    }

    private fun TestScope.model(
        h: PantryUiHousehold,
        saved: SavedStateHandle = SavedStateHandle(),
    ) =
        PantryViewModel(DemoCatalogRepository(), h, saved).also { vm ->
            created += vm
            backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { vm.state.collect() }
        }

    private fun data(vm: PantryViewModel) = (vm.state.value as ScreenState.Ready).data

    @Test
    fun latestLocalQueryAndSavedInputUseCanonicalCatalogIds() =
        runTest(dispatcher) {
            val saved = SavedStateHandle()
            val vm = model(PantryUiHousehold(), saved)
            runCurrent()
            vm.queryChanged("сыр")
            vm.queryChanged("  ТоМ  ")
            runCurrent()
            assertEquals(listOf("tomatoes"), data(vm).suggestions.map { it.id })
            val restored =
                model(
                    PantryUiHousehold(),
                    SavedStateHandle(saved.keys().associateWith { saved.get<Any?>(it) }),
                )
            runCurrent()
            assertEquals("  ТоМ  ", data(restored).query)
            vm.queryChanged("несуществующий продукт")
            runCurrent()
            assertTrue(data(vm).suggestions.isEmpty())
        }

    @Test
    fun addAndAbsoluteEditUseDifferentRepositoryOperations() =
        runTest(dispatcher) {
            val h = PantryUiHousehold()
            val vm = model(h)
            runCurrent()
            vm.add("tomatoes", Quantity(200.0, QuantityUnit.GRAM))
            runCurrent()
            assertEquals(
                700.0,
                data(vm).household.pantry.single { it.ingredientId == "tomatoes" }.quantity!!.value,
                0.0,
            )
            vm.edit("tomatoes", Quantity(100.0, QuantityUnit.GRAM))
            runCurrent()
            assertEquals(
                100.0,
                data(vm).household.pantry.single { it.ingredientId == "tomatoes" }.quantity!!.value,
                0.0,
            )
            assertEquals(listOf("add:tomatoes", "set:tomatoes"), h.calls.map { it.first })
            vm.edit("tomatoes", null)
            runCurrent()
            vm.add("tomatoes", Quantity(20.0, QuantityUnit.GRAM))
            runCurrent()
            assertNull(data(vm).household.pantry.single { it.ingredientId == "tomatoes" }.quantity)
        }

    @Test
    fun pendingWritesRejectDoubleTapAndFailureKeepsQueryUntilRetrySucceeds() =
        runTest(dispatcher) {
            val h =
                PantryUiHousehold().apply {
                    failWrite = true
                    gate = CompletableDeferred()
                }
            val vm = model(h)
            runCurrent()
            vm.queryChanged("том")
            runCurrent()
            vm.add("tomatoes", Quantity(200.0, QuantityUnit.GRAM))
            vm.add("tomatoes", Quantity(200.0, QuantityUnit.GRAM))
            runCurrent()
            assertTrue(vm.actions.state.value.pending)
            assertEquals(1, h.calls.size)
            h.gate!!.complete(Unit)
            runCurrent()
            assertTrue(vm.actions.state.value.failed)
            assertEquals("том", data(vm).query)
            h.failWrite = false
            vm.add("tomatoes", Quantity(200.0, QuantityUnit.GRAM))
            runCurrent()
            assertFalse(vm.actions.state.value.failed)
            assertEquals("", data(vm).query)
            assertEquals(1, data(vm).added.count { it.first.id == "tomatoes" })
        }

    @Test
    fun failedReadRetriesAndFailedUndoKeepsDeletedItem() =
        runTest(dispatcher) {
            val h = PantryUiHousehold().apply { failRead = true }
            val vm = model(h)
            assertTrue(vm.state.value is ScreenState.Loading)
            runCurrent()
            assertTrue(vm.state.value is ScreenState.Error)
            h.failRead = false
            vm.retry()
            runCurrent()
            val item = data(vm).household.pantry.first()
            vm.remove(item)
            runCurrent()
            assertEquals(item, vm.deleted.value)
            h.failWrite = true
            vm.undoDelete()
            runCurrent()
            assertEquals(item, vm.deleted.value)
            h.failWrite = false
            vm.undoDelete()
            runCurrent()
            assertNull(vm.deleted.value)
            assertEquals(
                item,
                data(vm).household.pantry.single { it.ingredientId == item.ingredientId },
            )
        }
}
