package com.example.mobile_android.feature.recipe

import android.app.Application
import android.os.SystemClock
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.dropbox.differ.SimpleImageComparator
import com.example.mobile_android.data.DemoCatalog
import com.example.mobile_android.data.DemoCatalogRepository
import com.example.mobile_android.domain.*
import com.example.mobile_android.feature.common.*
import com.example.mobile_android.ui.Screenshot
import com.example.mobile_android.ui.UiSmoke
import com.example.mobile_android.ui.components.*
import com.example.mobile_android.ui.theme.AlmostReadyTheme
import com.github.takahirom.roborazzi.RoborazziOptions
import com.github.takahirom.roborazzi.captureRoboImage
import java.io.File
import kotlinx.coroutines.flow.MutableSharedFlow
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
@Config(sdk = [36], application = Application::class, qualifiers = "ru-rRU-w400dp-h900dp-notnight-xhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class RecipeUiScreenTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    @Before fun freezeTime() { assertTrue(SystemClock.setCurrentTimeMillis(1_735_689_600_000L)) }
    private fun text(value: String) = compose.onNodeWithText(value)
    private fun scroll(value: String): SemanticsNodeInteraction {
        compose.onNodeWithTag("recipe-ui-content").performScrollToNode(hasText(value))
        return text(value)
    }

    private fun launch(
        state: RecipeState = recipeUiState(),
        action: ActionState = ActionState(),
        scale: Float = 1f,
        width: Int = 400,
        favorite: () -> Unit = {},
        shopping: () -> Unit = {},
        added: () -> Unit = {},
    ) {
        compose.setContent {
            CompositionLocalProvider(LocalDensity provides Density(2f, scale)) {
                AlmostReadyTheme {
                    Surface(Modifier.width(width.dp).fillMaxHeight(), color = MaterialTheme.colorScheme.background) {
                        RecipeScreen(state, action, {}, favorite, added, shopping, {})
                    }
                }
            }
        }
    }

    @Category(UiSmoke::class) @Test fun loadingWaitsForCatalogWithoutInventingRecipe() {
        val source = MutableSharedFlow<Catalog>(replay = 1)
        val vm = RecipeViewModel(object : CatalogRepository { override val catalog = source }, RecipeUiHousehold(), RecipeUiPreferences(), SavedStateHandle(mapOf("recipeId" to "cheese")))
        compose.setContent {
            val state by vm.state.collectAsStateWithLifecycle()
            AlmostReadyTheme {
                LoadContent(state, vm::retry) { RecipeScreen(it, ActionState(), {}, {}, {}, {}, {}) }
            }
        }
        compose.onNode(hasProgressBarRangeInfo(androidx.compose.ui.semantics.ProgressBarRangeInfo.Indeterminate)).assertExists()
        text("Рецепт не найден").assertDoesNotExist()
        source.tryEmit(DemoCatalog.catalog)
        compose.waitUntil(10000) { compose.onAllNodesWithText("Паста с томатами и сыром").fetchSemanticsNodes().isNotEmpty() }
        text("Паста с томатами и сыром").assertIsDisplayed()
    }

    @Category(UiSmoke::class) @Test fun missingReadyUnknownAndMissingPhotoAreDistinct() {
        val state = mutableStateOf(recipeUiState())
        compose.setContent { AlmostReadyTheme { RecipeScreen(state.value, ActionState(), {}, {}, {}, {}, {}) } }
        text("Нужно докупить: 1").assertIsDisplayed()
        scroll("Докупить: 80 г").assertIsDisplayed()
        compose.runOnIdle {
            state.value = recipeUiState(pantry = DemoCatalog.initialPantry + PantryItem("hard-cheese", Quantity(200.0, QuantityUnit.GRAM)))
        }
        scroll("Все продукты есть дома").assertIsDisplayed()
        compose.runOnIdle {
            // Неизвестно остаётся только при несовместимых единицах; без веса — достаточно.
            state.value = recipeUiState(pantry = DemoCatalog.initialPantry + PantryItem("hard-cheese", Quantity(200.0, QuantityUnit.MILLILITER)))
        }
        text("Добавить в покупки").assertIsNotEnabled()
        scroll("Количество или единицы неизвестны").assertIsDisplayed()
        val unknown = DemoCatalog.catalog.copy(
            ingredients = DemoCatalog.catalog.ingredients.map { it.copy(offer = null) },
            recipes = DemoCatalog.catalog.recipes.map { it.copy(photo = "", nutritionPerServing = null, allergenDataComplete = false) },
        )
        compose.runOnIdle { state.value = recipeUiState(catalog = unknown) }
        scroll("Фото отсутствует").assertIsDisplayed()
        scroll("КБЖУ на порцию: нет оценки").assertIsDisplayed()
        scroll("Сведения об аллергенах неполные. Нет полной оценки.").assertIsDisplayed()
    }

    @Category(UiSmoke::class) @Test fun missingRecipeAndEmptyStepsHaveExplicitStates() {
        val state = mutableStateOf(recipeUiState("absent"))
        compose.setContent { AlmostReadyTheme { RecipeScreen(state.value, ActionState(), {}, {}, {}, {}, {}) } }
        text("Рецепт не найден").assertIsDisplayed()
        text("Добавить в покупки").assertDoesNotExist()
        compose.runOnIdle {
            state.value = recipeUiState(catalog = DemoCatalog.catalog.copy(recipes = DemoCatalog.catalog.recipes.map { it.copy(steps = emptyList()) }))
        }
        scroll("К шагам →").performClick()
        text("Шаги приготовления пока отсутствуют").assertIsDisplayed()
    }

    @Config(qualifiers = "ru-rRU-w360dp-h900dp-notnight-xhdpi")
    @Category(UiSmoke::class) @Test fun narrowLargeFontSupportsStepsAndCallbacks() {
        var favorites = 0
        var purchases = 0
        launch(scale = 1.5f, width = 360, favorite = { favorites++ }, added = { purchases++ })
        scroll("Паста с томатами и сыром").assertIsDisplayed()
        compose.onNodeWithContentDescription("Сохранить рецепт в избранное").performClick()
        text("Добавить в покупки").performClick()
        assertEquals(1, favorites); assertEquals(1, purchases)
        scroll("К шагам →").performClick()
        scroll("Натрите сыр, добавьте к пасте и подавайте.").assertIsDisplayed()
    }

    @Config(qualifiers = "ru-rRU-w360dp-h900dp-notnight-xhdpi")
    @Category(UiSmoke::class) @Test fun longLabelsRemainReachableAtLargeFont() {
        val title = "Паста с томатами и выдержанным сыром для семейного обеда"
        val ingredient = "Твёрдый выдержанный сыр с очень длинным названием продукта"
        val catalog = DemoCatalog.catalog.copy(
            recipes = DemoCatalog.catalog.recipes.map { it.copy(title = title) },
            ingredients = DemoCatalog.catalog.ingredients.map { if (it.id == "hard-cheese") it.copy(name = ingredient) else it },
        )
        launch(state = recipeUiState(catalog = catalog), scale = 1.5f, width = 360)
        scroll(title).assertIsDisplayed()
        scroll(ingredient).assertIsDisplayed()
        text("Добавить в покупки").assertIsDisplayed().assertHasClickAction()
        scroll("К шагам →").performClick()
        scroll("Натрите сыр, добавьте к пасте и подавайте.").assertIsDisplayed()
    }

    @Category(UiSmoke::class) @Test fun loadingRetryPendingFailureAndRepositoryCallbacks() {
        val h = RecipeUiHousehold().apply { failRead = true }
        val vm = RecipeViewModel(DemoCatalogRepository(), h, RecipeUiPreferences(), SavedStateHandle(mapOf("recipeId" to "cheese")))
        compose.setContent {
            val state by vm.state.collectAsStateWithLifecycle()
            val action by vm.actions.state.collectAsStateWithLifecycle()
            AlmostReadyTheme {
                LoadContent(state, vm::retry) {
                    RecipeScreen(it, action, vm::servingsChanged, vm::favorite, vm::addToShopping, {}, vm.actions::dismiss)
                }
            }
        }
        compose.waitUntil(10000) { compose.onAllNodesWithText("Повторить").fetchSemanticsNodes().isNotEmpty() }
        h.failRead = false; text("Повторить").performClick()
        compose.waitUntil(10000) { compose.onAllNodesWithText("Добавить в покупки").fetchSemanticsNodes().isNotEmpty() }
        h.gate = kotlinx.coroutines.CompletableDeferred()
        text("Добавить в покупки").performClick()
        text("Сохраняем изменения…").assertIsDisplayed()
        text("Добавить в покупки").assertIsNotEnabled()
        compose.onNodeWithContentDescription("Сохранить рецепт в избранное").assertIsNotEnabled()
        h.failWrite = true; h.gate!!.complete(Unit)
        compose.waitUntil(10000) { compose.onAllNodesWithText("Не удалось сохранить изменения. Повторите действие.").fetchSemanticsNodes().isNotEmpty() }
        h.failWrite = false; text("Добавить в покупки").performClick()
        compose.waitUntil(10000) { compose.onAllNodesWithText("Открыть покупки").fetchSemanticsNodes().isNotEmpty() }
        assertEquals(2, h.shoppingCalls)
        text("Обновить список покупок").assertIsEnabled()
    }

    @Category(UiSmoke::class) @Test fun scrollStepsPreserveHostBackAndSource() {
        compose.setContent {
            var recipe by remember { mutableStateOf(true) }
            AlmostReadyTheme {
                if (recipe) {
                    androidx.activity.compose.BackHandler { recipe = false }
                    Column {
                        BrandTopBar("Рецепт", onBack = { recipe = false })
                        RecipeScreen(recipeUiState(), ActionState(), {}, {}, {}, {}, {})
                    }
                } else Text("Источник: избранное")
            }
        }
        scroll("К шагам →").performClick()
        text("Как приготовить").assertIsDisplayed()
        compose.runOnIdle { compose.activity.onBackPressedDispatcher.onBackPressed() }
        text("Источник: избранное").assertIsDisplayed()
    }

    @Category(Screenshot::class) @Test fun detailScreenshot() = screenshot("detail")
    @Config(qualifiers = "ru-rRU-w360dp-h900dp-notnight-xhdpi")
    @Category(Screenshot::class) @Test fun narrowLargeFontScreenshot() = screenshot("narrow-large-font", scale = 1.5f, width = 360)
    @Category(Screenshot::class) @Test fun readyScreenshot() = screenshot("ready", state = recipeUiState(pantry = DemoCatalog.initialPantry + PantryItem("hard-cheese", Quantity(200.0, QuantityUnit.GRAM))))
    @Category(Screenshot::class) @Test fun stepsScreenshot() = screenshot("steps", steps = true)
    @Category(Screenshot::class) @Test fun unknownScreenshot() {
        val catalog = DemoCatalog.catalog.copy(
            recipes = DemoCatalog.catalog.recipes.map { it.copy(nutritionPerServing = null, allergenDataComplete = false, photo = "") },
        )
        screenshot("unknown", state = recipeUiState(catalog = catalog, pantry = DemoCatalog.initialPantry + PantryItem("hard-cheese", null)))
    }

    private fun screenshot(name: String, scale: Float = 1f, width: Int = 400, steps: Boolean = false, state: RecipeState = recipeUiState()) {
        check(System.getProperty("os.name") == "Linux" && System.getProperty("os.arch") == "amd64")
        launch(state, scale = scale, width = width)
        if (steps) scroll("К шагам →").performClick()
        compose.waitForIdle()
        val file = "recipe-ui-$name.png"
        if (System.getProperty("roborazzi.test.verify") == "true") assertTrue(File("src/test/screenshots/$file").isFile)
        compose.onRoot().captureRoboImage(file, roborazziOptions = RoborazziOptions(compareOptions = RoborazziOptions.CompareOptions(changeThreshold = 0f, imageComparator = SimpleImageComparator(maxDistance = 0f))))
    }
}
