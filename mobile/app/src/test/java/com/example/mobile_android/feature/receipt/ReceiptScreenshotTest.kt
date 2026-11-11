package com.example.mobile_android.feature.receipt

import android.app.Application
import android.os.SystemClock
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onRoot
import com.dropbox.differ.SimpleImageComparator
import com.example.mobile_android.data.DemoCatalog
import com.example.mobile_android.ui.Screenshot
import com.example.mobile_android.ui.theme.AlmostReadyTheme
import com.github.takahirom.roborazzi.RoborazziOptions
import com.github.takahirom.roborazzi.captureRoboImage
import java.io.File
import kotlinx.coroutines.runBlocking
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
@Config(sdk = [36], application = Application::class, qualifiers = "ru-rRU-w400dp-h900dp-notnight-xhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Category(Screenshot::class)
class ReceiptScreenshotTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    @Before fun freezeTime() {
        assertTrue(SystemClock.setCurrentTimeMillis(1_735_689_600_000L))
    }

    @Test fun captureScreen() = screenshot("capture", ReceiptState.Capture())

    @Test fun reviewScreen() {
        val lines = runBlocking { DemoReceiptRecognizer.recognize() }
        screenshot("review", ReceiptState.Review(lines, DemoCatalog.catalog.ingredients))
    }

    private fun screenshot(stateName: String, state: ReceiptState) {
        check(System.getProperty("os.name") == "Linux" && System.getProperty("os.arch") == "amd64")
        val name = "receipt-local-$stateName.png"
        if (System.getProperty("roborazzi.test.verify") == "true")
            assertTrue("Missing reference: $name", File("src/test/screenshots/$name").isFile)
        compose.setContent {
            AlmostReadyTheme {
                ReceiptScreen(state, {}, {}, {}, {}, { _, _ -> }, { _, _, _ -> }, {})
            }
        }
        compose.onRoot().captureRoboImage(
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
