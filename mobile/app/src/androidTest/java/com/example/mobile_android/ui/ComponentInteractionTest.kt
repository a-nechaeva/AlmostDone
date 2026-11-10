package com.example.mobile_android.ui

import androidx.compose.runtime.*
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.example.mobile_android.data.DemoCatalog
import com.example.mobile_android.domain.*
import com.example.mobile_android.feature.profile.PreferenceToggle
import com.example.mobile_android.ui.components.QuantityDialog
import com.example.mobile_android.ui.components.RecipeCard
import com.example.mobile_android.ui.theme.AlmostReadyTheme
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ComponentInteractionTest {
    @get:Rule val compose = createComposeRule()

    @Test
    fun labelledCheckboxRowIsOneClickableAccessibleControl() {
        var checked by mutableStateOf(false)
        compose.setContent {
            AlmostReadyTheme { PreferenceToggle("Молоко", checked, true) { checked = it } }
        }
        compose
            .onNode(hasText("Молоко") and isToggleable())
            .assertHasClickAction()
            .performClick()
            .assertIsOn()
        compose.runOnIdle { assertTrue(checked) }
    }

    @Test
    fun favoriteButtonDoesNotAlsoOpenTheRecipe() {
        val opens = AtomicInteger()
        val favorites = AtomicInteger()
        val recipe = DemoCatalog.catalog.recipe("omelette")!!
        val match =
            matchRecipe(recipe, DemoCatalog.initialPantry, DemoCatalog.catalog, FoodPreferences())
        compose.setContent {
            AlmostReadyTheme {
                RecipeCard(
                    match,
                    false,
                    { opens.incrementAndGet() },
                    { favorites.incrementAndGet() },
                )
            }
        }
        compose.onNodeWithContentDescription("В избранное: ${recipe.title}").performClick()
        compose.runOnIdle {
            assertEquals(0, opens.get())
            assertEquals(1, favorites.get())
        }
        compose.onNodeWithText(recipe.title).performClick()
        compose.runOnIdle { assertEquals(1, opens.get()) }
    }

    @Test
    fun invalidQuantityCannotBeSavedAndBlankMeansUnknown() {
        val ingredient = DemoCatalog.catalog.ingredient("tomatoes")!!
        var saved = false
        var quantity: Quantity? = Quantity(1.0, QuantityUnit.GRAM)
        compose.setContent {
            AlmostReadyTheme {
                QuantityDialog(
                    ingredient,
                    null,
                    false,
                    {},
                    {
                        saved = true
                        quantity = it
                    },
                )
            }
        }
        compose.onNode(hasSetTextAction()).performTextReplacement("-1")
        compose.onNodeWithText("Добавить").assertIsNotEnabled()
        compose.onNode(hasSetTextAction()).performTextReplacement("")
        compose.onNodeWithText("Добавить").assertIsEnabled().performClick()
        compose.runOnIdle {
            assertTrue(saved)
            assertNull(quantity)
        }
    }
}
