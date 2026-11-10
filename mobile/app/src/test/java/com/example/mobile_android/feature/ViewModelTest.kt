package com.example.mobile_android.feature

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.mobile_android.data.DemoCatalog
import com.example.mobile_android.data.DemoCatalogRepository
import com.example.mobile_android.domain.*
import com.example.mobile_android.feature.auth.SessionViewModel
import com.example.mobile_android.feature.common.*
import com.example.mobile_android.feature.dishes.*
import com.example.mobile_android.feature.shopping.ShoppingViewModel
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.test.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class ViewModelTest {
    @get:Rule val main = MainDispatcherRule()
    private val created = mutableListOf<ViewModel>()

    @After
    fun close() {
        created.forEach { it.viewModelScope.cancel() }
    }

    private fun dishes(
        h: FakeHousehold = FakeHousehold(),
        p: FakePreferences = FakePreferences(),
        saved: SavedStateHandle = SavedStateHandle(),
    ) =
        DishesViewModel(DemoCatalogRepository(), h, p, saved, main.dispatcher).also {
            created += it
        }

    private fun TestScope.collect(vm: DishesViewModel) {
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { vm.state.collect() }
    }

    private fun data(vm: DishesViewModel) = (vm.state.value as ScreenState.Ready).data

    @Test
    fun addingFoodImmediatelyUpdatesMatches() = runTest {
        val h = FakeHousehold()
        val vm = dishes(h)
        collect(vm)
        runCurrent()
        assertFalse(data(vm).matches.first { it.recipe.id == "cheese" }.ready)
        h.addPantry("hard-cheese", Quantity(200.0, QuantityUnit.GRAM))
        runCurrent()
        assertTrue(data(vm).matches.first { it.recipe.id == "cheese" }.ready)
    }

    @Test
    fun profileChangeReclassifiesRecipesWithoutReloadingScreen() = runTest {
        val p = FakePreferences()
        val vm = dishes(p = p)
        collect(vm)
        runCurrent()
        p.update { it.copy(excludedAllergens = setOf(Allergen.MILK)) }
        runCurrent()
        assertEquals(
            setOf("omelette", "cheese", "cheeseEgg"),
            data(vm).hidden.map { it.recipe.id }.toSet(),
        )
        assertEquals(listOf("pasta"), data(vm).visible.map { it.recipe.id })
    }

    @Test
    fun calorieFilterUsesPerServingValues() = runTest {
        val vm = dishes()
        collect(vm)
        runCurrent()
        vm.maxKcalChanged(600)
        runCurrent()
        assertTrue(data(vm).visible.any { it.recipe.id == "cheese" })
        vm.maxKcalChanged(500)
        runCurrent()
        assertFalse(data(vm).visible.any { it.recipe.id == "cheese" })
    }

    @Test
    fun selectedFiltersSurviveViewModelRecreation() = runTest {
        val saved = SavedStateHandle()
        val first = dishes(saved = saved)
        collect(first)
        runCurrent()
        first.queryChanged("Паста")
        first.maxMinutesChanged(30)
        first.availabilityChanged(Availability.BUY)
        first.maxKcalChanged(600)
        first.methodChanged(CookingMethod.STOVE.name)
        first.viewChanged(DishesView.GRAPH)
        runCurrent()
        val restored = SavedStateHandle(saved.keys().associateWith { saved.get<Any?>(it) })
        val second = dishes(saved = restored)
        collect(second)
        runCurrent()
        assertEquals("Паста", data(second).filters.query)
        assertEquals(Availability.BUY, data(second).filters.availability)
        assertEquals(30, data(second).filters.maxMinutes)
        assertEquals(600, data(second).filters.maxKcal)
        assertEquals(CookingMethod.STOVE.name, data(second).filters.method)
        assertEquals(DishesView.GRAPH.name, second.view.value)
        assertEquals(listOf("cheese"), data(second).visible.map { it.recipe.id })
        assertEquals(setOf("cheese"), data(second).suggestion!!.recipeIds)
    }

    @Test
    fun graphUsesFilteredMatchesAndSwitchingViewsDoesNotResetThem() = runTest {
        val vm = dishes()
        collect(vm)
        runCurrent()
        assertEquals(setOf("cheese", "cheeseEgg"), data(vm).suggestion!!.recipeIds)
        vm.queryChanged("Омлет")
        vm.availabilityChanged(Availability.BUY)
        vm.maxMinutesChanged(15)
        vm.maxKcalChanged(450)
        vm.methodChanged(CookingMethod.STOVE.name)
        runCurrent()
        val filtered = data(vm)
        assertEquals(listOf("cheeseEgg"), filtered.visible.map { it.recipe.id })
        assertEquals(setOf("cheeseEgg"), filtered.suggestion!!.recipeIds)
        vm.viewChanged(DishesView.GRAPH)
        runCurrent()
        assertEquals(filtered, data(vm))
        vm.viewChanged(DishesView.LIST)
        runCurrent()
        assertEquals(filtered, data(vm))
        vm.availabilityChanged(Availability.NOW)
        runCurrent()
        assertEquals(listOf("omelette"), data(vm).visible.map { it.recipe.id })
        assertNull(data(vm).suggestion)
        vm.resetFilters()
        runCurrent()
        assertEquals(4, data(vm).visible.size)
    }

    @Test
    fun graphReactsToPantryAndNeverPromisesUnknownOrDisallowedRecipes() = runTest {
        val h = FakeHousehold()
        val p = FakePreferences()
        val vm = dishes(h, p)
        collect(vm)
        runCurrent()
        h.setPantry("hard-cheese", null)
        runCurrent()
        assertNull(data(vm).suggestion)
        h.removePantry("hard-cheese")
        p.update { it.copy(diabetes = true) }
        runCurrent()
        assertNull(data(vm).suggestion)
        p.update { FoodPreferences(excludedAllergens = setOf(Allergen.MILK)) }
        runCurrent()
        assertNull(data(vm).suggestion)
        p.update { FoodPreferences() }
        h.addPantry("hard-cheese", Quantity(200.0, QuantityUnit.GRAM))
        runCurrent()
        assertNull(data(vm).suggestion)
        assertTrue(data(vm).visible.all { it.ready })
    }

    @Test
    fun graphPurchaseUsesCommonShoppingQuoteAndCanRetryAFailedWrite() = runTest {
        val h = FakeHousehold()
        val vm = dishes(h)
        collect(vm)
        runCurrent()
        h.failWrite = true
        vm.addPurchase()
        runCurrent()
        assertTrue(vm.actions.state.value.failed)
        assertTrue(h.values.value.manualPurchases.isEmpty())
        h.failWrite = false
        vm.addPurchase()
        runCurrent()
        vm.addPurchase()
        runCurrent()
        val basket = shoppingQuote(DemoCatalog.catalog, h.values.value)
        assertEquals(1, h.values.value.manualPurchases.size)
        assertEquals("hard-cheese", basket.lines.single().ingredientId)
        assertEquals(Quantity(200.0, QuantityUnit.GRAM), basket.lines.single().buyQuantity)
        assertEquals(23000L, basket.totalKopecks)
        assertEquals(DemoCatalog.initialPantry, h.values.value.pantry)
        assertFalse(vm.actions.state.value.failed)
    }

    @Test
    fun graphSelectionAndFiltersSurviveReadErrorLoadingAndRetry() = runTest {
        var fail = true
        val source = MutableSharedFlow<Catalog>(replay = 1)
        val repository =
            object : CatalogRepository {
                override val catalog = flow {
                    if (fail) throw java.io.IOException("offline")
                    emitAll(source)
                }
            }
        val vm =
            DishesViewModel(
                    repository,
                    FakeHousehold(),
                    FakePreferences(),
                    SavedStateHandle(),
                    main.dispatcher,
                )
                .also { created += it }
        collect(vm)
        runCurrent()
        assertTrue(vm.state.value is ScreenState.Error)
        vm.viewChanged(DishesView.GRAPH)
        vm.queryChanged("Омлет")
        fail = false
        vm.retry()
        runCurrent()
        assertEquals(ScreenState.Loading, vm.state.value)
        source.emit(DemoCatalog.catalog)
        runCurrent()
        assertEquals(DishesView.GRAPH.name, vm.view.value)
        assertEquals("Омлет", data(vm).filters.query)
        assertEquals(setOf("cheeseEgg"), data(vm).suggestion!!.recipeIds)
    }

    @Test
    fun readFailureIsShownAndRetryResubscribes() = runTest {
        val h = FakeHousehold().apply { failRead = true }
        val vm = dishes(h)
        collect(vm)
        runCurrent()
        assertTrue(vm.state.value is ScreenState.Error)
        h.failRead = false
        vm.retry()
        runCurrent()
        assertTrue(vm.state.value is ScreenState.Ready)
    }

    @Test
    fun profileReadFailureNeverFallsBackToUnrestrictedRecipes() = runTest {
        val vm = dishes(p = FakePreferences().apply { failRead = true })
        collect(vm)
        runCurrent()
        assertTrue(vm.state.value is ScreenState.Error)
    }

    @Test
    fun failedMutationCanBeRetriedWithoutStuckLoading() = runTest {
        val h = FakeHousehold().apply { failWrite = true }
        val vm = dishes(h)
        collect(vm)
        runCurrent()
        vm.favorite("cheese")
        runCurrent()
        assertTrue(vm.actions.state.value.failed)
        assertFalse(vm.actions.state.value.pending)
        h.failWrite = false
        vm.favorite("cheese")
        runCurrent()
        assertTrue("cheese" in h.values.value.favoriteRecipes)
        assertFalse(vm.actions.state.value.failed)
    }

    @Test
    fun cancelledRequestCannotOverwriteTheNewerResult() = runTest {
        val refresh = MutableStateFlow(0)
        val output = mutableListOf<ScreenState<Int>>()
        val collector =
            backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
                loadingStates(refresh) {
                        val request = refresh.value
                        flow {
                            delay(if (request == 0) 1000 else 10)
                            emit(request)
                        }
                    }
                    .collect { output += it }
            }
        runCurrent()
        refresh.value = 1
        runCurrent()
        advanceTimeBy(1500)
        runCurrent()
        assertEquals(listOf(1), output.filterIsInstance<ScreenState.Ready<Int>>().map { it.data })
        collector.cancel()
    }

    @Test
    fun cancellationIsNotReportedAsAWriteFailure() = runTest {
        val owner = CoroutineScope(SupervisorJob() + main.dispatcher)
        val actions = ScreenActions(owner)
        actions.run { awaitCancellation() }
        runCurrent()
        assertTrue(actions.state.value.pending)
        owner.cancel()
        runCurrent()
        assertFalse(actions.state.value.pending)
        assertFalse(actions.state.value.failed)
        assertNull(actions.state.value.message)
    }

    @Test
    fun passwordIsClearedOnBothFailedAndSuccessfulSignIn() = runTest {
        val repository =
            object : SessionRepository {
                val value = MutableStateFlow(false)
                override val signedIn: Flow<Boolean> = value

                override suspend fun signIn(login: String, password: String) {
                    require(login == "demo" && password == "demo")
                    value.value = true
                }

                override suspend fun signOut() {
                    value.value = false
                }
            }
        val vm = SessionViewModel(repository).also { created += it }
        vm.loginChanged("demo")
        vm.passwordChanged("wrong")
        vm.signIn()
        runCurrent()
        assertEquals("", vm.form.value.password)
        assertTrue(vm.actions.state.value.failed)
        vm.passwordChanged("demo")
        vm.signIn()
        runCurrent()
        assertEquals("", vm.form.value.password)
        assertTrue(repository.value.value)
    }

    @Test
    fun medicalUnknownIsNotListedAsReadyToCookNow() = runTest {
        val p = FakePreferences().apply { values.value = FoodPreferences(diabetes = true) }
        val vm = dishes(p = p)
        collect(vm)
        runCurrent()
        assertTrue(data(vm).visible.all { it.dietary.status == Suitability.UNKNOWN })
        vm.availabilityChanged(Availability.NOW)
        runCurrent()
        assertTrue(data(vm).visible.isEmpty())
    }

    @Test
    fun unknownNutritionCannotPassAnActiveCalorieLimit() = runTest {
        val source =
            object : CatalogRepository {
                override val catalog =
                    flowOf(
                        DemoCatalog.catalog.copy(
                            recipes =
                                listOf(
                                    DemoCatalog.catalog.recipes
                                        .first()
                                        .copy(nutritionPerServing = null)
                                )
                        )
                    )
            }
        val vm =
            DishesViewModel(
                    source,
                    FakeHousehold(),
                    FakePreferences(),
                    SavedStateHandle(),
                    main.dispatcher,
                )
                .also { created += it }
        collect(vm)
        runCurrent()
        assertEquals(1, data(vm).visible.size)
        vm.maxKcalChanged(500)
        runCurrent()
        assertTrue(data(vm).visible.isEmpty())
    }

    @Test
    fun changedProfileWarnsAboutPlannedRecipesWithoutDeletingThePlan() = runTest {
        val h =
            FakeHousehold().apply {
                values.value = values.value.copy(plan = listOf(PlannedRecipe("cheese", 2)))
            }
        val p = FakePreferences()
        val vm =
            ShoppingViewModel(DemoCatalogRepository(), h, p, SavedStateHandle()).also {
                created += it
            }
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { vm.state.collect() }
        runCurrent()
        p.update { it.copy(excludedAllergens = setOf(Allergen.MILK)) }
        runCurrent()
        val state = (vm.state.value as ScreenState.Ready).data
        assertEquals(listOf(PlannedRecipe("cheese", 2)), state.household.plan)
        assertTrue(state.planWarnings.single().contains("Молоко"))
    }

    @Test
    fun failedSignOutRetainsTheSessionAndExposesAnError() = runTest {
        val repo =
            object : SessionRepository {
                override val signedIn = flowOf(true)

                override suspend fun signIn(login: String, password: String) = Unit

                override suspend fun signOut() {
                    throw java.io.IOException("storage unavailable")
                }
            }
        val vm = SessionViewModel(repo).also { created += it }
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { vm.state.collect() }
        runCurrent()
        vm.signOut()
        runCurrent()
        assertEquals(true, (vm.state.value as ScreenState.Ready).data)
        assertTrue(vm.actions.state.value.failed)
        assertNotNull(vm.actions.state.value.message)
    }

    @Test
    fun sessionObservationSurvivesBackgroundWithoutReloadingTheGraph() = runTest {
        var subscriptions = 0
        val repo =
            object : SessionRepository {
                override val signedIn = flow {
                    subscriptions++
                    if (subscriptions > 1) delay(100)
                    emit(true)
                    awaitCancellation()
                }

                override suspend fun signIn(login: String, password: String) = Unit

                override suspend fun signOut() = Unit
            }
        val vm = SessionViewModel(repo).also { created += it }
        val first =
            backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { vm.state.collect() }
        runCurrent()
        assertEquals(true, (vm.state.value as ScreenState.Ready).data)
        first.cancel()
        advanceTimeBy(6000)
        runCurrent()
        val resumed = mutableListOf<ScreenState<Boolean>>()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
            vm.state.collect { resumed += it }
        }
        runCurrent()
        advanceTimeBy(200)
        runCurrent()
        assertEquals(1, subscriptions)
        assertTrue(resumed.all { it is ScreenState.Ready && it.data })
    }
}
