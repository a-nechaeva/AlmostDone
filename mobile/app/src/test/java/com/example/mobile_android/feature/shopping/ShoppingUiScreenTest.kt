package com.example.mobile_android.feature.shopping

import android.app.Application
import android.os.SystemClock
import androidx.activity.ComponentActivity
import androidx.compose.material3.Surface
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.Density
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.viewModelScope
import com.dropbox.differ.SimpleImageComparator
import com.example.mobile_android.data.DemoCatalog
import com.example.mobile_android.data.DemoCatalogRepository
import com.example.mobile_android.domain.*
import com.example.mobile_android.feature.common.*
import com.example.mobile_android.ui.Screenshot
import com.example.mobile_android.ui.UiSmoke
import com.example.mobile_android.ui.components.LoadContent
import com.example.mobile_android.ui.theme.AlmostReadyTheme
import com.github.takahirom.roborazzi.RoborazziOptions
import com.github.takahirom.roborazzi.captureRoboImage
import java.io.File
import java.io.IOException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.cancel
import org.junit.After
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
class ShoppingUiScreenTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val household = ShoppingUiHousehold()
    private lateinit var shopping: ShoppingViewModel
    private var budgetVm: ShoppingBudgetViewModel? = null

    @Before
    fun freezeTime() {
        assertTrue(SystemClock.setCurrentTimeMillis(1_735_689_600_000L))
        compose.mainClock.autoAdvance = true
    }

    @After
    fun close() {
        if (::shopping.isInitialized) shopping.viewModelScope.cancel()
        budgetVm?.viewModelScope?.cancel()
    }

    private fun launch(
        scale: Float = 1f,
        longName: Boolean = false,
        connectExamples: Boolean = false,
    ) {
        compose.setContent {
            val catalog =
                if (longName)
                    object : CatalogRepository {
                        override val catalog =
                            kotlinx.coroutines.flow.flowOf(
                                DemoCatalog.catalog.copy(
                                    ingredients =
                                        DemoCatalog.catalog.ingredients.map {
                                            if (it.id == "hard-cheese")
                                                it.copy(
                                                    name =
                                                        "Твёрдый сыр с очень длинным названием и подробным описанием упаковки",
                                                )
                                            else it
                                        },
                                ),
                            )
                    }
                else DemoCatalogRepository()
            val vm = remember {
                ShoppingViewModel(catalog, household, ShoppingUiPreferences(), SavedStateHandle())
            }
                .also { shopping = it }
            val owner = rememberCoroutineScope()
            val exampleActions = remember { ScreenActions(owner) }
            val exampleAction by exampleActions.state.collectAsState()
            var openedRecipe by remember { mutableStateOf<String?>(null) }
            val state by vm.state.collectAsState()
            val action by vm.actions.state.collectAsState()
            CompositionLocalProvider(LocalDensity provides Density(2f, scale)) {
                AlmostReadyTheme {
                    Surface {
                        LoadContent(state, vm::retry) {
                            ShoppingScreen(
                                it,
                                if (exampleAction.pending || exampleAction.message != null)
                                    exampleAction
                                else action,
                                vm::budgetChanged,
                                vm::toggleChecked,
                                vm::removeRecipe,
                                vm::removeManual,
                                vm::addBoughtToPantry,
                                vm::addSuggestion,
                                {},
                                {
                                    vm.actions.dismiss()
                                    exampleActions.dismiss()
                                },
                                openRecipe =
                                    if (connectExamples) { id -> openedRecipe = id } else null,
                                addBudgetExample =
                                    if (connectExamples)
                                        { example ->
                                            exampleActions.run("Пример добавлен") {
                                                example.packages.forEach { pack ->
                                                    household.addManualPurchase(
                                                        pack.ingredientId,
                                                        pack.quantity,
                                                    )
                                                }
                                            }
                                        }
                                    else null,
                            )
                        }
                        openedRecipe?.let { androidx.compose.material3.Text("Открыт рецепт: $it") }
                    }
                }
            }
        }
        compose.waitForIdle()
    }

    private fun text(value: String) = compose.onNodeWithText(value)

    private fun checkbox() =
        compose.onNode(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Checkbox))

    private fun await(value: String) {
        compose.waitUntil(10000) {
            compose.onAllNodesWithText(value).fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun openBudget() {
        text("Подобрать покупки под бюджет").performScrollTo().performClick()
        await("Сколько потратим?")
    }

    private fun launchBudget(source: ShoppingBudgetSource, scale: Float = 1f) {
        compose.setContent {
            val vm = remember {
                ShoppingBudgetViewModel(SavedStateHandle(), source)
            }
                .also { budgetVm = it }
            val form by vm.form.collectAsState()
            CompositionLocalProvider(LocalDensity provides Density(2f, scale)) {
                AlmostReadyTheme {
                    Surface {
                        ShoppingBudgetContent(
                            form,
                            DemoCatalog.catalog,
                            vm::textChanged,
                            vm::submit,
                            vm::retry,
                            vm::clearResult,
                        )
                    }
                }
            }
        }
        compose.waitForIdle()
    }

    @Category(UiSmoke::class)
    @Test
    fun checkUncheckAndExplicitCheckoutStaySeparate() {
        launch()
        checkbox().performClick()
        await("Покупка отмечена")
        assertEquals(0, household.checkoutCalls)
        assertTrue(household.values.value.pantry.isEmpty())
        text("Вернуть в список").performScrollTo().performClick()
        await("Что докупить")
        assertTrue(household.values.value.checkedPurchases.isEmpty())
        checkbox().performScrollTo().performClick()
        text("Добавить купленное домой").performScrollTo().performClick()
        compose.runOnIdle { assertEquals(1, household.checkoutCalls) }
    }

    @Category(UiSmoke::class)
    @Test
    fun pendingWriteAndErrorCanBeRetried() {
        val gate = CompletableDeferred<Unit>()
        household.writeGate = gate
        launch()
        checkbox().performClick()
        checkbox().assertIsNotEnabled()
        assertFalse(household.values.value.checkedPurchases.contains("hard-cheese"))
        household.failWrite = true
        gate.complete(Unit)
        await("Не удалось сохранить изменения. Повторите действие.")
        household.failWrite = false
        household.writeGate = null
        checkbox().performClick()
        await("Покупка отмечена")
    }

    @Category(UiSmoke::class)
    @Test
    fun readErrorRetryCanYieldEmptyAndOpenBudget() {
        household.failRead = true
        launch()
        await("Данные недоступны")
        household.failRead = false
        household.values.value = Household()
        text("Повторить").performClick()
        await("Список пока пуст")
        text("Подобрать покупки").performScrollTo().performClick()
        await("Сколько потратим?")
    }

    @Category(UiSmoke::class)
    @Test
    fun budgetValidationResultAndSystemBackPreserveDraft() {
        launch()
        openBudget()
        text("Бюджет, ₽").performTextReplacement("-5")
        text("Подобрать план").performScrollTo().assertIsNotEnabled()
        text("Бюджет, ₽").performTextReplacement("500,25")
        text("Подобрать план").performScrollTo().performClick()
        await("В пределах демо-бюджета")
        compose.runOnIdle { compose.activity.onBackPressedDispatcher.onBackPressed() }
        await("Сколько потратим?")
        text("Бюджет, ₽").assertTextContains("500,25")
        compose.runOnIdle { compose.activity.onBackPressedDispatcher.onBackPressed() }
        await("Что докупить")
        assertTrue(household.values.value.checkedPurchases.isEmpty())
    }

    @Category(UiSmoke::class)
    @Test
    fun budgetEmptyErrorAndRetryUseRealStateMachine() {
        var fail = true
        launchBudget(ShoppingBudgetSource { if (fail) throw IOException("test") else null })
        text("Подобрать план").performScrollTo().performClick()
        await("План недоступен")
        fail = false
        text("Повторить").performScrollTo().performClick()
        await("Пока нет подходящего плана")
        text("Изменить бюджет").performScrollTo().performClick()
        await("Сколько потратим?")
    }

    @Category(UiSmoke::class)
    @Test
    fun optionalRecipeCallbackReceivesTheExistingRecipeId() {
        launch(connectExamples = true)
        openBudget()
        text("Подобрать план").performScrollTo().performClick()
        await("В пределах демо-бюджета")
        compose.onAllNodesWithText("Открыть рецепт")[0].performScrollTo().performClick()
        await("Открыт рецепт: cheese")
    }

    @Category(UiSmoke::class)
    @Test
    fun unknownPriceNeverConfirmsBudget() {
        launchBudget(FakeShoppingBudgetSource(FakeShoppingBudgetSource.UNKNOWN_PRICE))
        text("Подобрать план").performScrollTo().performClick()
        await("Стоимость неизвестна")
        text("В пределах демо-бюджета").assertDoesNotExist()
        text("Покупки из примера не добавляются в список.").performScrollTo().assertIsDisplayed()
        text("Добавить план в покупки").assertDoesNotExist()
    }

    @Category(UiSmoke::class)
    @Test
    @Config(qualifiers = "ru-rRU-w360dp-h900dp-notnight-xhdpi")
    fun largeFontLongLabelsRemainScrollableAndClickable() {
        launch(1.5f, true)
        checkbox().performClick()
        await("Покупка отмечена")
        text("Подобрать покупки под бюджет").performScrollTo().assertIsDisplayed().performClick()
        await("Сколько потратим?")
        text("Подобрать план").performScrollTo().assertIsDisplayed().performClick()
        await("В пределах демо-бюджета")
    }

    @Category(UiSmoke::class)
    @Test
    fun optionalPlanCallbackUsesSharedFakeAndCanRetryWithoutDuplicates() {
        household.values.value = Household()
        launch(connectExamples = true)
        text("Подобрать покупки").performScrollTo().performClick()
        await("Сколько потратим?")
        text("Подобрать план").performScrollTo().performClick()
        await("В пределах демо-бюджета")
        household.failWrite = true
        text("Добавить план в покупки").performScrollTo().performClick()
        await("Не удалось сохранить изменения. Повторите действие.")
        assertTrue(household.values.value.manualPurchases.isEmpty())
        household.failWrite = false
        text("Добавить план в покупки").performScrollTo().performClick()
        await("Пример добавлен")
        text("Добавить план в покупки").performScrollTo().performClick()
        compose.runOnIdle {
            assertEquals(1, household.values.value.manualPurchases.size)
            assertTrue(household.values.value.pantry.isEmpty())
        }
    }

    @Category(Screenshot::class)
    @Test
    fun listScreenshot() {
        launch()
        shot("list")
    }

    @Category(Screenshot::class)
    @Test
    fun checkedScreenshot() {
        household.values.value =
            household.values.value.copy(checkedPurchases = setOf("hard-cheese"))
        launch()
        shot("checked")
    }

    @Category(Screenshot::class)
    @Test
    fun emptyScreenshot() {
        household.values.value = Household()
        launch()
        shot("empty")
    }

    @Category(Screenshot::class)
    @Test
    fun budgetScreenshot() {
        launchBudget(FakeShoppingBudgetSource())
        shot("budget")
    }

    @Category(Screenshot::class)
    @Test
    fun resultScreenshot() {
        launchBudget(FakeShoppingBudgetSource())
        text("Подобрать план").performScrollTo().performClick()
        await("В пределах демо-бюджета")
        shot("result")
    }

    @Category(Screenshot::class)
    @Test
    fun noPlanScreenshot() {
        launchBudget(FakeShoppingBudgetSource(null))
        text("Подобрать план").performScrollTo().performClick()
        await("Пока нет подходящего плана")
        shot("no-plan")
    }

    @Category(Screenshot::class)
    @Test
    fun unknownScreenshot() {
        launchBudget(FakeShoppingBudgetSource(FakeShoppingBudgetSource.UNKNOWN_PRICE))
        text("Подобрать план").performScrollTo().performClick()
        await("Стоимость неизвестна")
        shot("unknown")
    }

    @Category(Screenshot::class)
    @Test
    @Config(qualifiers = "ru-rRU-w360dp-h900dp-notnight-xhdpi")
    fun largeFontScreenshot() {
        launch(1.5f, true)
        shot("large-font")
    }

    @Category(Screenshot::class)
    @Test
    fun loadingScreenshot() {
        launchBudget(ShoppingBudgetSource { kotlinx.coroutines.awaitCancellation() })
        text("Подобрать план").performScrollTo().performClick()
        await("Загружаем демонстрационный план…")
        shot("loading")
    }

    @Category(Screenshot::class)
    @Test
    fun errorScreenshot() {
        launchBudget(ShoppingBudgetSource { throw IOException("test") })
        text("Подобрать план").performScrollTo().performClick()
        await("План недоступен")
        shot("error")
    }

    private fun shot(name: String) {
        check(System.getProperty("os.name") == "Linux" && System.getProperty("os.arch") == "amd64")
        compose.waitForIdle()
        val file = "shopping-ui-$name.png"
        if (System.getProperty("roborazzi.test.verify") == "true")
            assertTrue("Missing $file", File("src/test/screenshots/$file").isFile)
        compose
            .onRoot()
            .captureRoboImage(
                file,
                roborazziOptions =
                    RoborazziOptions(
                        compareOptions =
                            RoborazziOptions.CompareOptions(
                                changeThreshold = 0f,
                                imageComparator = SimpleImageComparator(maxDistance = 0f),
                            ),
                    ),
            )
    }
}
