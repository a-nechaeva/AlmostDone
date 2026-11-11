package com.example.mobile_android.feature.profile

import com.example.mobile_android.domain.*
import com.example.mobile_android.feature.MainDispatcherRule
import com.example.mobile_android.feature.common.ScreenState
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.test.*
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class ProfileDraftViewModelTest {
    @get:Rule val main = MainDispatcherRule()

    @Test
    fun savesCompleteDraftOnceAndRestoresFromRepository() = runTest {
        val repo = ProfileUiPreferences()
        val vm = ProfileViewModel(repo)
        val draft =
            FoodPreferences(
                FoodType.VEGAN,
                setOf(Allergen.MILK),
                true,
                true,
                true,
                "  Стол из назначения  ",
            )
        val subscription =
            backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { vm.state.collect() }
        runCurrent()
        assertEquals(FoodPreferences(), repo.values.value)
        vm.save(draft)
        advanceUntilIdle()
        val expected = draft.copy(dietTable = "Стол из назначения")
        assertEquals(1, repo.writes)
        assertEquals(expected, repo.values.value)
        assertEquals(ScreenState.Ready(expected), vm.state.value)
        val restored = ProfileViewModel(repo)
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { restored.state.collect() }
        runCurrent()
        assertEquals(ScreenState.Ready(expected), restored.state.value)
        subscription.cancel()
    }

    @Test
    fun saveFailureRetainsSavedValueAndRetryIsOneFullWrite() = runTest {
        val original = FoodPreferences(excludedAllergens = setOf(Allergen.MILK))
        val repo = ProfileUiPreferences(original).apply { writeFailure = true }
        val vm = ProfileViewModel(repo)
        val draft = original.copy(lactoseFree = true, diabetes = true, dietTable = "Назначение")
        vm.save(draft)
        advanceUntilIdle()
        assertTrue(vm.actions.state.value.failed)
        assertEquals(original, repo.values.value)
        repo.writeFailure = false
        vm.save(draft)
        advanceUntilIdle()
        assertEquals(draft, repo.values.value)
        assertEquals(2, repo.writes)
        assertFalse(vm.actions.state.value.failed)
    }

    @Test
    fun pendingSavePreventsDuplicateSubmission() = runTest {
        val repo = ProfileUiPreferences().apply { gate = CompletableDeferred() }
        val vm = ProfileViewModel(repo)
        val draft = FoodPreferences(lactoseFree = true)
        vm.save(draft)
        vm.save(FoodPreferences(diabetes = true))
        runCurrent()
        assertTrue(vm.actions.state.value.pending)
        assertEquals(1, repo.writes)
        assertEquals(FoodPreferences(), repo.values.value)
        repo.gate!!.complete(Unit)
        advanceUntilIdle()
        assertEquals(draft, repo.values.value)
        assertFalse(vm.actions.state.value.pending)
    }

    @Test
    fun loadingErrorRetryAndEmptyPreferences() = runTest {
        val repo = ProfileUiPreferences().apply { readFailure = true }
        val vm = ProfileViewModel(repo)
        assertEquals(ScreenState.Loading, vm.state.value)
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { vm.state.collect() }
        runCurrent()
        assertTrue(vm.state.value is ScreenState.Error)
        repo.readFailure = false
        vm.retry()
        runCurrent()
        assertEquals(ScreenState.Ready(FoodPreferences()), vm.state.value)
    }

    @Test
    fun lactoseAndMilkProteinStayIndependent() = runTest {
        val repo = ProfileUiPreferences()
        val vm = ProfileViewModel(repo)
        vm.save(FoodPreferences(lactoseFree = true))
        advanceUntilIdle()
        assertTrue(repo.values.value.lactoseFree)
        assertTrue(repo.values.value.excludedAllergens.isEmpty())
        vm.save(FoodPreferences(excludedAllergens = setOf(Allergen.MILK)))
        advanceUntilIdle()
        assertFalse(repo.values.value.lactoseFree)
        assertEquals(setOf(Allergen.MILK), repo.values.value.excludedAllergens)
    }
}
