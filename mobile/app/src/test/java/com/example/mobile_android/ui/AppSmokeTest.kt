package com.example.mobile_android.ui

import android.app.Application
import android.os.SystemClock
import androidx.activity.ComponentActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.Density
import com.dropbox.differ.SimpleImageComparator
import com.example.mobile_android.app.AppDependencies
import com.example.mobile_android.data.DemoCatalog
import com.example.mobile_android.domain.*
import com.example.mobile_android.feature.FakeHousehold
import com.example.mobile_android.feature.FakePreferences
import com.example.mobile_android.navigation.AppRoot
import com.example.mobile_android.ui.theme.AlmostReadyTheme
import com.github.takahirom.roborazzi.RoborazziOptions
import com.yandex.authsdk.YandexAuthOptions
import com.yandex.authsdk.YandexAuthSdk
import com.github.takahirom.roborazzi.captureRoboImage
import java.io.File
import kotlinx.coroutines.flow.*
import org.junit.Assert.*
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.experimental.categories.Category
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(
    sdk = [36],
    application = Application::class,
    qualifiers = "ru-rRU-w400dp-h900dp-notnight-xhdpi",
)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class AppSmokeTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val dependencies = SmokeDependencies()

    @Before
    fun freezeTime() {
        assertTrue(SystemClock.setCurrentTimeMillis(1_735_689_600_000L))
        assertEquals(1_735_689_600_000L, SystemClock.uptimeMillis())
        compose.mainClock.autoAdvance = true
    }

    private fun launch(fontScale: Float = 1f) {
        compose.setContent {
            CompositionLocalProvider(LocalDensity provides Density(2f, fontScale)) {
                AlmostReadyTheme { AppRoot(dependencies) }
            }
        }
    }

    private fun text(value: String) = compose.onNodeWithText(value)

    private fun dishText(value: String): SemanticsNodeInteraction {
        compose.onNodeWithTag("dishes-results").performScrollToNode(hasText(value))
        return text(value)
    }

    private fun awaitText(value: String) {
        compose.waitUntil(10_000) {
            compose.onAllNodesWithText(value).fetchSemanticsNodes().isNotEmpty()
        }
        text(value).assertIsDisplayed()
    }

    private fun tab(value: String) =
        compose.onNode(
            hasText(value) and SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Tab)
        )

    @Category(UiSmoke::class)
    @Test
    fun demoLoginPantryDishesRecipeAndBack() {
        dependencies.session.value.value = false
        launch()
        awaitText("Войти в демо")
        text("Логин").assert(hasSetTextAction()).performTextInput("demo")
        text("Пароль").assert(hasSetTextAction()).performTextInput("demo")
        text("Войти в демо").assertHasClickAction().performClick()
        awaitText("Мои продукты")
        text("Добавить продукт").assert(hasSetTextAction())
        compose.onNodeWithContentDescription("Добавить по фото чека").assertHasClickAction()
        text("Подобрать блюда").performScrollTo().assertHasClickAction().performClick()
        awaitText("Что приготовим?")
        compose.onNodeWithContentDescription("Открыть фильтры").assertHasClickAction()
        text("Омлет с томатами").performScrollTo().performClick()
        awaitText("Рецепт")
        awaitText("Омлет с томатами")
        compose.onNodeWithContentDescription("Назад").assertHasClickAction().performClick()
        awaitText("Что приготовим?")
        compose.runOnIdle { compose.activity.onBackPressedDispatcher.onBackPressed() }
        awaitText("Мои продукты")
        assertTrue(dependencies.session.value.value)
    }

    @Category(UiSmoke::class)
    @Test
    fun loadingBecomesContentWhenFakeEmits() {
        dependencies.catalogSource = MutableSharedFlow(replay = 1)
        launch()
        compose.onNode(hasProgressBarRangeInfo(ProgressBarRangeInfo.Indeterminate)).assertExists()
        dependencies.catalogSource.tryEmit(DemoCatalog.catalog)
        awaitText("Мои продукты")
        compose
            .onNode(hasProgressBarRangeInfo(ProgressBarRangeInfo.Indeterminate))
            .assertDoesNotExist()
    }

    @Category(UiSmoke::class)
    @Test
    fun emptyPantryCanOpenEmptySearchAndResetIt() {
        dependencies.household.values.value = Household()
        launch()
        awaitText("Пока нет продуктов")
        text("Подобрать блюда").performScrollTo().performClick()
        awaitText("Что приготовим?")
        text("Найти блюдо").performTextInput("несуществующее блюдо")
        awaitText("Подходящих блюд нет")
        text("Сбросить фильтры").performScrollTo().assertHasClickAction().performClick()
        compose.waitUntil(10_000) {
            compose.onAllNodesWithText("Подходящих блюд нет").fetchSemanticsNodes().isEmpty()
        }
        tab("Продукты").assertHasClickAction().performClick()
        awaitText("Пока нет продуктов")
    }

    @Category(UiSmoke::class)
    @Test
    fun readErrorRetryAndFailedWriteUseRealViewModels() {
        dependencies.household.failRead = true
        launch()
        awaitText("Данные недоступны")
        dependencies.household.failRead = false
        text("Повторить").assertHasClickAction().performClick()
        awaitText("Мои продукты")
        dependencies.household.failWrite = true
        compose.onNodeWithContentDescription("Удалить Яйца").performScrollTo().performClick()
        awaitText("Не удалось сохранить изменения. Повторите действие.")
        assertTrue(dependencies.household.values.value.pantry.any { it.ingredientId == "eggs" })
        dependencies.household.failWrite = false
        compose.onNodeWithContentDescription("Удалить Яйца").performScrollTo().performClick()
        compose.waitUntil(10_000) {
            dependencies.household.values.value.pantry.none { it.ingredientId == "eggs" }
        }
        text("Отменить удаление").performScrollTo().performClick()
        compose.waitUntil(10_000) {
            dependencies.household.values.value.pantry.any { it.ingredientId == "eggs" }
        }
    }

    private fun openGraph(fontScale: Float = 1f) {
        launch(fontScale)
        awaitText("Мои продукты")
        tab("Блюда").performClick()
        awaitText("Что приготовим?")
        text("Граф").performClick()
        awaitText("Больше блюд с одной покупкой")
    }

    @Category(UiSmoke::class)
    @Test
    fun graphAndListShareFiltersRecipeIdAndSystemBack() {
        openGraph()
        text("Найти блюдо").performTextInput("Омлет")
        dishText("Докупить 1–3").performClick()
        compose.onNodeWithContentDescription("Открыть фильтры").performClick()
        compose
            .onNodeWithContentDescription("Максимальное время приготовления, минуты")
            .performSemanticsAction(SemanticsActions.SetProgress) { it(15f) }
        compose
            .onNodeWithContentDescription("Максимальная калорийность на порцию")
            .performSemanticsAction(SemanticsActions.SetProgress) { it(450f) }
        text("Плита").performClick()
        text("Показать блюда").performClick()
        dishText("Омлет с сыром").performClick()
        awaitText("Рецепт")
        awaitText("Омлет с сыром")
        compose.runOnIdle { compose.activity.onBackPressedDispatcher.onBackPressed() }
        compose.onNodeWithTag("dishes-results").performScrollToIndex(0)
        awaitText("Больше блюд с одной покупкой")
        dishText("Граф").assertIsSelected()
        compose.onNode(hasSetTextAction()).assertTextContains("Омлет")
        dishText("Докупить 1–3").assertIsSelected()
        dishText("Список").performClick()
        compose.onNode(hasSetTextAction()).assertTextContains("Омлет")
        dishText("Докупить 1–3").assertIsSelected()
        dishText("Омлет с сыром").assertIsDisplayed()
        text("Омлет с томатами").assertDoesNotExist()
        dishText("Граф").performClick()
        compose.onNodeWithContentDescription("Открыть фильтры").performClick()
        text("Время: до 15 мин").assertIsDisplayed()
        text("Калорийность: до 450 ккал на порцию").assertIsDisplayed()
        text("Плита").assertIsSelected()
        text("Духовка").performClick()
        text("Показать блюда").performClick()
        awaitText("Подходящих блюд нет")
        dishText("Сбросить фильтры").performClick()
        dishText("Омлет с сыром").assertIsDisplayed()
    }

    @Category(UiSmoke::class)
    @Test
    fun graphPurchaseAppearsInSharedShoppingAndWriteCanRetry() {
        openGraph()
        dependencies.household.failWrite = true
        dishText("Добавить в покупки").performClick()
        dishText("Не удалось сохранить изменения. Повторите действие.").assertIsDisplayed()
        assertTrue(dependencies.household.values.value.manualPurchases.isEmpty())
        dependencies.household.failWrite = false
        dishText("Добавить в покупки").performClick()
        compose.waitUntil(10_000) { dependencies.household.values.value.manualPurchases.size == 1 }
        tab("Покупки").performClick()
        awaitText("Из рецептов и выбранных предложений")
        text("Твёрдый сыр").performScrollTo().assertIsDisplayed()
        assertEquals(
            23000L,
            shoppingQuote(DemoCatalog.catalog, dependencies.household.values.value).totalKopecks,
        )
        tab("Блюда").performClick()
        compose.onNodeWithTag("dishes-results").performScrollToIndex(0)
        awaitText("Больше блюд с одной покупкой")
        dishText("Граф").assertIsSelected()
    }

    @Category(UiSmoke::class)
    @Test
    fun graphLoadingAndReadErrorRetryKeepSelectedView() {
        launch()
        awaitText("Мои продукты")
        dependencies.household.failRead = true
        tab("Блюда").performClick()
        awaitText("Данные недоступны")
        text("Граф").performClick().assertIsSelected()
        dependencies.household.failRead = false
        dependencies.catalogSource = MutableSharedFlow(replay = 1)
        text("Повторить").performClick()
        compose.onNode(hasProgressBarRangeInfo(ProgressBarRangeInfo.Indeterminate)).assertExists()
        text("Граф").assertIsSelected()
        dependencies.catalogSource.tryEmit(DemoCatalog.catalog)
        awaitText("Больше блюд с одной покупкой")
        dishText("Лучшая одиночная покупка").assertIsDisplayed()
        dishText("Найти блюдо").performTextInput("нет такого блюда")
        awaitText("Подходящих блюд нет")
        dishText("Сбросить фильтры").performClick()
        dishText("Сейчас").performClick()
        awaitText("Нет связей с одной покупкой")
        dishText("Список").performClick()
        dishText("Омлет с томатами").assertIsDisplayed()
    }

    @Category(Screenshot::class)
    @Test
    fun dishesGraphScreenshot() {
        openGraph()
        dishText("Омлет с сыром")
        capture("dishes-graph.png")
    }

    @Category(Screenshot::class)
    @Test
    fun dishesGraphLargeFontScreenshot() {
        openGraph(1.5f)
        dishText("Омлет с сыром")
        capture("dishes-graph-large-font.png")
    }

    @Category(Screenshot::class)
    @Test
    @Config(qualifiers = "ru-rRU-w360dp-h800dp-notnight-xhdpi")
    fun dishesGraphNarrowScreenshot() {
        openGraph()
        dishText("Омлет с сыром")
        capture("dishes-graph-narrow.png")
    }

    @Category(Screenshot::class)
    @Test
    fun dishesGraphEmptyScreenshot() {
        openGraph()
        text("Найти блюдо").performTextInput("нет такого блюда")
        awaitText("Подходящих блюд нет")
        capture("dishes-graph-empty.png")
    }

    @Category(Screenshot::class)
    @Test
    fun dishesGraphNoLinksScreenshot() {
        openGraph()
        dishText("Сейчас").performClick()
        awaitText("Нет связей с одной покупкой")
        capture("dishes-graph-no-links.png")
    }

    @Category(Screenshot::class)
    @Test
    fun dishesGraphErrorScreenshot() {
        launch()
        awaitText("Мои продукты")
        dependencies.household.failRead = true
        tab("Блюда").performClick()
        awaitText("Данные недоступны")
        text("Граф").performClick().assertIsSelected()
        capture("dishes-graph-error.png")
    }

    @Category(Screenshot::class)
    @Test
    fun dishesGraphLoadingScreenshot() {
        launch()
        awaitText("Мои продукты")
        dependencies.catalogSource = MutableSharedFlow(replay = 1)
        tab("Блюда").performClick()
        text("Граф").performClick().assertIsSelected()
        compose.onNode(hasProgressBarRangeInfo(ProgressBarRangeInfo.Indeterminate)).assertExists()
        capture("dishes-graph-loading.png")
    }

    @Category(Screenshot::class) @Test fun dishesScreenshot() = screenshot("dishes.png", 1f)

    @Category(Screenshot::class)
    @Test
    fun dishesLargeFontScreenshot() = screenshot("dishes-large-font.png", 1.5f)

    private fun screenshot(name: String, fontScale: Float) {
        launch(fontScale)
        awaitText("Мои продукты")
        tab("Блюда").performClick()
        awaitText("Что приготовим?")
        capture(name)
    }

    private fun capture(name: String) {
        compose.mainClock.advanceTimeBy(1000)
        check(
            System.getProperty("os.name") == "Linux" && System.getProperty("os.arch") == "amd64"
        ) {
            "Run screenshots with bash .github/android/check.sh in the pinned Linux x86 container"
        }
        compose.waitForIdle()
        // A missing reference must fail verification instead of silently recording one.
        if (System.getProperty("roborazzi.test.verify") == "true") {
            assertTrue("Missing reference: $name", File("src/test/screenshots/$name").isFile)
        }
        compose
            .onRoot()
            .captureRoboImage(
                name,
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

private class SmokeSession : SessionRepository {
    val value = MutableStateFlow(true)
    override val signedIn: Flow<Boolean> = value

    override suspend fun signIn(login: String, password: String) {
        require(login == "demo" && password == "demo") { "Неверные демо-данные" }
        value.value = true
    }

    override suspend fun signInWithToken(token: String) {
        value.value = true
    }

    override suspend fun signOut() {
        value.value = false
    }
}

private class SmokeDependencies : AppDependencies {
    var catalogSource =
        MutableSharedFlow<Catalog>(replay = 1).apply { tryEmit(DemoCatalog.catalog) }
    override val catalog =
        object : CatalogRepository {
            override val catalog: Flow<Catalog>
                get() = catalogSource
        }
    override val household = FakeHousehold()
    override val preferences = FakePreferences()
    override val session = SmokeSession()
    override val yandexAuth by lazy {
        YandexAuthSdk.create(YandexAuthOptions(RuntimeEnvironment.getApplication()))
    }
}
