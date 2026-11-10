package com.example.mobile_android.feature.favorites

import android.app.Application
import android.os.SystemClock
import androidx.activity.ComponentActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.Density
import com.example.mobile_android.app.AppDependencies
import com.example.mobile_android.data.DemoCatalog
import com.example.mobile_android.domain.*
import com.example.mobile_android.navigation.AppRoot
import com.example.mobile_android.ui.UiSmoke
import com.example.mobile_android.ui.theme.AlmostReadyTheme
import com.yandex.authsdk.YandexAuthOptions
import com.yandex.authsdk.YandexAuthSdk
import kotlinx.coroutines.flow.flowOf
import org.junit.Assert.assertTrue
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
@Config(sdk = [36], application = Application::class,
    qualifiers = "ru-rRU-w400dp-h900dp-notnight-xhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Category(UiSmoke::class)
class FavoritesNavigationTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    @Before fun freezeTime() {
        assertTrue(SystemClock.setCurrentTimeMillis(1_735_689_600_000L))
        compose.mainClock.autoAdvance = true
    }

    @Test fun existingNavigationOpensExactRecipeAndBackRestoresScroll() {
        val recipes = (0..25).map { DemoCatalog.catalog.recipes.first().copy(id = "favorite/item $it", title = "Любимое блюдо $it") }
        val data = DemoCatalog.catalog.copy(recipes = recipes)
        val dependencies = object : AppDependencies {
            override val catalog = object : CatalogRepository { override val catalog = flowOf(data) }
            override val household = FavoritesHouseholdFake(Household(favoriteRecipes = recipes.map { it.id }.toSet()))
            override val preferences = FavoritesPreferencesFake()
            override val session = object : SessionRepository {
                override val signedIn = flowOf(true)
                override suspend fun signIn(login: String, password: String) = Unit
                override suspend fun signInWithToken(token: String) = Unit
                override suspend fun signOut() = Unit
            }
            override val yandexAuth by lazy {
                YandexAuthSdk.create(YandexAuthOptions(RuntimeEnvironment.getApplication()))
            }
        }
        compose.setContent {
            CompositionLocalProvider(LocalDensity provides Density(2f, 1f)) {
                AlmostReadyTheme { AppRoot(dependencies) }
            }
        }
        compose.waitUntil(10_000) { compose.onAllNodesWithText("Мои продукты").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithContentDescription("Избранное").performClick()
        compose.onNodeWithTag("favorites-list").performScrollToIndex(15)
        compose.onNodeWithText("Любимое блюдо 15").assertIsDisplayed().performClick()
        compose.onNodeWithContentDescription("Пример подачи: Любимое блюдо 15").assertIsDisplayed()
        compose.onNodeWithContentDescription("Назад").performClick()
        compose.onNodeWithTag("favorites-list").assertExists()
        compose.onNodeWithText("Любимое блюдо 15").assertIsDisplayed()
        compose.onNodeWithText("Блюда").assertIsSelected()
    }
}
