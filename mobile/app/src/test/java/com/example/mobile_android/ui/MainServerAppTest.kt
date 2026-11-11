package com.example.mobile_android.ui

import android.app.Application
import androidx.activity.ComponentActivity
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import com.example.mobile_android.app.AppDependencies
import com.example.mobile_android.data.remote.*
import com.example.mobile_android.domain.SessionRepository
import com.example.mobile_android.navigation.AppRoot
import com.example.mobile_android.ui.theme.AlmostReadyTheme
import java.util.concurrent.CopyOnWriteArrayList
import kotlinx.coroutines.flow.MutableStateFlow
import org.json.JSONObject
import org.junit.Assert.*
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
@Category(UiSmoke::class)
class MainServerAppTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun signsInWithFakeSdkNavigatesUnavailableScreensAndLogsOut() {
        val requests = CopyOnWriteArrayList<HttpRequest>()
        val api = ApiClient("https://api.example.test", HttpTransport { request ->
            requests += request
            when (request.url.encodedPath) {
                "/api/v1/auth/yandex" -> session("signed-in")
                "/api/v1/me/state" -> state()
                "/api/v1/auth/logout" -> HttpResponse(204)
                else -> error("Unexpected request")
            }
        })
        val dependencies = object : AppDependencies {
            override val session = ServerSessionRepository(api, MemorySessionStore())
            override val yandexLogin = FakeYandexLogin()
        }
        compose.setContent { AlmostReadyTheme { AppRoot(dependencies) } }

        awaitText("Войти через Яндекс ID")
        compose.onNodeWithText("Пароль").assertDoesNotExist()
        compose.onNodeWithText("Войти через Яндекс ID").performClick()
        awaitText("Мои продукты")
        compose.onNodeWithText("Пока недоступно").assertIsDisplayed()
        compose.onNodeWithContentDescription("Добавить продукт").assertIsNotEnabled()
        assertEquals("fake-yandex-token", JSONObject(requests[0].body).getString("oauth_token"))
        assertEquals("Bearer access-signed-in", requests[1].headers["Authorization"])

        compose.onNodeWithContentDescription("Добавить по фото чека").performClick()
        awaitText("Добавить по фото")
        compose.onNodeWithText("Пока недоступно").assertIsDisplayed()
        compose.onNodeWithText("Продукты").performClick()
        awaitText("Распознавание продуктов по фото ещё подключается.")
        compose.onNodeWithText("Сделать фото").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithText("Выбрать из галереи").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithContentDescription("Назад").performClick()
        awaitText("Мои продукты")

        tab("Блюда").performClick()
        awaitText("Что приготовим?")
        compose.onNodeWithText("Граф").performClick()
        awaitText("Больше блюд с одной покупкой")
        compose.onNodeWithText("Граф").assertIsSelected()
        compose.onNodeWithText("Пока недоступно").assertIsDisplayed()
        compose.onNodeWithText("Изменить продукты дома").performClick()
        awaitText("Мои продукты")
        tab("Блюда").performClick()
        awaitText("Больше блюд с одной покупкой")
        compose.onNodeWithText("Скрытые блюда").performClick()
        awaitText("Почему блюда скрыты")
        compose.onNodeWithContentDescription("Назад").performClick()

        tab("Покупки").performClick()
        awaitText("Что докупить")
        compose.onNodeWithText("Подобрать покупки").assertIsNotEnabled()
        tab("Профиль").performClick()
        awaitText("Яндекс ID")
        compose.onNodeWithText("Питание и аллергены").assertIsNotEnabled()
        compose.onNodeWithText("Избранное").performClick()
        compose.onNodeWithText("Пока недоступно").assertIsDisplayed()
        compose.onNodeWithContentDescription("Назад").performClick()
        awaitText("Яндекс ID")
        compose.onNodeWithText("Выйти").performScrollTo().performClick()
        awaitText("Выйти из аккаунта?")
        compose.onNode(hasText("Выйти") and hasAnyAncestor(isDialog())).performClick()
        awaitText("Войти через Яндекс ID")
        compose.waitUntil(10_000) { requests.size == 3 }
        assertEquals(listOf("/api/v1/auth/yandex", "/api/v1/me/state", "/api/v1/auth/logout"), requests.map { it.url.encodedPath })
        assertEquals("Bearer access-signed-in", requests.last().headers["Authorization"])
    }

    @Test
    fun restoredNavigationIsKeptOnlyForTheSameVerifiedSession() {
        val key = MutableStateFlow<String?>("account-a-session")
        val dependencies = object : AppDependencies {
            override val yandexLogin = FakeYandexLogin()
            override val session = object : SessionRepository {
                override val sessionKey = key
                override suspend fun signInWithToken(token: String) {
                    key.value = "account-b-session"
                }
                override suspend fun signOut() {
                    key.value = null
                }
            }
        }
        var rejectOnRestore = false
        val restoration = StateRestorationTester(compose)
        restoration.setContent {
            DisposableEffect(Unit) {
                onDispose {
                    if (rejectOnRestore) key.value = null
                }
            }
            AlmostReadyTheme { AppRoot(dependencies) }
        }
        awaitText("Мои продукты")
        tab("Профиль").performClick()
        awaitText("Яндекс ID")
        restoration.emulateSavedInstanceStateRestore()
        awaitText("Яндекс ID")

        compose.runOnIdle { rejectOnRestore = true }
        restoration.emulateSavedInstanceStateRestore()
        awaitText("Войти через Яндекс ID")
        compose.onNodeWithText("Войти через Яндекс ID").performClick()
        awaitText("Мои продукты")
        compose.onNodeWithText("Яндекс ID").assertDoesNotExist()
    }

    private fun awaitText(text: String) {
        compose.waitUntil(10_000) { compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty() }
    }

    private fun tab(text: String) = compose.onNode(
        hasText(text) and SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Tab)
    )
}
