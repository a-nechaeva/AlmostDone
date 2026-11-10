package com.example.mobile_android.feature.dishes

import android.app.Application
import android.os.SystemClock
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import com.dropbox.differ.SimpleImageComparator
import com.example.mobile_android.domain.Allergen
import com.example.mobile_android.domain.FoodPreferences
import com.example.mobile_android.feature.FakePreferences
import com.example.mobile_android.ui.Screenshot
import com.github.takahirom.roborazzi.RoborazziOptions
import com.github.takahirom.roborazzi.captureRoboImage
import java.io.File
import org.junit.Assert.assertTrue
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
@Category(Screenshot::class)
class DishesLocalScreenshotTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val preferences = FakePreferences()

    @Before
    fun freezeTime() {
        assertTrue(SystemClock.setCurrentTimeMillis(1_735_689_600_000L))
        compose.mainClock.autoAdvance = true
    }

    @Test
    fun filters() {
        launch()
        await("Что приготовим?")
        compose.onNodeWithContentDescription("Открыть фильтры").performClick()
        compose.onNodeWithText("До 30 мин").performClick()
        compose.onNodeWithText("Молоко").performClick()
        await("Показать 1 блюдо")
        compose.onNodeWithText("Оборудование").assertIsDisplayed()
        compose.onNodeWithText("Показать 1 блюдо").assertIsDisplayed()
        capture("filters", compose.onNode(isDialog()))
    }

    @Test
    fun hidden() {
        preferences.values.value = FoodPreferences(excludedAllergens = setOf(Allergen.MILK))
        launch()
        await("Что приготовим?")
        compose.onNodeWithTag("dishes-results").performScrollToNode(hasText("Скрытые блюда (3)"))
        compose.onNodeWithText("Скрытые блюда (3)").performClick()
        await("Почему блюда скрыты")
        capture("hidden")
    }

    @Test
    fun loading() {
        launch(DishesHostCatalog(ready = false))
        await("Подбираем блюда")
        capture("loading")
    }

    @Test
    fun empty() {
        launch()
        await("Что приготовим?")
        compose.onNode(hasSetTextAction()).performTextInput("Суп")
        await("Подходящих блюд нет")
        capture("empty")
    }

    @Test
    fun error() {
        launch(DishesHostCatalog(ready = false).apply { failRead = true })
        await("Блюда не загрузились")
        capture("error")
    }

    private fun launch(catalog: DishesHostCatalog = DishesHostCatalog()) {
        compose.setContent { DishesLocalHost(catalog, preferences) }
    }

    private fun await(text: String) {
        compose.waitUntil(10_000) {
            compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun capture(scenario: String, target: SemanticsNodeInteraction = compose.onRoot()) {
        val name = "dishes-local-$scenario.png"
        compose.mainClock.advanceTimeBy(1000)
        compose.waitForIdle()
        check(System.getProperty("os.name") == "Linux" && System.getProperty("os.arch") == "amd64")
        if (
            System.getProperty("roborazzi.test.verify") == "true" ||
                System.getProperty("roborazzi.test.compare") == "true"
        ) {
            assertTrue("Missing reference: $name", File("src/test/screenshots/$name").isFile)
        }
        target.captureRoboImage(
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
