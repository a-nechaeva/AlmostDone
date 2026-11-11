package com.example.mobile_android.feature.dishes

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.viewModelScope
import com.example.mobile_android.data.DemoCatalog
import com.example.mobile_android.domain.*
import com.example.mobile_android.feature.FakeHousehold
import com.example.mobile_android.feature.FakePreferences
import com.example.mobile_android.feature.MainDispatcherRule
import com.example.mobile_android.feature.common.ScreenState
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class DishesLocalViewModelTest {
    @get:Rule val main = MainDispatcherRule()
    private val models = mutableListOf<DishesViewModel>()
    private val household = FakeHousehold()
    private val profile = FakePreferences()

    @After
    fun clearModels() {
        models.forEach { it.viewModelScope.cancel() }
    }

    @Test
    fun availabilityIncludesZeroAndOneThroughThreeWithConfirmedData() = runTest {
        val ingredients = (1..6).map { Ingredient("i$it", "Продукт $it", QuantityUnit.GRAM) }
        val base = DemoCatalog.catalog.recipes.first()
        fun recipe(
            id: String,
            missing: Int,
            confirmed: Boolean = true,
            uncertain: Boolean = false,
        ) =
            base.copy(
                id = id,
                ingredients =
                    (ingredients.take(missing + 1) + ingredients.takeLast(1).filter { uncertain })
                        .map { RecipeIngredient(it.id, Quantity(10.0, it.unit)) },
                allergenDataComplete = confirmed,
            )
        household.values.value =
            Household(
                pantry =
                    listOf(
                        PantryItem("i1", Quantity(20.0, QuantityUnit.GRAM)),
                        PantryItem("i6", null),
                    )
            )
        val catalog =
            Catalog(
                ingredients,
                listOf(
                    recipe("ready", 0),
                    recipe("one", 1),
                    recipe("two", 2),
                    recipe("three", 3),
                    recipe("four", 4),
                    recipe("unknown-allergens", 0, confirmed = false),
                    recipe("unknown-quantity", 1, uncertain = true),
                ),
            )
        val model = model(catalog)
        collect(model)
        runCurrent()

        // Без исключённых аллергенов неполные сведения о них не мешают подбору.
        assertEquals(
            mapOf(
                "ready" to DishGroup.READY,
                "one" to DishGroup.BUY_ONE,
                "two" to DishGroup.BUY_TWO,
                "three" to DishGroup.BUY_THREE,
                "four" to DishGroup.ABOVE_LIMIT,
                "unknown-allergens" to DishGroup.READY,
                // i6 дома без количества — достаточно, не хватает только i2
                "unknown-quantity" to DishGroup.BUY_ONE,
            ),
            model.result.visible.associate { it.recipe.id to dishGroup(it) },
        )
        assertNull(model.result.visible.first { it.recipe.id == "one" }.purchaseKopecks)
        model.availabilityChanged(Availability.NOW)
        runCurrent()
        assertEquals(setOf("ready", "unknown-allergens"), model.result.visible.map { it.recipe.id }.toSet())
        model.availabilityChanged(Availability.BUY)
        runCurrent()
        assertEquals(
            setOf("one", "two", "three", "unknown-quantity"),
            model.result.visible.map { it.recipe.id }.toSet(),
        )

        // С исключённым аллергеном неполные сведения — «требуют проверки», в «Сейчас» не попадают.
        // Кунжута в блюде нет, но сведения неполные — подтвердить нельзя.
        model.toggleAllergen(Allergen.SESAME)
        model.availabilityChanged(Availability.ALL)
        runCurrent()
        val unknown = model.result.visible.first { it.recipe.id == "unknown-allergens" }
        assertEquals(DishGroup.DIET_UNKNOWN, dishGroup(unknown))
        assertEquals(listOf("Сведения об аллергенах неполные"), dishWarnings(unknown))
        model.availabilityChanged(Availability.NOW)
        runCurrent()
        assertFalse(model.result.visible.any { it.recipe.id == "unknown-allergens" })
    }

    @Test
    fun graphPurchaseSetIsAddedToShoppingAsWholePackages() = runTest {
        household.values.value =
            Household(pantry = DemoCatalog.initialPantry.filter { it.ingredientId != "tomatoes" })
        val model = model()
        collect(model)
        runCurrent()
        assertEquals("hard-cheese+tomatoes", model.result.purchaseSets.first().key)
        model.availabilityChanged(Availability.NOW)
        runCurrent()
        assertTrue(model.result.purchaseSets.isEmpty())
        model.availabilityChanged(Availability.ALL)
        runCurrent()
        model.addPurchaseSet("hard-cheese+tomatoes")
        runCurrent()
        assertEquals(
            listOf(
                ManualPurchase("hard-cheese", Quantity(200.0, QuantityUnit.GRAM)),
                ManualPurchase("tomatoes", Quantity(500.0, QuantityUnit.GRAM)),
            ),
            household.values.value.manualPurchases,
        )
    }

    @Test
    fun hiddenContextUsesAllFiltersAndTemporaryAllergensAreRestoredOutsideProfile() = runTest {
        val saved = SavedStateHandle()
        profile.values.value = FoodPreferences(excludedAllergens = setOf(Allergen.GLUTEN))
        val model = model(saved = saved)
        collect(model)
        model.toggleAllergen(Allergen.MILK)
        runCurrent()
        assertEquals(setOf("omelette", "pasta", "cheese", "cheeseEgg"), model.result.hidden.ids())

        model.queryChanged("ОМЛЕТ")
        model.maxMinutesChanged(15)
        model.maxKcalChanged(450)
        model.methodChanged(CookingMethod.STOVE.name)
        model.availabilityChanged(Availability.BUY)
        runCurrent()
        assertEquals(setOf("cheeseEgg"), model.result.hidden.ids())
        assertEquals(listOf("Содержит: Молоко"), model.result.hidden.single().dietary.reasons)
        assertTrue(model.result.visible.isEmpty())

        val restored = model(saved = saved)
        collect(restored)
        runCurrent()
        assertEquals(model.result.filters, restored.result.filters)
        assertEquals(model.result.hidden, restored.result.hidden)
        restored.methodChanged(CookingMethod.OVEN.name)
        runCurrent()
        assertTrue(restored.result.hidden.isEmpty())
        restored.resetFilters()
        runCurrent()
        assertEquals(DishFilters(), restored.result.filters)
        assertEquals(setOf("pasta", "cheese"), restored.result.hidden.ids())
        assertEquals(setOf(Allergen.GLUTEN), profile.values.value.excludedAllergens)
    }

    @Test
    fun completedCalculationCannotPublishAfterNewInputsHaveArrived() = runTest {
        val computation = QueuedDishesDispatcher()
        val model = model(dispatcher = computation)
        val emitted = mutableListOf<DishesState>()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
            model.state.collect { if (it is ScreenState.Ready) emitted += it.data }
        }
        runCurrent()
        computation.runNext()
        model.queryChanged("Омлет")
        model.toggleAllergen(Allergen.MILK)
        household.values.value = Household()
        runCurrent()
        assertTrue(emitted.isEmpty())
        assertEquals("Омлет", model.query.value)

        while (computation.hasWork) {
            computation.runNext()
            runCurrent()
        }
        assertEquals(1, emitted.size)
        val result = emitted.single()
        assertEquals("Омлет", result.filters.query)
        assertEquals(setOf("omelette", "cheeseEgg"), result.hidden.ids())
        assertEquals(listOf(4, 4), result.hidden.map { it.missing.size })
        assertTrue(result.household.pantry.isEmpty())
    }

    @Test
    fun exactTimeLimitAndIncompleteAllergensKeepGraphSuggestionsQualified() = runTest {
        val base = DemoCatalog.catalog
        val cheese = base.recipes.first { it.id == "cheese" }
        val catalog =
            base.copy(
                recipes =
                    listOf(
                        cheese.copy(id = "180", minutes = 180),
                        cheese.copy(id = "181", minutes = 181),
                        cheese.copy(id = "incomplete", allergenDataComplete = false),
                    )
            )
        val model = model(catalog)
        collect(model)
        runCurrent()
        // Без исключённых аллергенов блюдо с неполными сведениями участвует в подсказке.
        assertEquals(setOf("180", "181", "incomplete"), model.result.suggestion?.recipeIds)
        val incomplete = model.result.visible.first { it.recipe.id == "incomplete" }
        assertEquals(Suitability.ALLOWED, incomplete.dietary.status)
        assertEquals(DishGroup.BUY_ONE, dishGroup(incomplete))

        model.maxMinutesChanged(180)
        runCurrent()
        assertEquals(setOf("180", "incomplete"), model.result.suggestion?.recipeIds)
        model.maxMinutesChanged(ANY_MINUTES)
        runCurrent()
        assertEquals(setOf("180", "181", "incomplete"), model.result.suggestion?.recipeIds)

        // С исключённым аллергеном — только блюда с полными сведениями.
        model.toggleAllergen(Allergen.SESAME)
        runCurrent()
        assertEquals(setOf("180", "181"), model.result.suggestion?.recipeIds)
    }

    @Test
    fun graphCannotAddPreviousSuggestionWhilePantryChangeIsBeingCalculated() = runTest {
        val computation = QueuedDishesDispatcher()
        val model = model(dispatcher = computation)
        collect(model)
        runCurrent()
        computation.runNext()
        runCurrent()
        assertNotNull(model.result.suggestion)

        household.values.value = Household()
        runCurrent()
        assertTrue(computation.hasWork)
        assertNotEquals(model.result.inputRevision, model.inputRevision.value)
        model.addPurchase()
        runCurrent()
        assertTrue(household.values.value.manualPurchases.isEmpty())
        computation.runNext()
        runCurrent()
        assertNull(model.result.suggestion)
    }

    private fun model(
        fixture: Catalog = DemoCatalog.catalog,
        saved: SavedStateHandle = SavedStateHandle(),
        dispatcher: CoroutineDispatcher = main.dispatcher,
    ) =
        DishesViewModel(
                object : CatalogRepository {
                    override val catalog = flowOf(fixture)
                },
                household,
                profile,
                saved,
                dispatcher,
            )
            .also { models += it }

    private fun TestScope.collect(model: DishesViewModel) {
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { model.state.collect {} }
    }

    private val DishesViewModel.result
        get() = (state.value as ScreenState.Ready).data

    private fun List<RecipeMatch>.ids() = map { it.recipe.id }.toSet()
}
