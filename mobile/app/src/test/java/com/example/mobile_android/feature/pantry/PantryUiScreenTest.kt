package com.example.mobile_android.feature.pantry

import android.app.Application
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.SystemClock
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.*
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.Density
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.viewModelScope
import com.dropbox.differ.SimpleImageComparator
import com.example.mobile_android.app.LocalFeatureDependencies
import com.example.mobile_android.data.DemoCatalog
import com.example.mobile_android.data.DemoCatalogRepository
import com.example.mobile_android.domain.*
import com.example.mobile_android.navigation.AppRoot
import com.example.mobile_android.ui.Screenshot
import com.example.mobile_android.ui.UiSmoke
import com.example.mobile_android.ui.components.BrandTopBar
import com.example.mobile_android.ui.components.LoadContent
import com.example.mobile_android.ui.theme.AlmostReadyTheme
import com.github.takahirom.roborazzi.RoborazziOptions
import com.github.takahirom.roborazzi.captureRoboImage
import com.example.mobile_android.ui.FakeYandexLogin
import java.io.File
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.flowOf
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
import org.robolectric.shadows.ShadowDialog

@RunWith(RobolectricTestRunner::class)
@Config(
    sdk = [36],
    application = Application::class,
    qualifiers = "ru-rRU-w400dp-h900dp-notnight-xhdpi",
)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class PantryUiScreenTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val household = PantryUiHousehold()
    private lateinit var vm: PantryViewModel
    private var catalogData = DemoCatalog.catalog
    private var dishes = 0
    private var receipts = 0

    @Before
    fun setup() {
        assertTrue(SystemClock.setCurrentTimeMillis(1_735_689_600_000L))
        compose.mainClock.autoAdvance = true
    }

    @After
    fun cleanup() {
        if (::vm.isInitialized) vm.viewModelScope.cancel()
    }

    private fun launch(
        fontScale: Float = 1f,
        restoration: StateRestorationTester? = null,
        appHost: Boolean = false,
    ) {
        vm =
            PantryViewModel(
                object : CatalogRepository {
                    override val catalog = flowOf(catalogData)
                },
                household,
                SavedStateHandle(),
            )
        val content: @Composable () -> Unit = {
            CompositionLocalProvider(LocalDensity provides Density(2f, fontScale)) {
                AlmostReadyTheme {
                    if (appHost) {
                        AppRoot(PantryUiAppDependencies(household))
                    } else {
                        val state by vm.state.collectAsState()
                        val action by vm.actions.state.collectAsState()
                        val deleted by vm.deleted.collectAsState()
                        Scaffold(topBar = { BrandTopBar() }) { padding ->
                            Box(Modifier.fillMaxSize().padding(padding)) {
                                LoadContent(state, vm::retry) { data ->
                                    PantryScreen(
                                        data,
                                        action,
                                        deleted,
                                        vm::queryChanged,
                                        vm::add,
                                        vm::edit,
                                        vm::remove,
                                        vm::undoDelete,
                                        vm::favorite,
                                        vm.actions::dismiss,
                                        { dishes++ },
                                        { receipts++ },
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
        if (restoration == null) compose.setContent(content) else restoration.setContent(content)
        compose.waitForIdle()
    }

    private fun text(value: String) = compose.onNodeWithText(value)

    private fun search(query: String = "том", ingredientName: String = "Томаты") {
        compose.onNodeWithContentDescription("Добавить продукт").performTextInput(query)
        compose.onNodeWithContentDescription("Выбрать $ingredientName").performClick()
    }

    private fun amount() = text("Количество, г")

    private fun awaitText(value: String) {
        compose.waitUntil(10_000) {
            compose.onAllNodesWithText(value).fetchSemanticsNodes().isNotEmpty()
        }
        text(value).assertIsDisplayed()
    }

    @Test
    @Category(UiSmoke::class)
    fun canonicalAddAndEditAreDistinctAndCallbacksStillWork() {
        launch()
        compose.runOnIdle { household.failWrite = true }
        compose
            .onNodeWithContentDescription("Избранный ингредиент: Томаты")
            .performScrollTo()
            .performClick()
        compose.runOnIdle { household.failWrite = false }
        search()
        amount().performTextInput("200")
        text("Станет дома: 700 г").performScrollTo().assertIsDisplayed()
        text("Добавить к продуктам").performScrollTo().performClick()
        awaitText("700 г")
        compose.onAllNodesWithText("Томаты").assertCountEquals(1)
        compose
            .onNodeWithContentDescription("Изменить количество: Томаты")
            .performScrollTo()
            .performClick()
        amount().performTextReplacement("123")
        text("Сохранить").performScrollTo().performClick()
        awaitText("123 г")
        assertEquals(listOf("add:tomatoes", "set:tomatoes"), household.calls.map { it.first })
        assertEquals(1, household.values.value.pantry.count { it.ingredientId == "tomatoes" })
        text("Подобрать блюда").assertIsDisplayed().performClick()
        assertEquals(1, dishes)
        compose
            .onNodeWithContentDescription("Добавить по фото чека")
            .performScrollTo()
            .performClick()
        assertEquals(1, receipts)
        search("сыр", "Твёрдый сыр")
        amount().performTextInput("200")
        text("Добавить к продуктам").performScrollTo().performClick()
        compose.onNode(hasScrollToIndexAction()).performScrollToNode(hasText("Твёрдый сыр"))
        compose.onNodeWithContentDescription("Изменить количество: Твёрдый сыр").assertIsDisplayed()
        assertEquals(
            "add:hard-cheese" to Quantity(200.0, QuantityUnit.GRAM),
            household.calls.last(),
        )
    }

    @Test
    @Category(UiSmoke::class)
    fun failureKeepsDraftAndRetryWaitsWithoutDuplicateWrites() {
        household.failWrite = true
        launch()
        search()
        amount().performTextInput("200")
        text("Добавить к продуктам").performScrollTo().performClick()
        awaitText("Повторить сохранение")
        amount().assertTextContains("200")
        compose.runOnIdle {
            household.failWrite = false
            household.gate = CompletableDeferred()
        }
        text("Повторить сохранение").performScrollTo().performClick()
        text("Сохранение…").assertIsNotEnabled().performClick()
        assertEquals(2, household.calls.size)
        compose.runOnIdle { household.gate!!.complete(Unit) }
        awaitText("700 г")
    }

    @Test
    @Category(UiSmoke::class)
    fun cancelAndBackNeverWriteAndSearchCanBeCleared() {
        launch()
        search()
        amount().performTextInput("999")
        text("Отмена").performScrollTo().performClick()
        assertTrue(household.calls.isEmpty())
        compose.onNodeWithContentDescription("Очистить поиск").performClick()
        compose.onNodeWithContentDescription("Добавить продукт").performTextInput("нет такого")
        text("Ничего не найдено").assertIsDisplayed()
        compose.runOnIdle { ShadowDialog.getShownDialogs().last { it.isShowing }.onBackPressed() }
        text("Мои продукты").assertIsDisplayed()
        compose
            .onNodeWithContentDescription("Изменить количество: Томаты")
            .performScrollTo()
            .performClick()
        compose.runOnIdle { ShadowDialog.getShownDialogs().last { it.isShowing }.onBackPressed() }
        compose.waitForIdle()
        text("Количество, г").assertDoesNotExist()
        assertTrue(household.calls.isEmpty())
    }

    @Test
    @Category(UiSmoke::class)
    fun readFailureRetriesAndQuantityDraftSurvivesRestoration() {
        household.failRead = true
        val restoration = StateRestorationTester(compose)
        launch(restoration = restoration)
        text("Данные недоступны").assertIsDisplayed()
        compose.runOnIdle { household.failRead = false }
        text("Повторить").performClick()
        search()
        amount().performTextInput("12,5")
        restoration.emulateSavedInstanceStateRestore()
        amount().assertTextContains("12,5")
        text("Отмена").performScrollTo().performClick()
        assertTrue(household.calls.isEmpty())
    }

    @Test
    @Category(UiSmoke::class)
    fun processRecreationDuringWriteRestoresEditableDraft() {
        val restoration = StateRestorationTester(compose)
        household.gate = CompletableDeferred()
        launch(restoration = restoration)
        search()
        amount().performTextInput("200")
        text("Добавить к продуктам").performScrollTo().performClick()
        text("Сохранение…").assertIsNotEnabled()
        compose.runOnIdle {
            vm.viewModelScope.cancel()
            vm =
                PantryViewModel(
                    DemoCatalogRepository(),
                    household,
                    SavedStateHandle(mapOf("query" to "том")),
                )
            household.gate = null
        }
        restoration.emulateSavedInstanceStateRestore()
        amount().assertTextContains("200").assertIsEnabled()
        text("Добавить к продуктам").performScrollTo().assertIsEnabled().performClick()
        awaitText("700 г")
    }

    @Test
    @Category(UiSmoke::class)
    fun emptyPantryKeepsReceiptAndDishesCallbacks() {
        household.values.value = Household()
        launch()
        text("Пока нет продуктов").assertIsDisplayed()
        text("Подобрать блюда").assertIsDisplayed().performClick()
        text("Добавить по фото чека").performScrollTo().performClick()
        assertEquals(1, dishes)
        assertEquals(1, receipts)
        text("Добавить продукты").performScrollTo().performClick()
        compose.onNodeWithContentDescription("Добавить продукт").assertIsFocused()
        compose
            .onNodeWithContentDescription("Выбрать Томаты")
            .performScrollTo()
            .assertHasClickAction()
    }

    @Test
    @Category(UiSmoke::class)
    fun deletionAndFailedUndoRemainRecoverable() {
        launch()
        compose
            .onNodeWithContentDescription("Изменить количество: Томаты")
            .performScrollTo()
            .performClick()
        text("Удалить томаты").performScrollTo().performClick()
        awaitText("Отменить удаление")
        compose.runOnIdle { household.failWrite = true }
        text("Отменить удаление").performScrollTo().performClick()
        text("Отменить удаление").assertIsEnabled()
        compose.runOnIdle { household.failWrite = false }
        text("Отменить удаление").performClick()
        compose
            .onNodeWithContentDescription("Изменить количество: Томаты")
            .performScrollTo()
            .assertIsDisplayed()
    }

    @Test
    @Category(UiSmoke::class)
    @Config(qualifiers = "ru-rRU-w360dp-h800dp-notnight-xhdpi")
    fun narrowLargeFontLongListAndKeyboardActionsRemainUsable() {
        val longName = "Очень длинное название продукта для проверки доступности"
        val extra = (1..40).map { Ingredient("long-$it", "$longName $it", QuantityUnit.GRAM) }
        catalogData = catalogData.copy(ingredients = catalogData.ingredients + extra)
        household.values.value =
            household.values.value.copy(
                pantry = DemoCatalog.initialPantry + extra.map { PantryItem(it.id, null) }
            )
        launch(1.5f)
        text("Подобрать блюда").assertIsDisplayed()
        compose.onNode(hasScrollToIndexAction()).performScrollToNode(hasText("$longName 40"))
        text("$longName 40").assertIsDisplayed()
        text("Подобрать блюда").assertIsDisplayed()
        compose
            .onNode(hasScrollToIndexAction())
            .performScrollToNode(hasContentDescription("Изменить количество: Томаты"))
        compose.onNodeWithContentDescription("Изменить количество: Томаты").performClick()
        amount().performTextReplacement("12,5")
        amount().performImeAction()
        text("Сохранить").performScrollTo().assertIsDisplayed().performClick()
        assertEquals(12.5, household.calls.single().second!!.value, 0.0)
    }

    @Test
    @Category(UiSmoke::class)
    fun explicitUnknownAndCatalogUnitsDoNotInventConversions() {
        launch()
        compose
            .onNodeWithContentDescription("Изменить количество: Молоко")
            .performScrollTo()
            .performClick()
        text("Количество, мл").assert(hasSetTextAction())
        text("Количество неизвестно").performScrollTo().performClick()
        text("Сохранить").performScrollTo().performClick()
        compose.waitForIdle()
        assertEquals("set:milk", household.calls.single().first)
        assertNull(household.calls.single().second)
        compose
            .onNodeWithContentDescription("Изменить количество: Яйца")
            .performScrollTo()
            .performClick()
        text("Количество, шт.").performTextReplacement("-5")
        text("Сохранить").performScrollTo().assertIsNotEnabled()
        text("Количество, шт.").performTextReplacement("3")
        text("Сохранить").performScrollTo().performClick()
        compose.waitForIdle()
        assertEquals(Quantity(3.0, QuantityUnit.PIECE), household.calls.last().second)
    }

    @Test
    @Category(Screenshot::class)
    fun productsScreenshot() {
        launch(appHost = true)
        capture("products")
    }

    @Test
    @Category(Screenshot::class)
    fun productsLargeFontScreenshot() {
        launch(1.5f, appHost = true)
        capture("products-large-font")
    }

    @Test
    @Category(Screenshot::class)
    fun searchScreenshot() {
        launch(appHost = true)
        compose.onNodeWithContentDescription("Добавить продукт").performTextInput("том")
        capture("search", sheet = true)
    }

    @Test
    @Category(Screenshot::class)
    fun quantityScreenshot() {
        launch(appHost = true)
        search()
        amount().performTextInput("200")
        capture("quantity", sheet = true)
    }

    @Test
    @Category(Screenshot::class)
    fun emptyScreenshot() {
        household.values.value = Household()
        launch(appHost = true)
        capture("empty")
    }

    private fun capture(suffix: String, sheet: Boolean = false) {
        check(System.getProperty("os.name") == "Linux" && System.getProperty("os.arch") == "amd64")
        compose.waitForIdle()
        val name = "pantry-ui-$suffix.png"
        if (System.getProperty("roborazzi.test.verify") == "true")
            assertTrue(File("src/test/screenshots/$name").isFile)
        val options =
            RoborazziOptions(
                compareOptions =
                    RoborazziOptions.CompareOptions(
                        changeThreshold = 0f,
                        imageComparator = SimpleImageComparator(maxDistance = 0f),
                    )
            )
        if (suffix == "quantity") {
            amount().assertTextContains("200")
            // Render nested dialog windows explicitly; the library reverses equal-type roots.
            val combined =
                compose.runOnIdle {
                    val dialogs = ShadowDialog.getShownDialogs().filter { it.isShowing }
                    assertEquals(2, dialogs.size)
                    val background = checkNotNull(dialogs.first().window).decorView
                    val foreground = checkNotNull(dialogs.last().window).decorView
                    Bitmap.createBitmap(
                            background.width,
                            background.height,
                            Bitmap.Config.ARGB_8888,
                        )
                        .also { bitmap ->
                            Canvas(bitmap).apply {
                                background.draw(this)
                                foreground.draw(this)
                            }
                        }
                }
            combined.captureRoboImage(name, roborazziOptions = options)
        } else {
            val root = if (sheet) compose.onAllNodes(isRoot()).onLast() else compose.onRoot()
            root.captureRoboImage(name, roborazziOptions = options)
        }
    }
}

private class PantryUiAppDependencies(override val household: PantryUiHousehold) : LocalFeatureDependencies {
    override val yandexLogin = FakeYandexLogin()
    override val catalog = DemoCatalogRepository()
    override val preferences =
        object : PreferencesRepository {
            override val preferences = flowOf(FoodPreferences())

            override suspend fun update(transform: (FoodPreferences) -> FoodPreferences) =
                error("unused")
        }
    override val session =
        object : SessionRepository {
            override val sessionKey = flowOf("test-session")


            override suspend fun signInWithToken(token: String) = error("unused")

            override suspend fun signOut() = error("unused")
        }
}
