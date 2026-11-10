package com.example.mobile_android.feature.favorites

import android.app.Application
import android.os.SystemClock
import androidx.activity.ComponentActivity
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.cancel
import androidx.compose.runtime.*
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import com.example.mobile_android.data.DemoCatalog
import com.example.mobile_android.data.DemoCatalogRepository
import com.example.mobile_android.domain.*
import com.example.mobile_android.feature.common.*
import com.example.mobile_android.ui.UiSmoke
import com.example.mobile_android.ui.theme.AlmostReadyTheme
import kotlinx.coroutines.CompletableDeferred
import org.junit.Assert.*
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.experimental.categories.Category
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], application = Application::class,
    qualifiers = "ru-rRU-w400dp-h900dp-notnight-xhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Category(UiSmoke::class)
class FavoritesUiTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val models = mutableListOf<FavoritesViewModel>()
    @After fun closeModels() { models.forEach { it.viewModelScope.cancel() } }
    @Before fun freezeTime() {
        assertTrue(SystemClock.setCurrentTimeMillis(1_735_689_600_000L))
        compose.mainClock.autoAdvance = true
    }
    private fun text(value: String) = compose.onNodeWithText(value)
    private fun icon(value: String) = compose.onNodeWithContentDescription(value)

    @Test fun bothListsSendTheCorrectIdsAndHeartDoesNotOpenRecipe() {
        val removed = mutableListOf<Pair<String, Boolean>>()
        val opened = mutableListOf<String>()
        compose.setContent { FavoritesUiHost(favorite = { id, kind -> removed += id to kind }, recipe = { opened += it }) }
        text("Омлет с томатами").assertIsDisplayed().performClick()
        icon("Убрать Омлет с томатами из избранного").performClick()
        assertEquals(listOf("omelette"), opened)
        assertEquals(listOf("omelette" to false), removed)
        text("Ингредиенты").performClick().assertIsSelected()
        text("Яйца").assertIsDisplayed()
        icon("Убрать Яйца из избранных ингредиентов").performClick()
        assertEquals(listOf("omelette" to false, "eggs" to true), removed)
        assertEquals(1, opened.size)
    }

    @Test fun bothEmptyStatesAreAvailable() {
        compose.setContent { FavoritesUiHost(state = favoritesFixture(emptySet(), emptySet())) }
        text("Нет избранных блюд").assertIsDisplayed()
        text("Ингредиенты").performClick()
        text("Нет избранных ингредиентов").assertIsDisplayed()
        text("Блюда").performClick()
        text("Нет избранных блюд").assertIsDisplayed()
    }

    @Test fun pendingWriteDisablesIngredientsAndGuardsRecipeHeart() {
        val removed = mutableListOf<String>()
        compose.setContent { FavoritesUiHost(action = ActionState(pending = true), favorite = { id, _ -> removed += id }) }
        text("Сохраняем изменения…").assertIsDisplayed()
        icon("Убрать Омлет с томатами из избранного").performClick()
        text("Ингредиенты").performClick()
        icon("Указать количество: Яйца").assertIsNotEnabled()
        icon("Убрать Яйца из избранных ингредиентов").assertIsNotEnabled()
        assertTrue(removed.isEmpty())
    }

    @Test fun quantityUsesCatalogUnitValidatesAndEmitsOnlyOnce() {
        val events = mutableListOf<FavoritesIngredientSelection>()
        compose.setContent { FavoritesUiHost(selection = { events += it }) }
        text("Ингредиенты").performClick()
        icon("Указать количество: Томаты").performClick()
        text("Количество, г").performTextInput("-2")
        text("Добавить в продукты").assertIsNotEnabled()
        text("Количество, г").performTextReplacement("125,5")
        text("Добавить в продукты").assertIsEnabled().performClick()
        text("Добавить в продукты").assertDoesNotExist()
        assertEquals(listOf(FavoritesIngredientSelection("tomatoes", Quantity(125.5, QuantityUnit.GRAM))), events)
        text("Ингредиенты").assertIsSelected()
    }

    @Test fun unknownQuantityAndCancelUseTheSameCatalogIngredient() {
        val events = mutableListOf<FavoritesIngredientSelection>()
        compose.setContent { FavoritesUiHost(selection = { events += it }) }
        text("Ингредиенты").performClick()
        icon("Указать количество: Яйца").performClick()
        text("Количество, шт.").assertExists()
        text("Отмена").performClick()
        assertTrue(events.isEmpty())
        icon("Указать количество: Яйца").performClick()
        text("Добавить в продукты").performClick()
        assertEquals(listOf(FavoritesIngredientSelection("eggs", null)), events)
    }

    @Test fun currentApplicationDoesNotPretendThatPantryIsConnected() {
        compose.setContent { FavoritesUiHost() }
        text("Ингредиенты").performClick()
        icon("Указать количество: Яйца").performClick()
        text("Добавление в продукты здесь пока недоступно.").assertIsDisplayed()
        text("Добавить в продукты").assertDoesNotExist()
        text("Закрыть").performClick()
        text("Количество, шт.").assertDoesNotExist()
    }

    @Test fun backClosesQuantityWithoutSendingAnEvent() {
        val events = mutableListOf<FavoritesIngredientSelection>()
        compose.setContent { FavoritesUiHost(selection = { events += it }) }
        text("Ингредиенты").performClick()
        icon("Указать количество: Яйца").performClick()
        text("Количество, шт.").performTextInput("3")
        compose.runOnIdle { compose.activity.onBackPressedDispatcher.onBackPressed() }
        text("Добавить в продукты").assertDoesNotExist()
        text("Ингредиенты").assertIsSelected()
        assertTrue(events.isEmpty())
    }

    @Test fun tabScrollAndQuantityDraftSurviveSavedStateRestoration() {
        val catalog = DemoCatalog.catalog.copy(ingredients = (0..35).map { Ingredient("i$it", "Ингредиент $it", QuantityUnit.GRAM) })
        val state = favoritesFixture(ingredientIds = catalog.ingredients.map { it.id }.toSet(), catalog = catalog)
        val restoration = StateRestorationTester(compose)
        restoration.setContent { FavoritesUiHost(state = state, selection = {}) }
        text("Ингредиенты").performClick()
        compose.onNodeWithTag("favorites-list").performScrollToIndex(18)
        text("Ингредиент 18").assertIsDisplayed()
        text("Блюда").performClick()
        text("Омлет с томатами").assertIsDisplayed()
        text("Ингредиенты").performClick()
        text("Ингредиент 18").assertIsDisplayed()
        restoration.emulateSavedInstanceStateRestore()
        text("Ингредиенты").assertIsSelected()
        text("Ингредиент 18").assertIsDisplayed()
        icon("Указать количество: Ингредиент 18").performClick()
        text("Количество, г").performTextInput("42")
        restoration.emulateSavedInstanceStateRestore()
        text("Количество, г").assertTextContains("42")
    }

    @Test fun realViewModelShowsReadRetryWriteErrorAndSuccessfulRetry() {
        val h = FavoritesHouseholdFake(Household(favoriteRecipes = setOf("omelette"))).apply { failRead = true }
        val vm = FavoritesViewModel(DemoCatalogRepository(), h, FavoritesPreferencesFake()).also { models += it }
        compose.setContent {
            val state by vm.state.collectAsState()
            val action by vm.actions.state.collectAsState()
            AlmostReadyTheme {
                com.example.mobile_android.ui.components.LoadContent(state, vm::retry) {
                    FavoritesUiHost(it, action, vm::favorite, dismiss = vm.actions::dismiss)
                }
            }
        }
        text("Данные недоступны").assertIsDisplayed()
        compose.runOnIdle { h.failRead = false }
        text("Повторить").performClick()
        text("Омлет с томатами").assertIsDisplayed()
        compose.runOnIdle { h.failWrite = true }
        icon("Убрать Омлет с томатами из избранного").performClick()
        text("Не удалось сохранить изменения. Повторите действие.").assertIsDisplayed()
        text("Омлет с томатами").assertIsDisplayed()
        compose.runOnIdle { h.failWrite = false }
        icon("Убрать Омлет с томатами из избранного").performClick()
        text("Нет избранных блюд").assertIsDisplayed()
    }

    @Test fun realViewModelWaitsForReadAndPendingRemoval() {
        val source = kotlinx.coroutines.flow.MutableSharedFlow<Catalog>(replay = 1)
        val h = FavoritesHouseholdFake(Household(favoriteIngredients = setOf("eggs")))
        val vm = FavoritesViewModel(object : CatalogRepository { override val catalog = source }, h, FavoritesPreferencesFake()).also { models += it }
        compose.setContent {
            val state by vm.state.collectAsState()
            val action by vm.actions.state.collectAsState()
            AlmostReadyTheme {
                com.example.mobile_android.ui.components.LoadContent(state, vm::retry) {
                    FavoritesUiHost(it, action, vm::favorite)
                }
            }
        }
        compose.onNode(hasProgressBarRangeInfo(ProgressBarRangeInfo.Indeterminate)).assertExists()
        compose.runOnIdle { source.tryEmit(DemoCatalog.catalog) }
        text("Ингредиенты").performClick()
        compose.runOnIdle { h.writeGate = CompletableDeferred() }
        icon("Убрать Яйца из избранных ингредиентов").performClick()
        text("Сохраняем изменения…").assertIsDisplayed()
        icon("Убрать Яйца из избранных ингредиентов").assertIsNotEnabled()
        compose.runOnIdle { h.writeGate!!.complete(Unit) }
        text("Нет избранных ингредиентов").assertIsDisplayed()
        assertEquals(listOf("eggs" to true), h.writes)
    }

    @Test
    @Config(qualifiers = "ru-rRU-w360dp-h900dp-notnight-xhdpi")
    fun largeFontLongIngredientAndRecipeHaveAccessibleActionsAt360dp() {
        val catalog = DemoCatalog.catalog.copy(ingredients = listOf(Ingredient("long", "Очень длинное название любимого ингредиента для домашней кухни", QuantityUnit.GRAM)))
        compose.setContent { FavoritesUiHost(state = favoritesFixture(ingredientIds = setOf("long"), catalog = catalog), fontScale = 1.5f, selection = {}) }
        icon("Убрать Омлет с томатами из избранного").assertIsDisplayed()
        text("Ингредиенты").performClick().assertIsSelected()
        val tabLayout = mutableListOf<TextLayoutResult>()
        compose.onNodeWithText("Ингредиенты", useUnmergedTree = true)
            .performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(tabLayout) }
        assertEquals(1, tabLayout.single().lineCount)
        icon("Указать количество: Очень длинное название любимого ингредиента для домашней кухни").assertIsDisplayed().performClick()
        text("Количество, г").assertIsDisplayed()
        text("Добавить в продукты").assertIsDisplayed()
    }
}
