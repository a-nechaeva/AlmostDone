package com.example.mobile_android.feature.favorites

import androidx.lifecycle.viewModelScope
import com.example.mobile_android.data.DemoCatalog
import com.example.mobile_android.data.DemoCatalogRepository
import com.example.mobile_android.domain.*
import com.example.mobile_android.feature.common.ScreenState
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.test.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class FavoritesViewModelTest {
    private val dispatcher = StandardTestDispatcher()
    private val models = mutableListOf<FavoritesViewModel>()
    @Before fun setup() { Dispatchers.setMain(dispatcher) }
    @After fun cleanup() {
        models.forEach { it.viewModelScope.cancel() }
        Dispatchers.resetMain()
    }

    private fun TestScope.model(
        household: FavoritesHouseholdFake = FavoritesHouseholdFake(),
        catalog: CatalogRepository = DemoCatalogRepository(),
        preferences: PreferencesRepository = FavoritesPreferencesFake(),
    ): FavoritesViewModel {
        val vm = FavoritesViewModel(catalog, household, preferences)
        models += vm
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { vm.state.collect() }
        return vm
    }
    private fun data(vm: FavoritesViewModel) = (vm.state.value as ScreenState.Ready).data

    @Test fun loadingWaitsForTheCatalogAndThenShowsBothLists() = runTest(dispatcher) {
        val source = MutableSharedFlow<Catalog>(replay = 1)
        val h = FavoritesHouseholdFake(Household(
            favoriteRecipes = setOf("cheese"), favoriteIngredients = setOf("eggs"),
        ))
        val vm = model(h, object : CatalogRepository { override val catalog = source })
        runCurrent()
        assertEquals(ScreenState.Loading, vm.state.value)
        source.emit(DemoCatalog.catalog)
        runCurrent()
        assertEquals(listOf("cheese"), data(vm).recipes.map { it.recipe.id })
        assertEquals(listOf("eggs"), data(vm).ingredients.map { it.id })
    }

    @Test fun sharedHouseholdChangesUpdateBothListsWithoutRestart() = runTest(dispatcher) {
        val h = FavoritesHouseholdFake()
        val vm = model(h)
        runCurrent()
        assertTrue(data(vm).recipes.isEmpty())
        assertTrue(data(vm).ingredients.isEmpty())
        h.toggleFavorite("omelette", false)
        h.toggleFavorite("tomatoes", true)
        runCurrent()
        assertEquals("omelette", data(vm).recipes.single().recipe.id)
        assertEquals("tomatoes", data(vm).ingredients.single().id)
        h.values.value = Household()
        runCurrent()
        assertTrue(data(vm).recipes.isEmpty())
        assertTrue(data(vm).ingredients.isEmpty())
    }

    @Test fun failedReadCanBeRetried() = runTest(dispatcher) {
        val h = FavoritesHouseholdFake().apply { failRead = true }
        val vm = model(h)
        runCurrent()
        assertTrue(vm.state.value is ScreenState.Error)
        h.failRead = false
        vm.retry()
        runCurrent()
        assertTrue(vm.state.value is ScreenState.Ready)
    }

    @Test fun catalogFailureCanBeRetriedWithoutUsingAnEmptyFallback() = runTest(dispatcher) {
        var fail = true
        val repo = object : CatalogRepository {
            override val catalog: Flow<Catalog> get() = flow {
                if (fail) throw java.io.IOException("catalog")
                emit(DemoCatalog.catalog)
            }
        }
        val vm = model(catalog = repo)
        runCurrent()
        assertTrue(vm.state.value is ScreenState.Error)
        fail = false
        vm.retry()
        runCurrent()
        assertTrue(vm.state.value is ScreenState.Ready)
    }

    @Test fun preferencesFailureDoesNotExposeUnrestrictedRecipes() = runTest(dispatcher) {
        val vm = model(preferences = object : PreferencesRepository {
            override val preferences = flow<FoodPreferences> { throw java.io.IOException("preferences") }
            override suspend fun update(transform: (FoodPreferences) -> FoodPreferences) = Unit
        })
        runCurrent()
        assertTrue(vm.state.value is ScreenState.Error)
    }

    @Test fun duplicateClicksWhilePendingAndAfterSuccessDoNotAddFavoriteBack() = runTest(dispatcher) {
        for (ingredient in listOf(false, true)) {
            val h = FavoritesHouseholdFake(Household(
                favoriteRecipes = setOf("omelette"), favoriteIngredients = setOf("omelette"),
            ))
            val gate = CompletableDeferred<Unit>()
            h.writeGate = gate
            val vm = model(h)
            runCurrent()
            repeat(3) { vm.favorite("omelette", ingredient) }
            runCurrent()
            assertTrue(vm.actions.state.value.pending)
            assertEquals(listOf("omelette" to ingredient), h.writes)
            gate.complete(Unit)
            runCurrent()
            assertFalse(vm.actions.state.value.pending)
            vm.favorite("omelette", ingredient)
            runCurrent()
            assertEquals(1, h.writes.size)
            assertFalse("omelette" in if (ingredient) h.values.value.favoriteIngredients else h.values.value.favoriteRecipes)
        }
    }

    @Test fun failedRemovalKeepsDataAndCanBeRetriedForEitherKind() = runTest(dispatcher) {
        for (ingredient in listOf(false, true)) {
            val h = FavoritesHouseholdFake(Household(
                favoriteRecipes = setOf("omelette"), favoriteIngredients = setOf("eggs"),
            )).apply { failWrite = true }
            val vm = model(h)
            runCurrent()
            val id = if (ingredient) "eggs" else "omelette"
            vm.favorite(id, ingredient)
            runCurrent()
            assertTrue(vm.actions.state.value.failed)
            assertFalse(vm.actions.state.value.pending)
            assertNotNull(vm.actions.state.value.message)
            assertEquals(1, data(vm).recipes.size)
            assertEquals(1, data(vm).ingredients.size)
            h.failWrite = false
            vm.favorite(id, ingredient)
            runCurrent()
            assertFalse(vm.actions.state.value.failed)
            if (ingredient) assertTrue(data(vm).ingredients.isEmpty())
            else assertTrue(data(vm).recipes.isEmpty())
        }
    }

    @Test fun cancellingRemovalDoesNotShowStorageError() = runTest(dispatcher) {
        val h = FavoritesHouseholdFake(Household(favoriteRecipes = setOf("omelette")))
        h.writeGate = CompletableDeferred()
        val vm = model(h)
        runCurrent()
        vm.favorite("omelette", false)
        runCurrent()
        vm.viewModelScope.cancel()
        runCurrent()
        assertFalse(vm.actions.state.value.pending)
        assertFalse(vm.actions.state.value.failed)
        assertNull(vm.actions.state.value.message)
        assertTrue("omelette" in h.values.value.favoriteRecipes)
    }
}
