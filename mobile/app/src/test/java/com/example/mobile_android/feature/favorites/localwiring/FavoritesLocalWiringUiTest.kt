package com.example.mobile_android.feature.favorites.localwiring

import android.app.Application
import android.os.Looper
import android.os.SystemClock
import androidx.activity.ComponentActivity
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.viewModelScope
import com.example.mobile_android.data.DemoCatalog
import com.example.mobile_android.domain.Household
import com.example.mobile_android.domain.Ingredient
import com.example.mobile_android.domain.PantryItem
import com.example.mobile_android.domain.Quantity
import com.example.mobile_android.domain.QuantityUnit
import com.example.mobile_android.feature.common.ScreenState
import com.example.mobile_android.feature.dishes.DishesViewModel
import com.example.mobile_android.feature.favorites.FavoritesIngredientSelection
import com.example.mobile_android.feature.pantry.PantryViewModel
import com.example.mobile_android.ui.UiSmoke
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import org.junit.Assert.*
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.experimental.categories.Category
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], application = Application::class, qualifiers = "ru-rRU-w400dp-h900dp-notnight-xhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Category(UiSmoke::class)
class FavoritesLocalWiringUiTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    @Before fun freezeTime() {
        assertTrue(SystemClock.setCurrentTimeMillis(1_735_689_600_000L))
    }

    @Test fun addsToExistingQuantityAndUpdatesPantryDishesAndRecipe() {
        val fixture = FavoritesLocalWiringFixture(
            initial = Household(
                pantry = DemoCatalog.initialPantry.map {
                    if (it.ingredientId == "tomatoes") it.copy(quantity = Quantity(50.0, QuantityUnit.GRAM))
                    else it
                },
                favoriteRecipes = setOf("omelette"),
                favoriteIngredients = setOf("tomatoes"),
            ),
        )
        val pantry = PantryViewModel(fixture.catalog, fixture.household, SavedStateHandle())
        val dishes = DishesViewModel(
            fixture.catalog, fixture.household, fixture.preferences, SavedStateHandle(),
            Dispatchers.Main.immediate,
        )
        try {
            compose.setContent {
                LaunchedEffect(Unit) {
                    launch { pantry.state.collect {} }
                    launch { dishes.state.collect {} }
                }
                FavoritesLocalWiringHost(fixture)
            }
            text("Омлет с томатами").assertIsDisplayed().performClick()
            text("Нужно докупить: 1").assertIsDisplayed()
            back()
            openQuantity("Томаты")
            text("Есть дома: 50 г", inDialog = true).assertIsDisplayed()
            text("Количество, г").performTextInput("75,5")
            text("Добавить в продукты").performClick()
            compose.onNode(isDialog()).assertDoesNotExist()
            text("Есть дома: 125,5 г").assertIsDisplayed()
            compose.runOnIdle {
                val pantryState = (pantry.state.value as ScreenState.Ready).data
                assertEquals(
                    Quantity(125.5, QuantityUnit.GRAM),
                    pantryState.added.single { it.first.id == "tomatoes" }.second.quantity,
                )
                val dishesState = (dishes.state.value as ScreenState.Ready).data
                assertTrue(dishesState.matches.single { it.recipe.id == "omelette" }.ready)
                assertEquals(
                    listOf(FavoritesIngredientSelection("tomatoes", Quantity(75.5, QuantityUnit.GRAM))),
                    fixture.household.pantryAdds,
                )
            }
            text("Блюда").performClick()
            text("Все продукты есть").assertIsDisplayed()
            text("Омлет с томатами").performClick()
            text("Все продукты есть дома").assertIsDisplayed()
        } finally {
            pantry.viewModelScope.cancel()
            dishes.viewModelScope.cancel()
        }
    }

    @Test fun blankQuantityRemainsUnknownInSharedPantry() {
        val fixture = FavoritesLocalWiringFixture()
        compose.setContent { FavoritesLocalWiringHost(fixture) }
        openQuantity("Яйца")
        text("Добавить в продукты").performClick()
        compose.onNode(isDialog()).assertDoesNotExist()
        text("Есть дома: Количество неизвестно").assertIsDisplayed()
        compose.runOnIdle {
            assertEquals(listOf(FavoritesIngredientSelection("eggs", null)), fixture.household.pantryAdds)
            assertEquals(PantryItem("eggs", null), fixture.household.values.value.pantry.single {
                it.ingredientId == "eggs"
            })
        }
    }

    @Test fun pendingWriteLocksDialogAndFailureKeepsDraftForRetry() {
        val fixture = FavoritesLocalWiringFixture()
        val gate = CompletableDeferred<Unit>()
        fixture.household.pantryGate = gate
        fixture.household.failAdd = true
        compose.setContent { FavoritesLocalWiringHost(fixture) }
        openQuantity("Томаты")
        text("Количество, г").performTextInput("25")
        val confirm = clickAction("Добавить в продукты")
        val cancel = clickAction("Отмена")
        compose.runOnIdle {
            confirm()
            // Invoke the previous frame's action before Compose disables the button.
            cancel()
        }
        text("Добавляем в продукты…").assertIsDisplayed()
        text("Добавить в продукты").assertIsNotEnabled()
        text("Количество, г").assertIsNotEnabled()
        text("Отмена").assertIsNotEnabled()
        back()
        text("Добавляем в продукты…").assertIsDisplayed()
        compose.runOnIdle {
            assertEquals(1, fixture.household.pantryAdds.size)
            gate.complete(Unit)
        }
        text("Не удалось добавить продукт.").assertIsDisplayed()
        text("Количество, г").assertTextContains("25")
        text("Повторить").assertIsEnabled()
        text("Есть дома: 500 г", inDialog = true).assertIsDisplayed()
        compose.runOnIdle { fixture.household.failAdd = false }
        text("Повторить").performClick()
        compose.onNode(isDialog()).assertDoesNotExist()
        text("Есть дома: 525 г").assertIsDisplayed()
        compose.runOnIdle {
            val selection = FavoritesIngredientSelection("tomatoes", Quantity(25.0, QuantityUnit.GRAM))
            assertEquals(listOf(selection, selection), fixture.household.pantryAdds)
        }
    }

    @Test fun exactRecipeAndBothListPositionsSurviveBackAndReload() {
        val recipes = (0..25).map {
            DemoCatalog.catalog.recipes.first().copy(id = "favorite/item $it", title = "Любимое блюдо $it")
        }
        val ingredients = (0..35).map { Ingredient("i$it", "Ингредиент $it", QuantityUnit.GRAM) }
        val fixture = FavoritesLocalWiringFixture(
            DemoCatalog.catalog.copy(
                recipes = recipes,
                ingredients = DemoCatalog.catalog.ingredients + ingredients,
            ),
            Household(
                favoriteRecipes = recipes.map { it.id }.toSet(),
                favoriteIngredients = ingredients.map { it.id }.toSet(),
            ),
        )
        compose.setContent { FavoritesLocalWiringHost(fixture) }
        compose.onNodeWithTag("favorites-list").performScrollToIndex(15)
        text("Любимое блюдо 15").assertIsDisplayed()
        text("Ингредиенты").performClick().assertIsSelected()
        compose.onNodeWithTag("favorites-list").performScrollToIndex(18)
        text("Ингредиент 18").assertIsDisplayed()
        text("Блюда").performClick().assertIsSelected()
        text("Любимое блюдо 15").assertIsDisplayed().performClick()
        compose.onNodeWithContentDescription("Пример подачи: Любимое блюдо 15").assertIsDisplayed()

        val gate = CompletableDeferred<Unit>()
        compose.runOnIdle { fixture.catalogGate = gate }
        Shadows.shadowOf(Looper.getMainLooper()).idleFor(6, TimeUnit.SECONDS)
        back()
        compose.onNodeWithTag("favorites-list").assertDoesNotExist()
        compose.runOnIdle { gate.complete(Unit) }
        text("Блюда").assertIsSelected()
        text("Любимое блюдо 15").assertIsDisplayed()
        text("Ингредиенты").performClick().assertIsSelected()
        text("Ингредиент 18").assertIsDisplayed()
    }

    @Test fun instantFailuresRequireANewClickFromTheRetryButton() {
        val fixture = FavoritesLocalWiringFixture()
        fixture.household.failAdd = true
        compose.setContent { FavoritesLocalWiringHost(fixture) }
        openQuantity("Томаты")
        text("Количество, г").performTextInput("25")

        val confirm = clickAction("Добавить в продукты")
        compose.runOnIdle {
            confirm()
            confirm()
            assertEquals(1, fixture.household.pantryAdds.size)
        }
        val retry = clickAction("Повторить")
        compose.runOnIdle {
            retry()
            retry()
            assertEquals(2, fixture.household.pantryAdds.size)
            fixture.household.failAdd = false
        }
        text("Количество, г").assertTextContains("25")
        text("Повторить").performClick()
        compose.onNode(isDialog()).assertDoesNotExist()
        text("Есть дома: 525 г").assertIsDisplayed()
        compose.runOnIdle { assertEquals(3, fixture.household.pantryAdds.size) }
    }

    private fun text(value: String, inDialog: Boolean = false): SemanticsNodeInteraction =
        if (inDialog) compose.onNode(hasText(value) and hasAnyAncestor(isDialog()))
        else compose.onNodeWithText(value)

    private fun clickAction(label: String): () -> Boolean =
        requireNotNull(text(label).fetchSemanticsNode().config[SemanticsActions.OnClick].action)

    private fun openQuantity(ingredient: String) {
        text("Ингредиенты").performClick().assertIsSelected()
        compose.onNodeWithContentDescription("Указать количество: $ingredient").performClick()
    }

    private fun back() = compose.runOnIdle { compose.activity.onBackPressedDispatcher.onBackPressed() }
}
