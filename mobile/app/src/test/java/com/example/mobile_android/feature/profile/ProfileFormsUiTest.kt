package com.example.mobile_android.feature.profile

import android.app.Application
import android.os.SystemClock
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.unit.Density
import com.dropbox.differ.SimpleImageComparator
import com.example.mobile_android.domain.*
import com.example.mobile_android.feature.common.*
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
class ProfileFormsUiTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val repo = ProfileUiPreferences()
    private val vm by lazy { ProfileViewModel(repo) }
    private var favorites = 0
    private var logouts = 0
    private var logoutState by mutableStateOf(ActionState())
    private var holdLogout = false

    @Before
    fun freezeTime() {
        assertTrue(SystemClock.setCurrentTimeMillis(1_735_689_600_000L))
    }

    private fun launch(fontScale: Float = 1f, connected: Boolean = true) {
        compose.setContent { Host(fontScale, connected) }
    }

    @Composable
    private fun Host(fontScale: Float = 1f, connected: Boolean = true) {
        val state by vm.state.collectAsState()
        val action by vm.actions.state.collectAsState()
        CompositionLocalProvider(LocalDensity provides Density(2f, fontScale)) {
            AlmostReadyTheme {
                Surface(
                    Modifier.fillMaxSize(),
                    color = androidx.compose.material3.MaterialTheme.colorScheme.background,
                ) {
                    LoadContent(state, vm::retry) { preferences ->
                        ProfileScreen(
                            preferences,
                            action,
                            logoutState,
                            vm::foodType,
                            vm::allergen,
                            vm::gluten,
                            vm::lactose,
                            vm::diabetes,
                            vm::table,
                            { favorites++ },
                            {
                                logouts++
                                if (holdLogout) logoutState = ActionState(pending = true)
                            },
                            vm.actions::dismiss,
                            {},
                            if (connected) vm::save else null,
                        )
                    }
                }
            }
        }
    }

    private fun text(label: String) = compose.onNodeWithText(label)

    private fun click(label: String) {
        text(label).apply { if (!isDisplayed()) performScrollTo() }.performClick()
    }

    private fun back() {
        compose.runOnIdle { compose.activity.onBackPressedDispatcher.onBackPressed() }
    }

    private fun open() {
        click("Питание и аллергены")
    }

    @Category(UiSmoke::class)
    @Test
    fun draftCancelBackAndNestedCancelNeverWrite() {
        launch()
        open()
        click("Веганство")
        click("Аллергены")
        click("Молоко (молочный белок)")
        text("Молоко (молочный белок)").assertIsOn()
        back()
        click("Аллергены")
        text("Молоко (молочный белок)").assertIsOff()
        click("Молоко (молочный белок)")
        click("Сохранить выбор")
        click("Диетический стол")
        text("Название из назначения").performTextInput("Стол для проверки")
        click("Отмена")
        click("Диетический стол")
        text("Название из назначения")
            .assert(
                SemanticsMatcher.expectValue(SemanticsProperties.EditableText, AnnotatedString(""))
            )
        back()
        back()
        text("Профиль").assertIsDisplayed()
        compose.runOnIdle {
            assertEquals(0, repo.writes)
            assertEquals(FoodPreferences(), repo.values.value)
        }
        open()
        text("Без ограничений").assertIsSelected()
        click("Вегетарианство")
        click("Отмена")
        open()
        text("Без ограничений").assertIsSelected()
    }

    @Category(UiSmoke::class)
    @Test
    fun fullDraftSaveFailureRetryAndPending() {
        launch()
        open()
        click("Веганство")
        click("Аллергены")
        click("Молоко (молочный белок)")
        click("Сохранить выбор")
        click("Без лактозы")
        click("Диетический стол")
        text("Название из назначения").performTextInput("Личное назначение")
        click("Сохранить")
        compose.runOnIdle {
            assertEquals(0, repo.writes)
            repo.writeFailure = true
        }
        click("Сохранить предпочтения")
        text("Не удалось сохранить изменения. Повторите действие.")
            .performScrollTo()
            .assertIsDisplayed()
        text("Веганство").performScrollTo().assertIsSelected()
        compose.runOnIdle {
            assertEquals(FoodPreferences(), repo.values.value)
            repo.writeFailure = false
            repo.gate = CompletableDeferred()
        }
        click("Сохранить предпочтения")
        text("Сохраняем…").assertIsNotEnabled()
        back()
        text("Предпочтения питания").performScrollTo().assertIsDisplayed()
        compose.runOnIdle {
            assertEquals(2, repo.writes)
            repo.gate!!.complete(Unit)
        }
        compose.waitUntil(10_000) {
            compose.onAllNodesWithText("Профиль").fetchSemanticsNodes().isNotEmpty()
        }
        compose.runOnIdle {
            assertEquals(FoodType.VEGAN, repo.values.value.foodType)
            assertEquals(setOf(Allergen.MILK), repo.values.value.excludedAllergens)
            assertTrue(repo.values.value.lactoseFree)
            assertEquals("Личное назначение", repo.values.value.dietTable)
        }
    }

    @Category(UiSmoke::class)
    @Test
    fun draftSurvivesRestorationAndRepositoryEmission() {
        val restoration = StateRestorationTester(compose)
        restoration.setContent { Host() }
        open()
        click("Веганство")
        click("Диетический стол")
        text("Название из назначения").performTextInput("Черновик")
        restoration.emulateSavedInstanceStateRestore()
        text("Название из назначения").assertTextContains("Черновик")
        compose.runOnIdle { repo.values.value = FoodPreferences(glutenFree = true) }
        text("Название из назначения").assertTextContains("Черновик")
        back()
        back()
        open()
        text("Без ограничений").assertIsSelected()
        text("Без глютена").performScrollTo().assertIsOn()
        compose.runOnIdle { assertEquals(0, repo.writes) }
    }

    @Category(UiSmoke::class)
    @Test
    fun legacyHostCannotPretendToSaveAndLogoutRequiresConfirmation() {
        launch(connected = false)
        open()
        click("Веганство")
        text("Сохранить предпочтения").performScrollTo().assertIsNotEnabled()
        text("Сохранение пока недоступно").performScrollTo().assertIsDisplayed()
        back()
        click("Избранное")
        compose.runOnIdle { assertEquals(1, favorites) }
        click("Выйти из демо")
        click("Отмена")
        compose.runOnIdle { assertEquals(0, logouts) }
        click("Выйти из демо")
        click("Выйти")
        compose.runOnIdle {
            assertEquals(1, logouts)
            assertEquals(0, repo.writes)
        }
    }

    @Config(qualifiers = "ru-rRU-w360dp-h900dp-notnight-xhdpi")
    @Category(UiSmoke::class)
    @Test
    fun accessibleChoicesLongLabelAt360AndLargeFont() {
        launch(1.5f)
        open()
        text("Вегетарианство")
            .performScrollTo()
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.RadioButton))
        click("Вегетарианство")
        text("Вегетарианство").assertIsSelected()
        click("Аллергены")
        text("Молоко (молочный белок)")
            .performScrollTo()
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Checkbox))
        click("Молоко (молочный белок)")
        text("Молоко (молочный белок)").assertIsOn()
        click("Сохранить выбор")
        click("Диетический стол")
        text("Название из назначения")
            .performTextInput(
                "Длинное название из личного назначения без обещаний медицинского соответствия"
            )
        click("Сохранить")
        text("Сохранить предпочтения").performScrollTo().assertIsDisplayed()
    }

    @Category(UiSmoke::class)
    @Test
    fun logoutPendingErrorAndRetryStayInConfirmation() {
        launch()
        click("Выйти из демо")
        compose.runOnIdle { holdLogout = true }
        click("Выйти")
        text("Выходим…").assertIsNotEnabled()
        text("Отмена").assertIsNotEnabled()
        compose.runOnIdle {
            assertEquals(1, logouts)
            logoutState =
                ActionState(message = "Не удалось выйти. Повторите попытку.", failed = true)
        }
        text("Не удалось выйти. Повторите попытку.").assertIsDisplayed()
        click("Выйти")
        compose.runOnIdle { assertEquals(2, logouts) }
    }

    @Category(UiSmoke::class)
    @Test
    fun readErrorCanRetryToEmptyProfile() {
        repo.readFailure = true
        launch()
        text("Данные недоступны").assertIsDisplayed()
        compose.runOnIdle { repo.readFailure = false }
        click("Повторить")
        open()
        text("Без ограничений").assertIsSelected()
    }

    @Category(Screenshot::class)
    @Test
    fun profileScreenshot() {
        launch()
        screenshot("profile-ui-home.png")
    }

    @Category(Screenshot::class)
    @Test
    fun preferencesScreenshot() {
        launch()
        open()
        screenshot("profile-ui-preferences.png")
    }

    @Category(Screenshot::class)
    @Test
    fun allergensScreenshot() {
        launch()
        open()
        click("Аллергены")
        screenshot("profile-ui-allergens.png")
    }

    @Category(Screenshot::class)
    @Test
    fun tableScreenshot() {
        launch()
        open()
        click("Диетический стол")
        screenshot("profile-ui-table.png")
    }

    @Category(Screenshot::class)
    @Test
    fun logoutScreenshot() {
        launch()
        click("Выйти из демо")
        screenshot("profile-ui-logout.png", dialog = true)
    }

    @Config(qualifiers = "ru-rRU-w360dp-h900dp-notnight-xhdpi")
    @Category(Screenshot::class)
    @Test
    fun largeFontScreenshot() {
        launch(1.5f)
        open()
        click("Аллергены")
        screenshot("profile-ui-allergens-360-large.png")
    }

    private fun screenshot(name: String, dialog: Boolean = false) {
        check(System.getProperty("os.name") == "Linux" && System.getProperty("os.arch") == "amd64")
        compose.waitForIdle()
        if (System.getProperty("roborazzi.test.verify") == "true")
            assertTrue(File("src/test/screenshots/$name").isFile)
        val root = if (dialog) compose.onNode(isDialog()) else compose.onRoot()
        root.captureRoboImage(
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
