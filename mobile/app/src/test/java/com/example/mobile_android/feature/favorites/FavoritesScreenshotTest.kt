package com.example.mobile_android.feature.favorites

import android.app.Application
import android.os.SystemClock
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import com.dropbox.differ.SimpleImageComparator
import com.example.mobile_android.data.DemoCatalog
import com.example.mobile_android.domain.*
import com.example.mobile_android.ui.Screenshot
import com.github.takahirom.roborazzi.RoborazziOptions
import com.github.takahirom.roborazzi.captureRoboImage
import java.io.File
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
@Config(sdk = [36], application = Application::class,
    qualifiers = "ru-rRU-w400dp-h900dp-notnight-xhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Category(Screenshot::class)
class FavoritesScreenshotTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    @Before fun freezeTime() {
        assertTrue(SystemClock.setCurrentTimeMillis(1_735_689_600_000L))
        compose.mainClock.autoAdvance = true
    }

    @Test fun dishesScreenshot() {
        compose.setContent { FavoritesUiHost() }
        compose.onNodeWithText("Омлет с томатами").assertIsDisplayed()
        capture("favorites-ui-dishes.png")
    }
    @Test fun ingredientsScreenshot() {
        compose.setContent { FavoritesUiHost() }
        compose.onNodeWithText("Ингредиенты").performClick()
        compose.onNodeWithText("Яйца").assertIsDisplayed()
        capture("favorites-ui-ingredients.png")
    }
    @Test fun emptyDishesScreenshot() {
        compose.setContent { FavoritesUiHost(state = favoritesFixture(emptySet(), emptySet())) }
        compose.onNodeWithText("Нет избранных блюд").assertIsDisplayed()
        capture("favorites-ui-empty-dishes.png")
    }
    @Test fun emptyIngredientsScreenshot() {
        compose.setContent { FavoritesUiHost(state = favoritesFixture(emptySet(), emptySet())) }
        compose.onNodeWithText("Ингредиенты").performClick()
        compose.onNodeWithText("Нет избранных ингредиентов").assertIsDisplayed()
        capture("favorites-ui-empty-ingredients.png")
    }
    @Test fun quantityScreenshot() {
        compose.setContent { FavoritesUiHost(selection = {}) }
        compose.onNodeWithText("Ингредиенты").performClick()
        compose.onNodeWithContentDescription("Указать количество: Томаты").performClick()
        compose.onNodeWithText("Количество, г").performTextInput("125,5")
        capture("favorites-ui-quantity.png")
    }
    @Test fun ingredientsLargeFontScreenshot() {
        compose.setContent { FavoritesUiHost(fontScale = 1.5f) }
        compose.onNodeWithText("Ингредиенты").performClick()
        capture("favorites-ui-ingredients-large-font.png")
    }
    @Test fun dishesLargeFontScreenshot() {
        compose.setContent { FavoritesUiHost(fontScale = 1.5f) }
        capture("favorites-ui-dishes-large-font.png")
    }
    @Test
    @Config(qualifiers = "ru-rRU-w360dp-h900dp-notnight-xhdpi")
    fun narrowLongIngredientScreenshot() {
        val catalog = DemoCatalog.catalog.copy(ingredients = listOf(Ingredient("long", "Очень длинное название любимого ингредиента для домашней кухни", QuantityUnit.GRAM)))
        compose.setContent { FavoritesUiHost(state = favoritesFixture(ingredientIds = setOf("long"), catalog = catalog), fontScale = 1.5f) }
        compose.onNodeWithText("Ингредиенты").performClick()
        capture("favorites-ui-360-large-font.png")
    }
    private fun capture(name: String) {
        compose.waitForIdle()
        if (System.getProperty("roborazzi.test.verify") == "true" ||
            System.getProperty("roborazzi.test.compare") == "true") {
            assertTrue("Missing reference: $name", File("src/test/screenshots/$name").isFile)
        }
        val target = if (name == "favorites-ui-quantity.png") compose.onNode(isDialog()) else compose.onRoot()
        target.captureRoboImage(name, roborazziOptions = RoborazziOptions(
            compareOptions = RoborazziOptions.CompareOptions(
                changeThreshold = 0f,
                imageComparator = SimpleImageComparator(maxDistance = 0f),
            ),
        ))
    }
}
