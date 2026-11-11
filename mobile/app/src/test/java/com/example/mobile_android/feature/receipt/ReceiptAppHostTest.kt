package com.example.mobile_android.feature.receipt

import android.app.Activity
import android.app.Application
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.os.SystemClock
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import com.example.mobile_android.app.AppDependencies
import com.example.mobile_android.data.DemoCatalogRepository
import com.example.mobile_android.domain.Allergen
import com.example.mobile_android.domain.FoodPreferences
import com.example.mobile_android.domain.FoodType
import com.example.mobile_android.domain.HouseholdRepository
import com.example.mobile_android.domain.PlannedRecipe
import com.example.mobile_android.domain.Quantity
import com.example.mobile_android.domain.QuantityUnit
import com.example.mobile_android.domain.SessionRepository
import com.example.mobile_android.feature.FakeHousehold
import com.example.mobile_android.feature.FakePreferences
import com.example.mobile_android.feature.shopping.ShoppingBudgetPlanFake
import com.example.mobile_android.feature.shopping.ShoppingUiHousehold
import com.example.mobile_android.navigation.AppRoot
import com.example.mobile_android.ui.UiSmoke
import com.example.mobile_android.ui.theme.AlmostReadyTheme
import com.yandex.authsdk.YandexAuthOptions
import com.yandex.authsdk.YandexAuthSdk
import java.io.File
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.flowOf
import org.junit.Assert.*
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.experimental.categories.Category
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(
    sdk = [36], application = Application::class,
    qualifiers = "ru-rRU-w400dp-h900dp-notnight-xhdpi",
)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Category(UiSmoke::class)
class ReceiptAppHostTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val household = FakeHousehold()
    private val preferences = FakePreferences()
    private val shopping = ShoppingUiHousehold()
    private val budget = ShoppingBudgetPlanFake(shopping)
    private var favoriteGate: CompletableDeferred<Unit>? = null

    @Before fun freezeTime() {
        assertTrue(SystemClock.setCurrentTimeMillis(1_735_689_600_000L))
    }

    @Test
    fun pantryOpensReceiptAndBackLeavesStockIntact() {
        val before = household.values.value
        launch()
        compose.onNodeWithContentDescription("Добавить по фото чека").performClick()
        await("Сфотографируйте чек")
        text("Сделать фото").performScrollTo().performClick()
        val captureDirectory = File(compose.activity.cacheDir, "receipt-photos")
        assertEquals(1, captureDirectory.listFiles()?.size)
        text("Выбрать из галереи").assertIsNotEnabled()
        sendPhotoResult(Activity.RESULT_CANCELED, null)
        assertEquals(0, captureDirectory.listFiles()?.size)
        text("Выбрать из галереи").assertIsEnabled()
        back()
        await("Мои продукты")
        assertEquals(before, household.values.value)
    }

    @Test
    fun systemPickerCancellationAndConfirmedImportUseSharedPantry() {
        val before = household.values.value
        launch()
        compose.onNodeWithContentDescription("Добавить по фото чека").performClick()
        await("Сфотографируйте чек")
        text("Выбрать из галереи").performScrollTo().performClick()
        sendPhotoResult(Activity.RESULT_CANCELED, null)
        await("Сфотографируйте чек")
        assertEquals(before, household.values.value)

        val photo = File.createTempFile("receipt-test-", ".png", compose.activity.cacheDir)
        try {
            photo.outputStream().use { stream ->
                val bitmap = Bitmap.createBitmap(8, 8, Bitmap.Config.ARGB_8888)
                assertTrue(bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream))
                bitmap.recycle()
            }
            text("Выбрать из галереи").performScrollTo().performClick()
            sendPhotoResult(Activity.RESULT_OK, Intent().setData(Uri.fromFile(photo)))
            await("Нашли в чеке")
            assertEquals(before, household.values.value)
            text("Добавить выбранное (1)").performScrollTo().performClick()
            await("Продукты добавлены домой")
            text("Открыть продукты").performClick()
            await("Мои продукты")
            assertEquals(
                Quantity(200.0, QuantityUnit.GRAM),
                household.values.value.pantry.single { it.ingredientId == "hard-cheese" }.quantity,
            )
            tab("Блюда").performClick()
            await("Что приготовим?")
            val dishes = compose.onNodeWithTag("dishes-results")
            dishes.performScrollToNode(hasText("Сейчас"))
            text("Сейчас").performClick()
            await("Омлет с томатами")
            dishes.performScrollToNode(hasText("Паста с томатами и сыром"))
            text("Паста с томатами и сыром").performClick()
            await("Рецепт")
            compose.onNodeWithTag("recipe-ui-content")
                .performScrollToNode(hasText("Все продукты есть дома"))
            text("Все продукты есть дома").assertIsDisplayed()
        } finally {
            photo.delete()
        }
    }

    @Test
    fun profileEditorHidesBarsSavesAndOpensPantry() {
        launch()
        tab("Профиль").performClick()
        await("Демо-профиль")
        text("Питание и аллергены").performScrollTo().performClick()
        tab("Профиль").assertDoesNotExist()
        compose.onNodeWithContentDescription("Избранное").assertDoesNotExist()
        text("Веганство").performScrollTo().performClick()
        text("Сохранить предпочтения").performScrollTo().performClick()
        await("Предпочтения сохранены")
        tab("Профиль").assertIsDisplayed()
        assertEquals(FoodType.VEGAN, preferences.values.value.foodType)
        text("Мои продукты").performScrollTo().performClick()
        await("Мои продукты")
        tab("Продукты").assertIsSelected()
    }

    @Test
    fun favoritesAddsQuantityAndRecipeHasOneHeartAndReturns() {
        household.values.value = household.values.value.copy(
            favoriteIngredients = setOf("tomatoes"), favoriteRecipes = setOf("omelette"),
        )
        launch()
        compose.onNodeWithContentDescription("Избранное").performClick()
        await("Избранное")
        text("Ингредиенты").performClick()
        compose.onNodeWithContentDescription("Указать количество: Томаты").performClick()
        text("Количество, г").performTextInput("25")
        text("Добавить в продукты").performClick()
        await("Есть дома: 525 г")
        text("Блюда").performClick()
        val gate = CompletableDeferred<Unit>()
        favoriteGate = gate
        val cardHeart = compose.onNodeWithContentDescription("Убрать Омлет с томатами из избранного")
        cardHeart.performClick().assertIsNotEnabled()
        text("Омлет с томатами").performClick()
        await("Рецепт")
        compose.onNodeWithContentDescription("Убрать рецепт из избранного").assertIsDisplayed()
        back()
        await("Избранное")
        compose.runOnIdle { gate.complete(Unit) }
    }

    @Test
    fun hiddenDishesInheritSearchAndBackKeepsSearch() {
        preferences.values.value = FoodPreferences(excludedAllergens = setOf(Allergen.MILK))
        launch()
        tab("Блюда").performClick()
        await("Что приготовим?")
        text("Найти блюдо").performTextInput("омлет")
        val dishes = compose.onNodeWithTag("dishes-results")
        dishes.performScrollToNode(hasText("Сейчас"))
        text("Сейчас").performClick()
        await("Скрытые блюда (1)")
        dishes.performScrollToNode(hasText("Скрытые блюда (1)") and hasClickAction())
        compose.onNode(hasText("Скрытые блюда (1)") and hasClickAction()).performClick()
        await("Почему блюда скрыты")
        text("Омлет с сыром").assertDoesNotExist()
        text("Омлет с томатами").performScrollTo().performClick()
        await("Рецепт")
        back()
        await("Почему блюда скрыты")
        back()
        dishes.performScrollToIndex(0)
        compose.onNodeWithContentDescription("Найти блюдо").assertTextContains("омлет")
        dishes.performScrollToNode(hasText("Сейчас"))
        text("Сейчас").assertIsSelected()
    }

    @Test
    fun shoppingBudgetOpensRecipeRestoresResultAndAddsPlan() {
        shopping.values.value = shopping.values.value.copy(manualPurchases = emptyList())
        launch(withShopping = true)
        tab("Покупки").performClick()
        await("Что докупить")
        text("Подобрать покупки").performScrollTo().performClick()
        text("Бюджет, ₽").performTextReplacement("500,25")
        scrollBudget(hasText("Подобрать план")).performClick()
        await("В пределах бюджета")
        val recipeLink = hasTestTag("shopping-budget-recipe-cheese")
        scrollBudget(recipeLink).performClick()
        await("Рецепт")
        back()
        compose.waitUntil(10_000) { compose.onAllNodes(recipeLink).fetchSemanticsNodes().isNotEmpty() }
        compose.onNode(recipeLink).assertIsDisplayed()
        scrollBudget(hasText("Добавить план в покупки")).performClick()
        compose.waitUntil(10_000) { budget.submissions.isNotEmpty() }
        assertEquals("hard-cheese", budget.submissions.single().single().ingredientId)
        assertTrue(shopping.values.value.manualPurchases.any { it.ingredientId == "hard-cheese" })
    }

    @Test
    fun plannedRecipeOpensAndBackPreservesItsPurchaseEntry() {
        val plan = listOf(PlannedRecipe("cheese", 2))
        shopping.values.value = shopping.values.value.copy(plan = plan)
        launch(withShopping = true)
        tab("Покупки").performClick()
        await("Что докупить")
        val open = "Открыть рецепт: Паста с томатами и сыром"
        val shoppingList = compose.onNodeWithTag("shopping-ui-list")
        shoppingList.performScrollToNode(hasText(open))
        text(open).performClick()
        await("Рецепт")
        back()
        shoppingList.performScrollToNode(hasText(open))
        text(open).assertIsDisplayed()
        assertEquals(plan, shopping.values.value.plan)
    }

    @Test
    fun purchasedListOpensSharedPantryWithoutMovingStock() {
        launch(withShopping = true)
        tab("Покупки").performClick()
        await("Что докупить")
        compose.onNode(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Checkbox))
            .performClick()
        await("Покупка отмечена")
        compose.onNodeWithTag("shopping-ui-list").performScrollToNode(hasText("Мои продукты"))
        text("Мои продукты").performClick()
        await("Пока нет продуктов")
        tab("Продукты").assertIsSelected()
        assertEquals(setOf("hard-cheese"), shopping.values.value.checkedPurchases)
        assertEquals(0, shopping.checkoutCalls)
        assertTrue(shopping.values.value.pantry.isEmpty())
    }

    private fun launch(withShopping: Boolean = false) {
        val dependencies = object : AppDependencies {
            override val catalog = DemoCatalogRepository()
            override val household = if (withShopping) shopping else
                object : HouseholdRepository by this@ReceiptAppHostTest.household {
                    override suspend fun toggleFavorite(id: String, ingredient: Boolean) {
                        favoriteGate?.await()
                        this@ReceiptAppHostTest.household.toggleFavorite(id, ingredient)
                    }
                }
            override val preferences = this@ReceiptAppHostTest.preferences
            override val budgetPlanWriter = budget.takeIf { withShopping }
            override val receiptImporter = ReceiptImporter { quantities ->
                val (id, quantity) = quantities.entries.single()
                this@ReceiptAppHostTest.household.addPantry(id, quantity)
            }
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
        compose.setContent { AlmostReadyTheme { AppRoot(dependencies) } }
        await(if (withShopping) "Пока нет продуктов" else "Мои продукты")
    }

    private fun text(value: String) = compose.onNodeWithText(value)

    private fun await(value: String) {
        compose.waitUntil(10_000) { compose.onAllNodesWithText(value).fetchSemanticsNodes().isNotEmpty() }
    }

    private fun tab(value: String) = compose.onNode(
        hasText(value) and SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Tab),
    )

    private fun scrollBudget(matcher: SemanticsMatcher): SemanticsNodeInteraction {
        compose.onNodeWithTag("shopping-ui-budget").performScrollToNode(matcher)
        return compose.onNode(matcher)
    }

    private fun sendPhotoResult(code: Int, data: Intent?) = compose.runOnIdle {
        val activity = shadowOf(compose.activity)
        activity.receiveResult(activity.nextStartedActivityForResult.intent, code, data)
    }

    private fun back() = compose.runOnIdle { compose.activity.onBackPressedDispatcher.onBackPressed() }
}
