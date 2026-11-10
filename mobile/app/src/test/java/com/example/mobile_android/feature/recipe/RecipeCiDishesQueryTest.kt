package com.example.mobile_android.feature.recipe

import android.app.Application
import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextRange
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.example.mobile_android.data.DemoCatalogRepository
import com.example.mobile_android.feature.common.ScreenState
import com.example.mobile_android.feature.dishes.DishesScreen
import com.example.mobile_android.feature.dishes.DishesView
import com.example.mobile_android.feature.dishes.DishesViewModel
import com.example.mobile_android.ui.UiSmoke
import com.example.mobile_android.ui.components.LoadContent
import com.example.mobile_android.ui.theme.AlmostReadyTheme
import java.util.concurrent.ConcurrentLinkedQueue
import kotlin.coroutines.CoroutineContext
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.cancel
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.experimental.categories.Category
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(
    sdk = [36],
    application = Application::class,
    qualifiers = "ru-rRU-w400dp-h900dp-notnight-xhdpi",
)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Category(UiSmoke::class)
class RecipeCiDishesQueryTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val calculations = ConcurrentLinkedQueue<Runnable>()
    private val dispatcher = object : CoroutineDispatcher() {
        override fun dispatch(context: CoroutineContext, block: Runnable) {
            calculations.add(block)
        }
    }

    private fun model(saved: SavedStateHandle = SavedStateHandle()) =
        DishesViewModel(
            DemoCatalogRepository(),
            RecipeUiHousehold(),
            RecipeUiPreferences(),
            saved,
            dispatcher,
        )

    @Test fun listKeepsTextAndCaretWhileResultsArePending() = checkTyping(DishesView.LIST)

    @Test fun graphKeepsTextAndCaretWhileResultsArePending() = checkTyping(DishesView.GRAPH)

    private fun checkTyping(view: DishesView) {
        val saved = SavedStateHandle()
        val vm = model(saved)
        try {
            compose.setContent {
                val state by vm.state.collectAsStateWithLifecycle()
                val action by vm.actions.state.collectAsStateWithLifecycle()
                val queryText by vm.query.collectAsStateWithLifecycle()
                AlmostReadyTheme {
                    LoadContent(state, vm::retry) {
                        DishesScreen(
                            it,
                            action,
                            false,
                            vm::queryChanged,
                            vm::availabilityChanged,
                            vm::maxMinutesChanged,
                            vm::maxKcalChanged,
                            vm::methodChanged,
                            vm::resetFilters,
                            vm::favorite,
                            {},
                            {},
                            {},
                            vm.actions::dismiss,
                            view,
                            vm::viewChanged,
                            vm::addPurchase,
                            queryText = queryText,
                        )
                    }
                }
            }
            compose.waitUntil(10_000) { calculations.isNotEmpty() }
            finishCalculations(vm)
            val field = compose.onNode(hasSetTextAction())
            val query = "нет такого блюда"
            field.performTextInput(query)
            compose.waitUntil(10_000) { calculations.isNotEmpty() }
            compose.mainClock.advanceTimeByFrame()
            field.assertTextEquals(query)
            assertSelection(field, query.length)
            compose.runOnIdle {
                assertEquals(query, vm.query.value)
                assertEquals(query, saved.get<String>("query"))
                assertEquals("", (vm.state.value as ScreenState.Ready).data.filters.query)
            }

            field.performTextInput("!")
            field.assertTextEquals("$query!")
            assertSelection(field, query.length + 1)
            finishCalculations(vm)
            compose.onNodeWithText("Подходящих блюд нет").assertExists()
            field.assertTextEquals("$query!")
            assertSelection(field, query.length + 1)

            field.performTextInputSelection(TextRange(4))
            field.performTextInput("X")
            val edited = query.take(4) + "X" + query.drop(4) + "!"
            field.assertTextEquals(edited)
            assertSelection(field, 5)
            finishCalculations(vm)
            field.assertTextEquals(edited)
            assertSelection(field, 5)
            compose.runOnIdle {
                assertEquals(edited, (vm.state.value as ScreenState.Ready).data.filters.query)
                vm.resetFilters()
            }
            field.assert(SemanticsMatcher.expectValue(SemanticsProperties.EditableText, AnnotatedString("")))
            assertSelection(field, 0)
            finishCalculations(vm)
            compose.runOnIdle {
                assertEquals("", (vm.state.value as ScreenState.Ready).data.filters.query)
            }
        } finally {
            vm.viewModelScope.cancel()
        }
    }

    @Test fun queryRestoresAndResetsWithoutWaitingForResults() {
        val saved = SavedStateHandle(mapOf("query" to "омлет"))
        val vm = model(saved)
        try {
            assertEquals("омлет", vm.query.value)
            assertEquals(ScreenState.Loading, vm.state.value)
            vm.queryChanged("сыр")
            assertEquals("сыр", vm.query.value)
            assertEquals("сыр", saved.get<String>("query"))
            vm.queryChanged("x".repeat(101))
            assertEquals("x".repeat(100), vm.query.value)
            vm.resetFilters()
            assertEquals("", vm.query.value)
            assertEquals(ScreenState.Loading, vm.state.value)
        } finally {
            vm.viewModelScope.cancel()
        }
    }

    private fun finishCalculations(vm: DishesViewModel) {
        compose.waitUntil(10_000) {
            compose.runOnIdle {
                while (calculations.isNotEmpty()) calculations.poll()?.run()
            }
            val data = (vm.state.value as? ScreenState.Ready)?.data
            calculations.isEmpty() && data?.filters?.query == vm.query.value
        }
        compose.waitForIdle()
    }

    private fun assertSelection(field: SemanticsNodeInteraction, position: Int) {
        assertEquals(
            TextRange(position),
            field.fetchSemanticsNode().config[SemanticsProperties.TextSelectionRange],
        )
    }
}
