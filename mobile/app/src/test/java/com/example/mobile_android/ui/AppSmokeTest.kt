package com.example.mobile_android.ui

import android.app.Application
import android.os.SystemClock
import androidx.activity.ComponentActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.Role
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

    @Test fun dishesScreenshot() = screenshot("dishes.png", 1f)

    @Test fun dishesLargeFontScreenshot() = screenshot("dishes-large-font.png", 1.5f)

    private fun screenshot(name: String, fontScale: Float) {
        check(
            System.getProperty("os.name") == "Linux" && System.getProperty("os.arch") == "amd64"
        ) {
            "Run screenshots with bash .github/android/check.sh in the pinned Linux x86 container"
        }
        launch(fontScale)
        awaitText("Мои продукты")
        tab("Блюда").performClick()
        awaitText("Что приготовим?")
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
