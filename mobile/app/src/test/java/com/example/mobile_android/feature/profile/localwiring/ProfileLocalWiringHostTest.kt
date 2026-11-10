package com.example.mobile_android.feature.profile.localwiring

import android.app.Application
import android.os.SystemClock
import android.view.View
import androidx.activity.ComponentActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.input.InputMode
import androidx.compose.ui.input.InputModeManager
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalInputModeManager
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.Density
import androidx.core.graphics.Insets
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.navigation.NavHostController
import androidx.navigation.compose.rememberNavController
import com.dropbox.differ.SimpleImageComparator
import com.example.mobile_android.data.local.LocalPreferences
import com.example.mobile_android.domain.Allergen
import com.example.mobile_android.domain.FoodPreferences
import com.example.mobile_android.domain.FoodType
import com.example.mobile_android.navigation.AppTab
import com.example.mobile_android.ui.Screenshot
import com.example.mobile_android.ui.UiSmoke
import com.example.mobile_android.ui.theme.AlmostReadyTheme
import com.github.takahirom.roborazzi.RoborazziOptions
import com.github.takahirom.roborazzi.captureRoboImage
import java.io.File
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.first
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.experimental.categories.Category
import org.junit.rules.TemporaryFolder
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
class ProfileLocalWiringHostTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    @get:Rule val directory = TemporaryFolder()
    private val storeScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private lateinit var storeFile: File
    private lateinit var local: LocalPreferences
    private lateinit var repository: RecordingPreferences
    private lateinit var nav: NavHostController
    private lateinit var insetsTarget: View
    private lateinit var inputMode: InputModeManager
    private val editorEvents = mutableListOf<Boolean>()
    private var logouts = 0

    @Before
    fun prepare() {
        assertTrue(SystemClock.setCurrentTimeMillis(1_735_689_600_000L))
        storeFile = File(directory.root, "profile-local-wiring.preferences_pb")
        local = localPreferences(storeScope)
        repository = RecordingPreferences(local)
        compose.activityRule.scenario.onActivity {
            WindowCompat.setDecorFitsSystemWindows(it.window, false)
        }
    }

    @After
    fun closeStore() {
        runBlocking { storeScope.coroutineContext.job.cancelAndJoin() }
    }

    private fun localPreferences(scope: CoroutineScope) =
        LocalPreferences(PreferenceDataStoreFactory.create(scope = scope) { storeFile })

    private fun launch(fontScale: Float = 1f) {
        compose.setContent {
            val controller = rememberNavController()
            val view = LocalView.current
            val mode = LocalInputModeManager.current
            SideEffect {
                nav = controller
                insetsTarget = view
                inputMode = mode
            }
            CompositionLocalProvider(LocalDensity provides Density(2f, fontScale)) {
                AlmostReadyTheme {
                    ProfileLocalWiringHost(
                        repository,
                        controller,
                        onEditorVisibilityChanged = { editorEvents += it },
                        logout = { logouts++ },
                    )
                }
            }
        }
        tab(AppTab.PROFILE)
        waitForText("Демо-профиль")
    }

    private fun text(label: String) = compose.onNodeWithText(label)

    private fun click(label: String) {
        text(label).apply { if (!isDisplayed()) performScrollTo() }.performClick()
    }

    private fun waitForText(label: String) {
        compose.waitUntil(10_000) {
            compose.onAllNodesWithText(label).fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun tab(tab: AppTab) {
        compose.onNodeWithTag(tab.route).performClick()
    }

    private fun openEditor() = click("Питание и аллергены")

    private fun back() {
        compose.runOnIdle { compose.activity.onBackPressedDispatcher.onBackPressed() }
    }

    private fun assertBars(visible: Boolean) {
        listOf("top-bar", "bottom-bar").forEach { tag ->
            if (visible) compose.onNodeWithTag(tag).assertIsDisplayed()
            else compose.onNodeWithTag(tag).assertDoesNotExist()
        }
    }

    @Test
    @Category(UiSmoke::class)
    fun oneLocalWriteUpdatesReopenedProfileAndDishes() {
        launch()
        tab(AppTab.DISHES)
        waitForText("Омлет с томатами: ALLOWED")
        tab(AppTab.PROFILE)
        waitForText("Демо-профиль")
        openEditor()
        click("Веганство")
        click("Без лактозы")
        click("Аллергены")
        click("Молоко (молочный белок)")
        click("Сохранить выбор")
        click("Диетический стол")
        text("Название из назначения").performTextInput("  Личное назначение  ")
        click("Сохранить")
        click("Сохранить предпочтения")
        waitForText("Предпочтения сохранены")
        assertBars(visible = true)
        compose.runOnIdle {
            assertEquals(1, repository.attempts)
            assertEquals(1, repository.writes)
        }
        openEditor()
        text("Веганство").assertIsSelected()
        back()

        click("Мои продукты")
        waitForText("Продукты дома")
        compose.runOnIdle { assertEquals(AppTab.PANTRY.route, nav.currentDestination?.route) }
        tab(AppTab.DISHES)
        waitForText("Омлет с томатами: HIDDEN")
        tab(AppTab.PROFILE)
        waitForText("Демо-профиль")
        openEditor()
        text("Веганство").assertIsSelected()
        text("Без лактозы").performScrollTo().assertIsOn()
        click("Аллергены")
        text("Молоко (молочный белок)").assertIsOn()
        back()
        click("Диетический стол")
        text("Название из назначения").assertTextContains("Личное назначение")

        closeStore()
        val reopenedScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        try {
            val persisted = runBlocking {
                withTimeout(10_000) { localPreferences(reopenedScope).preferences.first() }
            }
            assertEquals(
                FoodPreferences(
                    foodType = FoodType.VEGAN,
                    excludedAllergens = setOf(Allergen.MILK),
                    lactoseFree = true,
                    dietTable = "Личное назначение",
                ),
                persisted,
            )
        } finally {
            runBlocking { reopenedScope.coroutineContext.job.cancelAndJoin() }
        }
    }

    @Test
    @Category(UiSmoke::class)
    fun successfulWriteClosesEvenWhenASecondWriterHasAlreadyUpdatedPreferences() {
        launch()
        openEditor()
        click("Вегетарианство")
        compose.runOnIdle { repository.finishGate = CompletableDeferred() }
        click("Сохранить предпочтения")
        compose.waitUntil(10_000) { compose.runOnIdle { repository.writes == 1 } }

        val latest = FoodPreferences(lactoseFree = true)
        runBlocking { local.update { latest } }
        compose.runOnIdle { repository.finishGate!!.complete(Unit) }
        waitForText("Предпочтения сохранены")
        assertBars(visible = true)
        openEditor()
        text("Без ограничений").assertIsSelected()
        text("Без лактозы").performScrollTo().assertIsOn()
        compose.runOnIdle { assertEquals(1, repository.attempts) }
    }

    @Test
    @Category(UiSmoke::class)
    fun savesWithALegacyTableNameThatNeedsTrimmingAfterTruncation() {
        val trimmed = "а".repeat(99)
        runBlocking { local.update { it.copy(dietTable = "$trimmed б") } }
        launch()
        openEditor()
        click("Без лактозы")
        click("Сохранить предпочтения")
        waitForText("Предпочтения сохранены")
        assertEquals(
            FoodPreferences(lactoseFree = true, dietTable = trimmed),
            runBlocking { local.preferences.first() },
        )
        compose.runOnIdle { assertEquals(1, repository.writes) }
    }

    @Test
    @Category(UiSmoke::class)
    fun failedWriteKeepsDraftAndPendingRetryBlocksAnotherSubmit() {
        launch()
        openEditor()
        click("Вегетарианство")
        click("Без глютена")
        compose.runOnIdle { repository.failNext = true }
        click("Сохранить предпочтения")
        text("Не удалось сохранить изменения. Повторите действие.").performScrollTo()
            .assertIsDisplayed()
        text("Вегетарианство").performScrollTo().assertIsSelected()
        text("Без глютена").performScrollTo().assertIsOn()
        compose.runOnIdle {
            assertEquals(1, repository.attempts)
            assertEquals(0, repository.writes)
            repository.gate = CompletableDeferred()
        }
        val submit = text("Сохранить предпочтения").performScrollTo()
        val onClick = submit.fetchSemanticsNode().config[SemanticsActions.OnClick].action!!
        compose.runOnIdle {
            onClick()
            onClick()
        }
        text("Сохраняем…").assertIsNotEnabled()
        back()
        assertBars(visible = false)
        compose.runOnIdle {
            assertEquals(2, repository.attempts)
            assertEquals(0, repository.writes)
            repository.gate!!.complete(Unit)
        }
        waitForText("Предпочтения сохранены")
        assertBars(visible = true)
        compose.runOnIdle { assertEquals(1, repository.writes) }
        openEditor()
        text("Вегетарианство").assertIsSelected()
        text("Без глютена").performScrollTo().assertIsOn()
    }

    @Test
    @Category(UiSmoke::class)
    fun cancelBackAndRouteExitRestoreBarsWithoutWriting() {
        launch()
        assertBars(visible = true)
        openEditor()
        assertBars(visible = false)
        click("Без лактозы")
        click("Аллергены")
        click("Молоко (молочный белок)")
        back()
        assertBars(visible = false)
        click("Аллергены")
        text("Молоко (молочный белок)").assertIsOff()
        click("Отмена")
        text("Без лактозы").performScrollTo().assertIsOn()
        click("Отмена")
        assertBars(visible = true)
        openEditor()
        text("Без лактозы").performScrollTo().assertIsOff()
        click("Веганство")
        compose.runOnIdle { nav.navigateTestTab(AppTab.DISHES) }
        waitForText("Омлет с томатами: ALLOWED")
        assertBars(visible = true)
        tab(AppTab.PROFILE)
        waitForText("Демо-профиль")
        assertBars(visible = true)
        openEditor()
        text("Без ограничений").assertIsSelected()
        back()
        assertBars(visible = true)
        compose.runOnIdle {
            assertEquals(listOf(true, false, true, false, true, false), editorEvents)
            assertEquals(0, repository.attempts)
        }

        click("Избранное")
        waitForText("Избранное открыто")
        back()
        waitForText("Демо-профиль")
        click("Выйти из демо")
        click("Отмена")
        click("Выйти из демо")
        click("Выйти")
        compose.runOnIdle { assertEquals(1, logouts) }
    }

    @Test
    @Category(UiSmoke::class)
    fun leavingRouteDuringReadErrorDiscardsTheSavedEditor() {
        launch()
        openEditor()
        click("Веганство")
        compose.runOnIdle { repository.readFailure.value = true }
        waitForText("Данные недоступны")
        assertBars(visible = true)
        tab(AppTab.PANTRY)
        waitForText("Продукты дома")
        tab(AppTab.PROFILE)
        waitForText("Данные недоступны")
        compose.runOnIdle { repository.readFailure.value = false }
        click("Повторить")
        waitForText("Демо-профиль")
        assertBars(visible = true)
        openEditor()
        text("Без ограничений").assertIsSelected()
        compose.runOnIdle {
            assertEquals(listOf(true, false, true), editorEvents)
            assertEquals(0, repository.attempts)
        }
    }

    @Test
    @Config(qualifiers = "ru-rRU-w360dp-h520dp-notnight-xhdpi")
    @Category(UiSmoke::class)
    fun returningFromFavoritesOrAnotherTabPreservesProfileScroll() {
        launch(fontScale = 1.5f)
        val favorites = text("Избранное").performScrollTo().assertIsDisplayed()
        val range = SemanticsProperties.VerticalScrollAxisRange
        val scroller = compose.onNode(SemanticsMatcher.keyIsDefined(range))
        val initialScroll = scroller.fetchSemanticsNode().config[range].value()
        assertTrue(initialScroll > 0f)
        favorites.performClick()
        waitForText("Избранное открыто")
        back()
        waitForText("Избранное")
        assertEquals(initialScroll, scroller.fetchSemanticsNode().config[range].value(), 0f)
        tab(AppTab.PANTRY)
        waitForText("Продукты дома")
        tab(AppTab.PROFILE)
        waitForText("Избранное")
        assertEquals(initialScroll, scroller.fetchSemanticsNode().config[range].value(), 0f)
    }

    @Test
    @Config(qualifiers = "ru-rRU-w360dp-h900dp-notnight-xhdpi")
    @Category(UiSmoke::class)
    @OptIn(ExperimentalTestApi::class)
    fun keyboardKeepsTableSaveReachableAndReturnsToPreferencesScroll() {
        launch(fontScale = 1.5f)
        openEditor()
        val table = text("Диетический стол").performScrollTo()
        val tableTop = table.fetchSemanticsNode().boundsInRoot.top
        table.performClick()
        val name = text("Название из назначения")
        name.performClick().assertIsFocused().performTextInput("Стол из назначения")

        val keyboardHeight = 820
        val rootBottom = compose.onRoot().fetchSemanticsNode().boundsInRoot.bottom
        showKeyboardInsets(keyboardHeight)
        val save = text("Сохранить").performScrollTo().assertIsDisplayed()
        assertTrue(save.fetchSemanticsNode().boundsInRoot.bottom <= rootBottom - keyboardHeight)
        // Robolectric injects Compose key events directly, outside ViewRootImpl's mode switch.
        compose.runOnIdle { assertTrue(inputMode.requestInputMode(InputMode.Keyboard)) }
        name.performKeyInput { pressKey(Key.Tab) }
        save.assertIsFocused()
        save.performKeyInput { pressKey(Key.Enter) }
        showKeyboardInsets(0)
        table.assertIsDisplayed()
        assertEquals(tableTop, table.fetchSemanticsNode().boundsInRoot.top, 1f)
        text("Стол из назначения").assertIsDisplayed()
        compose.runOnIdle { assertEquals(0, repository.attempts) }
    }

    private fun showKeyboardInsets(height: Int) {
        compose.runOnIdle {
            val ime = WindowInsetsCompat.Type.ime()
            ViewCompat.dispatchApplyWindowInsets(
                insetsTarget,
                WindowInsetsCompat.Builder()
                    .setInsets(ime, Insets.of(0, 0, 0, height))
                    .setVisible(ime, height > 0)
                    .build(),
            )
        }
    }

    @Test
    @Category(Screenshot::class)
    fun homeScreenshot() {
        launch()
        screenshot("profile-local-wiring-home.png")
    }

    @Test
    @Category(Screenshot::class)
    fun nestedFormScreenshot() {
        launch()
        openEditor()
        click("Диетический стол")
        assertBars(visible = false)
        screenshot("profile-local-wiring-nested-form.png")
    }

    private fun screenshot(name: String) {
        check(System.getProperty("os.name") == "Linux" && System.getProperty("os.arch") == "amd64")
        if (System.getProperty("roborazzi.test.verify") == "true") {
            assertTrue(File("src/test/screenshots/$name").isFile)
        }
        compose.onRoot().captureRoboImage(
            name,
            roborazziOptions = RoborazziOptions(
                compareOptions = RoborazziOptions.CompareOptions(
                    changeThreshold = 0f,
                    imageComparator = SimpleImageComparator(maxDistance = 0f),
                )
            ),
        )
    }
}
