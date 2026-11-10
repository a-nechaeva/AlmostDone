package com.example.mobile_android.feature.dishes

import android.app.Application
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import com.example.mobile_android.data.DemoCatalog
import com.example.mobile_android.domain.Allergen
import com.example.mobile_android.domain.FoodPreferences
import com.example.mobile_android.feature.FakePreferences
import com.example.mobile_android.ui.UiSmoke
import org.junit.Assert.assertEquals
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
@Category(UiSmoke::class)
class DishesLocalHostTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val catalog = DishesHostCatalog()
    private val preferences = FakePreferences()

    @Test
    fun hiddenUsesSameQueryAvailabilityAndAllergensAndOpensRecipeById() {
        preferences.values.value = FoodPreferences(excludedAllergens = setOf(Allergen.GLUTEN))
        compose.setContent { DishesLocalHost(catalog, preferences) }

        await("Что приготовим?")
        compose.onNode(hasSetTextAction()).performTextInput("Омлет")
        compose.onNodeWithContentDescription("Открыть фильтры").performClick()
        compose.onNodeWithText("До 15 мин").performClick()
        compose.onNodeWithText("Молоко").assertIsOff().performClick().assertIsOn()
        compose.onNodeWithContentDescription("Закрыть фильтры").performClick()
        dish("Докупить 1–3").performClick()
        await("Скрытые блюда (1)")
        dish("Скрытые блюда (1)").performClick()

        await("Почему блюда скрыты")
        dish("Омлет с сыром").assertIsDisplayed()
        dish("Содержит: Молоко").assertIsDisplayed()
        compose.onNodeWithText("Омлет с томатами").assertDoesNotExist()
        dish("Омлет с сыром").performClick()
        await("Рецепт cheeseEgg")
        back()
        await("Почему блюда скрыты")
        dish("Изменить фильтры").performClick()
        compose.onNodeWithText("Молоко").assertIsOn()
        compose.onNodeWithContentDescription("Закрыть фильтры").performClick()
        back()
        await("Что приготовим?")
        compose.onNode(hasSetTextAction()).assertTextEquals("Омлет")
        dish("Докупить 1–3").assertIsSelected()
        dish("Без молока").assertIsDisplayed()
        dish("Скрытые блюда (1)").assertIsDisplayed()
        assertEquals(setOf(Allergen.GLUTEN), preferences.values.value.excludedAllergens)
    }

    @Test
    fun errorRetryLoadingAndEmptyResults() {
        val gatedCatalog = DishesHostCatalog(ready = false).apply { failRead = true }
        compose.setContent { DishesLocalHost(gatedCatalog, preferences) }
        await("Блюда не загрузились")
        gatedCatalog.failRead = false
        compose.onNodeWithText("Попробовать снова").performClick()
        await("Подбираем блюда")
        gatedCatalog.values.tryEmit(DemoCatalog.catalog)
        await("Что приготовим?")
        compose.onNode(hasSetTextAction()).performTextInput("нет такого блюда")
        await("Подходящих блюд нет")
        dish("Сбросить фильтры").performClick()
        dish("Омлет с томатами").assertIsDisplayed()
    }

    @Test
    fun changingQueryHidesPreviousCountAndResultsWhileKeepingInputEditable() {
        val computation = QueuedDishesDispatcher()
        preferences.values.value = FoodPreferences(excludedAllergens = setOf(Allergen.GLUTEN))
        compose.setContent { DishesLocalHost(catalog, preferences, computation = computation) }
        compose.waitUntil(10_000) { computation.hasWork }
        compose.runOnIdle { computation.runNext() }
        await("Что приготовим?")
        dish("Скрытые блюда (2)").assertIsDisplayed()
        dish("Найти блюдо").performTextInput("Омлет")
        compose.waitUntil(10_000) { computation.hasWork }

        await("Уточняем подбор")
        compose.onNode(hasSetTextAction()).assertTextEquals("Омлет").assertIsEnabled()
        compose.onNodeWithText("Скрытые блюда (2)").assertDoesNotExist()
        compose.onNodeWithText("Омлет с томатами").assertDoesNotExist()
        compose.runOnIdle { computation.runNext() }
        await("Омлет с томатами")
        compose.onNodeWithText("Скрытые блюда (2)").assertDoesNotExist()
    }

    private fun dish(text: String): SemanticsNodeInteraction {
        compose.onNodeWithTag("dishes-results").performScrollToNode(hasText(text))
        return compose.onNodeWithText(text)
    }

    private fun await(text: String) {
        compose.waitUntil(10_000) {
            compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun back() {
        compose.runOnIdle { compose.activity.onBackPressedDispatcher.onBackPressed() }
    }
}
