package com.example.mobile_android.feature.shopping

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.mobile_android.feature.MainDispatcherRule
import java.io.IOException
import kotlinx.coroutines.*
import kotlinx.coroutines.test.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class ShoppingBudgetViewModelTest {
    @get:Rule val main = MainDispatcherRule()
    private val models = mutableListOf<ViewModel>()

    private fun model(
        source: ShoppingBudgetSource = FakeShoppingBudgetSource(),
        saved: SavedStateHandle = SavedStateHandle(),
    ) = ShoppingBudgetViewModel(saved, source).also { models += it }

    @After
    fun close() {
        models.forEach { it.viewModelScope.cancel() }
    }

    @Test
    fun invalidAmountsNeverRequestAPlan() = runTest {
        var calls = 0
        val vm =
            model(
                ShoppingBudgetSource {
                    calls++
                    FakeShoppingBudgetSource.READY
                },
            )
        listOf("", "-1", "1,001", "1000001", "9999999999999999999999", "пятьсот").forEach {
            vm.textChanged(it)
            vm.submit()
            runCurrent()
            assertTrue(vm.form.value.invalid)
            assertEquals(ShoppingBudgetResult.Idle, vm.form.value.result)
        }
        assertEquals(0, calls)
    }

    @Test
    fun decimalInputIsPassedInKopecks() = runTest {
        var amount = -1L
        val vm =
            model(
                ShoppingBudgetSource {
                    amount = it
                    FakeShoppingBudgetSource.READY
                },
            )
        vm.textChanged("500,25")
        vm.submit()
        runCurrent()
        assertEquals(50025L, amount)
        assertEquals(
            ShoppingBudgetEstimate.WITHIN_EXAMPLE_BUDGET,
            (vm.form.value.result as ShoppingBudgetResult.Ready).estimate,
        )
    }

    @Test
    fun zeroIsAValidBudgetButFakeHasNoPlan() = runTest {
        val vm = model()
        vm.textChanged("0")
        vm.submit()
        runCurrent()
        assertEquals(ShoppingBudgetResult.Empty, vm.form.value.result)
    }

    @Test
    fun emptyReplyHasAnExplicitEmptyState() = runTest {
        val vm = model(FakeShoppingBudgetSource(null))
        vm.submit()
        runCurrent()
        assertEquals(ShoppingBudgetResult.Empty, vm.form.value.result)
    }

    @Test
    fun emptyPackageListIsNotAZeroCostPlan() = runTest {
        val vm =
            model(
                FakeShoppingBudgetSource(
                    FakeShoppingBudgetSource.READY.copy(packages = emptyList(), totalKopecks = 0),
                ),
            )
        vm.submit()
        runCurrent()
        assertEquals(ShoppingBudgetResult.Empty, vm.form.value.result)
    }

    @Test
    fun unknownLinePriceCannotConfirmBudgetEvenWithKnownTotal() = runTest {
        val reply = FakeShoppingBudgetSource.UNKNOWN_PRICE.copy(totalKopecks = 0)
        val vm = model(FakeShoppingBudgetSource(reply))
        vm.submit()
        runCurrent()
        assertEquals(
            ShoppingBudgetEstimate.UNKNOWN,
            (vm.form.value.result as ShoppingBudgetResult.Ready).estimate,
        )
    }

    @Test
    fun unknownTotalCannotConfirmBudgetEvenWithKnownLines() = runTest {
        val vm =
            model(
                FakeShoppingBudgetSource(FakeShoppingBudgetSource.READY.copy(totalKopecks = null)),
            )
        vm.submit()
        runCurrent()
        assertEquals(
            ShoppingBudgetEstimate.UNKNOWN,
            (vm.form.value.result as ShoppingBudgetResult.Ready).estimate,
        )
    }

    @Test
    fun errorCanBeRetriedAndPendingDoubleSubmitIsIgnored() = runTest {
        var calls = 0
        val gate = CompletableDeferred<Unit>()
        val vm =
            model(
                ShoppingBudgetSource {
                    calls++
                    gate.await()
                    if (calls == 1) throw IOException("test")
                    FakeShoppingBudgetSource.READY
                },
            )
        vm.submit()
        runCurrent()
        assertEquals(ShoppingBudgetResult.Loading, vm.form.value.result)
        vm.submit()
        runCurrent()
        assertEquals(1, calls)
        gate.complete(Unit)
        runCurrent()
        assertEquals(ShoppingBudgetResult.Error, vm.form.value.result)
        vm.retry()
        runCurrent()
        assertTrue(vm.form.value.result is ShoppingBudgetResult.Ready)
    }

    @Test
    fun editingInputRejectsStaleReplyEvenIfSourceIgnoresCancellation() = runTest {
        val old = CompletableDeferred<Unit>()
        val vm =
            model(
                ShoppingBudgetSource { amount ->
                    if (amount == 50000L) withContext(NonCancellable) { old.await() }
                    FakeShoppingBudgetSource.READY.copy(title = amount.toString())
                },
            )
        vm.submit()
        runCurrent()
        vm.textChanged("300")
        vm.submit()
        runCurrent()
        assertEquals("30000", (vm.form.value.result as ShoppingBudgetResult.Ready).example.title)
        old.complete(Unit)
        runCurrent()
        assertEquals("30000", (vm.form.value.result as ShoppingBudgetResult.Ready).example.title)
    }

    @Test
    fun backCancelsResultAndPreservesDraft() = runTest {
        val vm = model()
        vm.textChanged("300")
        vm.submit()
        runCurrent()
        vm.clearResult()
        assertEquals("300", vm.form.value.text)
        assertEquals(ShoppingBudgetResult.Idle, vm.form.value.result)
    }

    @Test
    fun draftSurvivesRecreationButFakeResultIsNotRestoredAsCurrent() = runTest {
        val saved = SavedStateHandle()
        val vm = model(saved = saved)
        vm.textChanged("123,45")
        vm.submit()
        runCurrent()
        val restored =
            model(saved = SavedStateHandle(saved.keys().associateWith { saved.get<Any?>(it) }))
        assertEquals("123,45", restored.form.value.text)
        assertEquals(ShoppingBudgetResult.Idle, restored.form.value.result)
    }
}
