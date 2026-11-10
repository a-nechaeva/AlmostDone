package com.example.mobile_android.feature.favorites.localwiring

import android.app.Application
import android.os.SystemClock
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import com.dropbox.differ.SimpleImageComparator
import com.example.mobile_android.ui.Screenshot
import com.github.takahirom.roborazzi.RoborazziOptions
import com.github.takahirom.roborazzi.captureRoboImage
import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.experimental.categories.Category
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], application = Application::class, qualifiers = "ru-rRU-w400dp-h900dp-notnight-xhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Category(Screenshot::class)
class FavoritesLocalWiringScreenshotTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    @Test fun failedAddKeepsQuantityAndShowsRetry() {
        assertTrue(SystemClock.setCurrentTimeMillis(1_735_689_600_000L))
        val fixture = FavoritesLocalWiringFixture()
        fixture.household.failAdd = true
        compose.setContent { FavoritesLocalWiringHost(fixture) }
        compose.onNodeWithText("Ингредиенты").performClick()
        compose.onNodeWithContentDescription("Указать количество: Томаты").performClick()
        compose.onNodeWithText("Количество, г").performTextInput("125,5")
        compose.onNodeWithText("Добавить в продукты").performClick()
        compose.onNodeWithText("Повторить").assertIsDisplayed()

        val name = "favorites-local-wiring-quantity-error.png"
        if (System.getProperty("roborazzi.test.verify") == "true" ||
            System.getProperty("roborazzi.test.compare") == "true"
        ) {
            assertTrue("Missing reference: $name", File("src/test/screenshots/$name").isFile)
        }
        compose.onNode(isDialog()).captureRoboImage(
            name,
            roborazziOptions = RoborazziOptions(
                compareOptions = RoborazziOptions.CompareOptions(
                    changeThreshold = 0f,
                    imageComparator = SimpleImageComparator(maxDistance = 0f),
                ),
            ),
        )
    }
}
