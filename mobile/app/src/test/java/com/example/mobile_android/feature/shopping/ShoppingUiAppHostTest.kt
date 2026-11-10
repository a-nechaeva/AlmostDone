package com.example.mobile_android.feature.shopping

import android.app.Application
import android.os.SystemClock
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import com.dropbox.differ.SimpleImageComparator
import com.example.mobile_android.app.AppDependencies
import com.example.mobile_android.data.DemoCatalogRepository
import com.example.mobile_android.domain.SessionRepository
import com.example.mobile_android.navigation.AppRoot
import com.example.mobile_android.ui.Screenshot
import com.example.mobile_android.ui.UiSmoke
import com.example.mobile_android.ui.theme.AlmostReadyTheme
import com.github.takahirom.roborazzi.RoborazziOptions
import com.github.takahirom.roborazzi.captureRoboImage
import java.io.File
import kotlinx.coroutines.flow.flowOf
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
class ShoppingUiAppHostTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val dependencies =
        object : AppDependencies {
            override val catalog = DemoCatalogRepository()
            override val household = ShoppingUiHousehold()
            override val preferences = ShoppingUiPreferences()
            override val session =
                object : SessionRepository {
                    override val signedIn = flowOf(true)

                    override suspend fun signIn(login: String, password: String) = Unit

                    override suspend fun signOut() = Unit
                }
        }

    @Before
    fun launch() {
        assertTrue(SystemClock.setCurrentTimeMillis(1_735_689_600_000L))
        compose.setContent { AlmostReadyTheme { AppRoot(dependencies) } }
        compose.waitUntil(10000) {
            compose.onAllNodesWithText("Мои продукты").fetchSemanticsNodes().isNotEmpty()
        }
        compose
            .onNode(
                hasText("Покупки") and
                    SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Tab),
            )
            .performClick()
        compose.waitUntil(10000) {
            compose.onAllNodesWithText("Что докупить").fetchSemanticsNodes().isNotEmpty()
        }
    }

    @Category(UiSmoke::class)
    @Test
    fun existingApplicationHostKeepsShoppingAndBudgetBackCompatible() {
        compose.onNodeWithText("Подобрать покупки под бюджет").performScrollTo().performClick()
        compose.onNodeWithText("Сколько потратим?").assertIsDisplayed()
        compose.onNodeWithContentDescription("Назад").performClick()
        compose.onNodeWithText("Что докупить").performScrollTo().assertIsDisplayed()
        compose.onNodeWithText("Добавить план в покупки").assertDoesNotExist()
    }

    @Category(Screenshot::class)
    @Test
    fun applicationShoppingScreenshot() {
        check(System.getProperty("os.name") == "Linux" && System.getProperty("os.arch") == "amd64")
        val name = "shopping-ui-app.png"
        if (System.getProperty("roborazzi.test.verify") == "true")
            assertTrue(File("src/test/screenshots/$name").isFile)
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
                            ),
                    ),
            )
    }
}
