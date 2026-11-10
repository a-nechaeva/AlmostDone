package com.example.mobile_android.feature.recipe.localwiring

import android.app.Application
import android.os.SystemClock
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertIsOff
import androidx.compose.ui.test.assertIsOn
import androidx.compose.ui.test.assertTextContains
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasProgressBarRangeInfo
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performTextInput
import com.dropbox.differ.SimpleImageComparator
import com.example.mobile_android.data.DemoCatalog
import com.example.mobile_android.data.DemoCatalogRepository
import com.example.mobile_android.domain.Catalog
import com.example.mobile_android.domain.CatalogRepository
import com.example.mobile_android.domain.PlannedRecipe
import com.example.mobile_android.domain.Quantity
import com.example.mobile_android.domain.QuantityUnit
import com.example.mobile_android.feature.recipe.RecipeUiHousehold
import com.example.mobile_android.ui.Screenshot
import com.example.mobile_android.ui.UiSmoke
import com.example.mobile_android.ui.theme.AlmostReadyTheme
import com.github.takahirom.roborazzi.RoborazziOptions
import com.github.takahirom.roborazzi.captureRoboImage
import java.io.File
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.experimental.categories.Category
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

private const val RECIPE_TITLE = "Паста с томатами и сыром"
private const val ADD_FAVORITE = "Сохранить рецепт в избранное"
private const val REMOVE_FAVORITE = "Убрать рецепт из избранного"
private const val SAVE_ERROR = "Не удалось сохранить изменения. Повторите действие."
private const val SCREENSHOT_FILE = "recipe-local-wiring-top-bar.png"

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], application = Application::class, qualifiers = "ru-rRU-w400dp-h900dp-notnight-xhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class RecipeLocalWiringTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    @Before
    fun freezeTime() {
        assertTrue(SystemClock.setCurrentTimeMillis(1_735_689_600_000L))
    }

    @Category(UiSmoke::class)
    @Test
    fun sameRecipeReturnsToEachSourceWithItsDraft() {
        launch(RecipeUiHousehold())
        val sources = mapOf(
            RecipeSource.Dishes to "томаты",
            RecipeSource.Graph to "одна покупка",
            RecipeSource.Favorites to "паста",
            RecipeSource.Shopping to "к ужину",
            RecipeSource.Budget to "350",
        )
        sources.entries.forEachIndexed { index, (source, draft) ->
            text(source.title).performClick()
            compose.onNodeWithTag(SOURCE_DRAFT).performTextInput(draft)
            openRecipe()
            text(RECIPE_TITLE).assertIsDisplayed()
            if (index % 2 == 0) {
                compose.onNodeWithContentDescription("Назад").performClick()
            } else {
                systemBack()
            }
            text(source.title).assertIsDisplayed()
            compose.onNodeWithTag(SOURCE_DRAFT).assertTextContains(draft)
            systemBack()
        }
    }

    @Category(UiSmoke::class)
    @Test
    fun topBarShowsOneHeartAndAllowsRetryAfterFailedWrite() {
        val gate = CompletableDeferred<Unit>()
        val household = RecipeUiHousehold().apply {
            this.gate = gate
            failWrite = true
        }
        launch(household, RecipeSource.Favorites)
        openRecipe()
        heart(ADD_FAVORITE).assertIsOff().assertIsEnabled().performClick()
        heart(ADD_FAVORITE).assertIsNotEnabled()
        text("Сохраняем изменения…").assertIsDisplayed()
        compose.runOnIdle {
            assertEquals(1, household.favoriteCalls)
            gate.complete(Unit)
        }
        waitForText(SAVE_ERROR)
        heart(ADD_FAVORITE).assertIsOff().assertIsEnabled()
        compose.runOnIdle { household.failWrite = false }
        heart(ADD_FAVORITE).performClick()
        compose.waitUntil(10_000) {
            compose.onAllNodesWithContentDescription(REMOVE_FAVORITE).fetchSemanticsNodes().size == 1
        }
        heart(REMOVE_FAVORITE).assertIsOn()
        compose.runOnIdle {
            assertEquals(2, household.favoriteCalls)
            assertEquals(setOf(RECIPE_ID), household.values.value.favoriteRecipes)
        }
        systemBack()
        text("Рецепт сохранён").assertIsDisplayed()
    }

    @Category(UiSmoke::class)
    @Test
    fun portionsAndPantryUpdateRequirementsAndSharedShoppingPlan() {
        val household = RecipeUiHousehold()
        launch(household, RecipeSource.Budget)
        openRecipe()
        text("≈230 ₽").assertIsDisplayed()
        val nutrition = "На порцию: Б 21 · Ж 17 · У 78 г"
        scrollTo(nutrition).assertIsDisplayed()
        scrollTo("Докупить: 80 г").assertIsDisplayed()
        scrollTo("Изменить порции")
        compose.onNodeWithContentDescription("Увеличить число порций").performClick()
        scrollTo("Докупить: 120 г").assertIsDisplayed()
        scrollTo(nutrition).assertIsDisplayed()
        runBlocking { household.setPantry("hard-cheese", Quantity(200.0, QuantityUnit.GRAM)) }
        scrollTo("Все продукты есть дома").assertIsDisplayed()
        text("≈0 ₽").assertIsDisplayed()
        compose.runOnIdle { household.failWrite = true }
        text("Добавить в покупки").performClick()
        waitForText(SAVE_ERROR)
        compose.runOnIdle {
            assertTrue(household.values.value.plan.isEmpty())
            household.failWrite = false
        }
        text("Добавить в покупки").performClick()
        waitForText("Обновить список покупок")
        scrollTo("Изменить порции")
        compose.onNodeWithContentDescription("Увеличить число порций").performClick()
        text("Обновить список покупок").performClick()
        compose.runOnIdle {
            assertEquals(3, household.shoppingCalls)
            assertEquals(listOf(PlannedRecipe(RECIPE_ID, 4)), household.values.value.plan)
        }
        text("Открыть покупки").performClick()
        text("Порции в покупках: 4").assertIsDisplayed()
    }

    @Category(UiSmoke::class)
    @Test
    fun missingRecipeHasNoTopBarActionAndReturnsToItsSource() {
        launch(RecipeUiHousehold(), RecipeSource.Shopping, recipeId = "absent")
        text("Открыть рецепт").performClick()
        waitForText("Рецепт не найден")
        assertNoHeart()
        text("Добавить в покупки").assertDoesNotExist()
        compose.onNodeWithContentDescription("Назад").performClick()
        text("Покупки").assertIsDisplayed()
    }

    @Category(UiSmoke::class)
    @Test
    fun loadingAndReadErrorHaveNoHeartAndRetryShowsUnknownData() {
        val catalogUpdates = MutableSharedFlow<Catalog>(replay = 1)
        val household = RecipeUiHousehold().apply { failRead = true }
        launch(household, RecipeSource.Dishes, catalog = object : CatalogRepository {
            override val catalog = catalogUpdates
        })
        text("Открыть рецепт").performClick()
        waitForText("Повторить")
        assertNoHeart()
        compose.runOnIdle { household.failRead = false }
        text("Повторить").performClick()
        compose.onNode(hasProgressBarRangeInfo(ProgressBarRangeInfo.Indeterminate))
            .assertIsDisplayed()
        assertNoHeart()
        val demo = DemoCatalog.catalog
        val recipe = checkNotNull(demo.recipe(RECIPE_ID))
        runBlocking { household.setPantry("hard-cheese", null) }
        val unknown = recipe.copy(photo = "", nutritionPerServing = null, allergenDataComplete = false)
        assertTrue(catalogUpdates.tryEmit(demo.copy(recipes = listOf(unknown))))
        waitForText("Фото отсутствует")
        heart(ADD_FAVORITE).assertIsEnabled()
        text("Фото отсутствует").assertIsDisplayed()
        text("Добавить в покупки").assertIsNotEnabled()
        scrollTo("КБЖУ на порцию: нет оценки").assertIsDisplayed()
        scrollTo("Сведения об аллергенах неполные. Нет полной оценки.").assertIsDisplayed()
        scrollTo("Количество или единицы неизвестны").assertIsDisplayed()
        compose.onNode(hasText("Нет оценки") and !hasAnyAncestor(hasTestTag("recipe-ui-content")))
            .assertIsDisplayed()
    }

    @Category(Screenshot::class)
    @Test
    fun selectedHeartInTopBarScreenshot() {
        check(System.getProperty("os.name") == "Linux" && System.getProperty("os.arch") == "amd64")
        val household = RecipeUiHousehold().apply {
            values.update { it.copy(favoriteRecipes = setOf(RECIPE_ID)) }
        }
        launch(household, RecipeSource.Favorites)
        openRecipe()
        heart(REMOVE_FAVORITE).assertIsOn()
        compose.waitForIdle()
        if (System.getProperty("roborazzi.test.verify") == "true") {
            assertTrue(File("src/test/screenshots/$SCREENSHOT_FILE").isFile)
        }
        compose.onRoot().captureRoboImage(
            SCREENSHOT_FILE,
            roborazziOptions = RoborazziOptions(
                compareOptions = RoborazziOptions.CompareOptions(
                    changeThreshold = 0f,
                    imageComparator = SimpleImageComparator(maxDistance = 0f),
                ),
            ),
        )
    }

    private fun launch(
        household: RecipeUiHousehold,
        startSource: RecipeSource? = null,
        recipeId: String = RECIPE_ID,
        catalog: CatalogRepository = DemoCatalogRepository(),
    ) {
        compose.setContent {
            AlmostReadyTheme { RecipeLocalWiringHost(household, catalog, startSource, recipeId) }
        }
    }

    private fun text(value: String) = compose.onNodeWithText(value)

    private fun waitForText(value: String) {
        compose.waitUntil(10_000) { compose.onAllNodesWithText(value).fetchSemanticsNodes().isNotEmpty() }
    }

    private fun openRecipe() {
        text("Открыть рецепт").performClick()
        waitForText(RECIPE_TITLE)
    }

    private fun systemBack() {
        compose.runOnIdle { compose.activity.onBackPressedDispatcher.onBackPressed() }
    }

    private fun scrollTo(value: String) =
        text(value).also { compose.onNodeWithTag("recipe-ui-content").performScrollToNode(hasText(value)) }

    private fun heart(description: String): SemanticsNodeInteraction {
        compose.onAllNodesWithContentDescription(description).assertCountEquals(1)
        return compose.onNode(hasContentDescription(description) and hasAnyAncestor(hasTestTag(RECIPE_TOP_BAR)))
    }

    private fun assertNoHeart() {
        compose.onNodeWithContentDescription(ADD_FAVORITE).assertDoesNotExist()
        compose.onNodeWithContentDescription(REMOVE_FAVORITE).assertDoesNotExist()
    }
}
