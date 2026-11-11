package com.example.mobile_android.feature.shopping

import android.app.Application
import android.net.Uri
import android.os.SystemClock
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.dropbox.differ.SimpleImageComparator
import com.example.mobile_android.data.DemoCatalogRepository
import com.example.mobile_android.domain.Household
import com.example.mobile_android.domain.Quantity
import com.example.mobile_android.domain.QuantityUnit
import com.example.mobile_android.ui.Screenshot
import com.example.mobile_android.ui.UiSmoke
import com.example.mobile_android.ui.components.LoadContent
import com.example.mobile_android.ui.theme.AlmostReadyTheme
import com.github.takahirom.roborazzi.RoborazziOptions
import com.github.takahirom.roborazzi.captureRoboImage
import java.io.File
import kotlinx.coroutines.CompletableDeferred
import org.junit.Assert.*
import org.junit.Before
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
class ShoppingLocalWiringTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val household = ShoppingUiHousehold()
    private val writer = ShoppingBudgetPlanFake(household)

    @Before
    fun freezeTime() {
        assertTrue(SystemClock.setCurrentTimeMillis(1_735_689_600_000L))
    }

    private fun launch(
        source: ShoppingBudgetSource = FakeShoppingBudgetSource(),
        connected: Boolean = true,
    ) {
        compose.setContent {
            val nav = rememberNavController()
            AlmostReadyTheme {
                Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                    NavHost(nav, startDestination = "shopping") {
                        composable("shopping") {
                            val factory = remember {
                                viewModelFactory {
                                    initializer {
                                        ShoppingViewModel(
                                            DemoCatalogRepository(),
                                            household,
                                            ShoppingUiPreferences(),
                                            SavedStateHandle(),
                                        )
                                    }
                                }
                            }
                            val vm: ShoppingViewModel = viewModel(factory = factory)
                            val state by vm.state.collectAsStateWithLifecycle()
                            val action by vm.actions.state.collectAsStateWithLifecycle()
                            LoadContent(state, vm::retry) {
                                ShoppingScreen(
                                    state = it,
                                    action = action,
                                    budget = vm::budgetChanged,
                                    toggle = vm::toggleChecked,
                                    removeRecipe = vm::removeRecipe,
                                    removeManual = vm::removeManual,
                                    checkout = vm::addBoughtToPantry,
                                    addSuggestion = vm::addSuggestion,
                                    dishes = {},
                                    dismiss = vm.actions::dismiss,
                                    openRecipe =
                                        if (connected)
                                            { id -> nav.navigate("recipe/${Uri.encode(id)}") }
                                        else null,
                                    openPantry =
                                        if (connected) ({ nav.navigate("pantry") }) else null,
                                    budgetPlanWriter = if (connected) writer else null,
                                    budgetSource = source,
                                )
                            }
                        }
                        composable(
                            "recipe/{recipeId}",
                            arguments =
                                listOf(navArgument("recipeId") { type = NavType.StringType }),
                        ) { entry ->
                            Text("Рецепт ${entry.arguments?.getString("recipeId")}")
                        }
                        composable("pantry") { Text("Продукты дома") }
                    }
                }
            }
        }
        compose.waitForIdle()
    }

    @Test
    @Category(UiSmoke::class)
    fun bothRecipeSourcesNavigateAndBackRestoresBudgetResultAndDraft() {
        launch()
        scrollTo("Омлет с сыром").performClick()
        await("Рецепт cheeseEgg")
        systemBack()
        await("Что докупить")

        openBudget()
        text("Бюджет, ₽").performTextReplacement("500,25")
        scrollTo("Подобрать план", budget = true).performClick()
        await("В пределах бюджета")
        val recipeButton = "shopping-budget-recipe-cheese"
        compose.onNodeWithTag("shopping-ui-budget").performScrollToNode(hasTestTag(recipeButton))
        compose.onNodeWithTag(recipeButton).performClick()
        await("Рецепт cheese")
        systemBack()
        compose.onNodeWithTag(recipeButton).assertIsDisplayed()
        scrollTo("Изменить бюджет", budget = true).performClick()
        text("Бюджет, ₽").assertTextContains("500,25")
        assertTrue(writer.submissions.isEmpty())
    }

    @Test
    @Category(UiSmoke::class)
    fun purchasedCanOpenPantryWithoutMovingItems() {
        launch()
        val checkbox =
            compose.onNode(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Checkbox))
        checkbox.performClick()
        await("Покупка отмечена")
        scrollTo("Мои продукты").performClick()
        await("Продукты дома")
        systemBack()
        await("Покупка отмечена")
        assertEquals(setOf("hard-cheese"), household.values.value.checkedPurchases)
        assertEquals(0, household.checkoutCalls)
        assertTrue(household.values.value.pantry.isEmpty())
    }

    @Test
    @Category(UiSmoke::class)
    fun twoPackageWriteWaitsAndFailsAtomicallyThenRetriesDeduplicatesAndUndoes() {
        household.values.value = Household()
        launch(FakeShoppingBudgetSource(twoPackageBudgetExample))
        submitBudget()
        val gate = CompletableDeferred<Unit>()
        writer.gate = gate
        writer.failAdd = true
        scrollTo("Добавить план в покупки", budget = true).performClick()
        scrollTo("Сохраняем изменения…", budget = true)
            .assertIsDisplayed()
            .assert(
                SemanticsMatcher.expectValue(SemanticsProperties.LiveRegion, LiveRegionMode.Polite)
            )
        scrollTo("Добавить план в покупки", budget = true).assertIsNotEnabled()
        compose.onNodeWithContentDescription("Назад").assertDoesNotExist()
        assertTrue(household.values.value.manualPurchases.isEmpty())
        gate.complete(Unit)
        scrollToAfterWrite("Не удалось добавить план в покупки.")
        assertTrue(household.values.value.manualPurchases.isEmpty())

        writer.failAdd = false
        scrollTo("Повторить добавление", budget = true).performClick()
        scrollToAfterWrite("План добавлен в покупки")
        val expected =
            listOf(
                ShoppingPackageSelection(
                    "hard-cheese",
                    "hard-cheese-200g",
                    Quantity(200.0, QuantityUnit.GRAM),
                    1,
                ),
                ShoppingPackageSelection(
                    "tomatoes",
                    "tomatoes-500g",
                    Quantity(500.0, QuantityUnit.GRAM),
                    1,
                ),
            )
        assertEquals(listOf(expected, expected), writer.submissions)
        assertEquals(
            setOf("hard-cheese", "tomatoes"),
            household.values.value.manualPurchases.map { it.ingredientId }.toSet(),
        )
        assertTrue(household.values.value.plan.isEmpty())
        scrollTo("Добавить план в покупки", budget = true).performClick()
        scrollToAfterWrite("План уже в покупках")
        assertEquals(2, household.values.value.manualPurchases.size)

        writer.failUndo = true
        scrollTo("Отменить", budget = true).performClick()
        scrollToAfterWrite("Не удалось отменить добавление.")
        assertEquals(2, household.values.value.manualPurchases.size)
        writer.failUndo = false
        scrollTo("Отменить", budget = true).performClick()
        scrollToAfterWrite("Добавление отменено")
        assertEquals(Household(), household.values.value)
    }

    @Test
    @Category(UiSmoke::class)
    fun writtenPlanAppearsInTheListAndUndoKeepsThePreviouslyCoveredLine() {
        household.values.value =
            household.values.value.copy(checkedPurchases = setOf("hard-cheese"))
        val before = household.values.value
        launch(FakeShoppingBudgetSource(twoPackageBudgetExample))
        submitBudget()
        scrollTo("Добавить план в покупки", budget = true).performClick()
        scrollToAfterWrite("План добавлен. Некоторые позиции уже в покупках.")
        assertEquals(setOf("hard-cheese"), household.values.value.checkedPurchases)
        compose.onNodeWithContentDescription("Назад").performClick()
        await("Сколько потратим?")
        text("Отменить").assertDoesNotExist()
        compose.onNodeWithContentDescription("Назад").performClick()
        scrollTo("Томаты").assertIsDisplayed()

        val undoGate = CompletableDeferred<Unit>()
        writer.undoGate = undoGate
        scrollTo("Отменить").performClick()
        scrollTo("Сохраняем изменения…").assertIsDisplayed()
        scrollTo("Подобрать покупки под бюджет").assertIsNotEnabled()
        undoGate.complete(Unit)
        scrollTo("Добавление отменено").assertIsDisplayed()
        await("Покупка отмечена")
        assertEquals(before, household.values.value)
    }

    @Test
    @Category(UiSmoke::class)
    fun unknownPriceDisablesWriteEvenWithConnectedHost() {
        launch(FakeShoppingBudgetSource(FakeShoppingBudgetSource.UNKNOWN_PRICE))
        submitBudget()
        await("Стоимость неизвестна")
        text("В пределах бюджета").assertDoesNotExist()
        scrollTo("Добавить план в покупки", budget = true).assertIsNotEnabled()
        assertTrue(writer.submissions.isEmpty())
    }

    @Test
    @Category(UiSmoke::class)
    fun disconnectedHostHasNoNewActions() {
        launch(connected = false)
        compose
            .onNode(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Checkbox))
            .performClick()
        scrollTo("Добавить купленное домой")
        text("Мои продукты").assertDoesNotExist()
        scrollTo("Омлет с сыром").assertHasNoClickAction()
        submitBudget()
        scrollTo("Покупки из примера не добавляются в список.", budget = true)
        text("Добавить план в покупки").assertDoesNotExist()
        compose.onNodeWithTag("shopping-budget-recipe-cheese").assertDoesNotExist()
        compose.onNodeWithTag("shopping-budget-recipe-cheeseEgg").assertDoesNotExist()
    }

    @Test
    @Category(Screenshot::class)
    fun connectedBudgetResultScreenshot() {
        launch()
        submitBudget()
        scrollTo("Добавить план в покупки", budget = true).assertIsEnabled()
        shot(compose.onNode(isDialog()), "budget-result")
    }

    @Test
    @Category(Screenshot::class)
    fun connectedPurchasedScreenshot() {
        household.values.value =
            household.values.value.copy(checkedPurchases = setOf("hard-cheese"))
        launch()
        scrollTo("Мои продукты").assertIsEnabled()
        shot(compose.onRoot(), "purchased")
    }

    private fun openBudget() {
        scrollTo(
                if (household.values.value.manualPurchases.isEmpty()) "Подобрать покупки"
                else "Подобрать покупки под бюджет"
            )
            .performClick()
    }

    private fun submitBudget() {
        openBudget()
        scrollTo("Подобрать план", budget = true).performClick()
    }

    private fun text(value: String) = compose.onNodeWithText(value)

    private fun await(value: String) {
        compose.waitUntil(10_000) {
            compose.onAllNodesWithText(value).fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun scrollTo(value: String, budget: Boolean = false): SemanticsNodeInteraction {
        compose
            .onNodeWithTag(if (budget) "shopping-ui-budget" else "shopping-ui-list")
            .performScrollToNode(hasText(value))
        return text(value)
    }

    private fun scrollToAfterWrite(value: String) {
        compose.waitForIdle()
        scrollTo(value, budget = true).assertIsDisplayed()
    }

    private fun systemBack() {
        compose.runOnIdle { compose.activity.onBackPressedDispatcher.onBackPressed() }
        compose.waitForIdle()
    }

    private fun shot(node: SemanticsNodeInteraction, name: String) {
        check(System.getProperty("os.name") == "Linux" && System.getProperty("os.arch") == "amd64")
        val file = "shopping-local-wiring-$name.png"
        if (System.getProperty("roborazzi.test.verify") == "true")
            assertTrue("Missing $file", File("src/test/screenshots/$file").isFile)
        node.captureRoboImage(
            file,
            roborazziOptions =
                RoborazziOptions(
                    compareOptions =
                        RoborazziOptions.CompareOptions(
                            changeThreshold = 0f,
                            imageComparator = SimpleImageComparator(maxDistance = 0f),
                        )
                ),
        )
    }
}
