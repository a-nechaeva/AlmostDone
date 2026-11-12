package com.example.mobile_android.data.remote

import com.example.mobile_android.data.DemoCatalog
import com.example.mobile_android.domain.Allergen
import com.example.mobile_android.domain.CookingMethod
import com.example.mobile_android.domain.Nutrition
import com.example.mobile_android.domain.Quantity
import com.example.mobile_android.domain.QuantityUnit
import java.io.IOException
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], application = android.app.Application::class)
class ServerCatalogRepositoryTest {
    private val body =
        """
        {"catalog_version":"v1",
         "ingredients":[
           {"id":"milk","name":"Молоко","unit":"ml","allergens":["milk"],"allergen_data_complete":true,
            "nutrition_per_100g":{"kcal":60.4,"protein_g":3.2,"fat_g":2.5,"carbs_g":4.7},
            "offer":{"quantity":{"value":1000,"unit":"ml"},"price":{"minor_units":11050,"currency":"RUB"}}},
           {"id":"oats","name":"Овсянка","unit":"g","allergens":["gluten"],"allergen_data_complete":true,
            "nutrition_per_100g":null,"offer":null},
           {"id":"egg","name":"Яйцо","unit":"pcs","allergens":["eggs"],"allergen_data_complete":false,
            "nutrition_per_100g":{"kcal":-5,"protein_g":12.7,"fat_g":11.5,"carbs_g":0.7},"offer":null}],
         "recipes":[
           {"id":"1","title":"Каша","photo_url":"http://127.0.0.1:8000/api/v1/recipes/1/photo","servings":24,
            "minutes":10,"steps":["Сварить"],
            "ingredients":[{"ingredient_id":"milk","quantity":{"value":2000,"unit":"ml"}},
                           {"ingredient_id":"oats","quantity":{"value":400,"unit":"g"}}],
            "nutrition_per_serving":{"kcal":210.4,"protein_g":7.6,"fat_g":5.2,"carbs_g":30.1},
            "allergens":["gluten","milk"],"allergen_data_complete":true,"methods":["stove"]},
           {"id":"2","title":"Неизвестная единица","photo_url":null,"servings":2,"minutes":5,"steps":[],
            "ingredients":[{"ingredient_id":"oats","quantity":{"value":2,"unit":"pcs"}}],
            "nutrition_per_serving":{"kcal":1,"protein_g":0,"fat_g":0,"carbs_g":0},
            "allergens":[],"allergen_data_complete":true,"methods":[]},
           {"id":"3","title":"Яичница","photo_url":null,"servings":1,"minutes":5,"steps":[],
            "ingredients":[{"ingredient_id":"egg","quantity":{"value":2,"unit":"pcs"}}],
            "nutrition_per_serving":{"kcal":150,"protein_g":12,"fat_g":10,"carbs_g":1},
            "allergens":["eggs","mustard"],"allergen_data_complete":true,"methods":["no_cook"]}]}
        """.trimIndent()

    @Test
    fun parsesCatalogInIngredientUnits() {
        val catalog = parseServerCatalog(JSONObject(body))
        val milk = catalog.ingredient("milk")!!
        assertEquals(QuantityUnit.MILLILITER, milk.unit)
        assertEquals(11050L, milk.offer!!.priceKopecks)
        assertNull(catalog.ingredient("oats")!!.offer)

        // КБЖУ на 100 г: значения с сервера округляются до граммов/ккал
        assertEquals(Nutrition(60, 3, 3, 5), milk.nutritionPer100g)
        // null у сервера — данных нет, подменять нулём нельзя
        assertNull(catalog.ingredient("oats")!!.nutritionPer100g)
        // битые значения (отрицательные) считаем отсутствием данных, а не роняем каталог
        assertNull(catalog.ingredient("egg")!!.nutritionPer100g)

        val porridge = catalog.recipe("1")!!
        // 24 порции → 12, количества пропорционально
        assertEquals(12, porridge.servings)
        assertEquals(Quantity(1000.0, QuantityUnit.MILLILITER), porridge.ingredients.first().quantity)
        assertEquals("http://127.0.0.1:8000/api/v1/recipes/1/photo", porridge.photo)
        assertEquals(setOf(Allergen.GLUTEN, Allergen.MILK), porridge.allergens)
        assertTrue(porridge.allergenDataComplete)
        assertEquals(false, porridge.dietaryFacts.glutenFree)
        assertEquals(setOf(CookingMethod.STOVE), porridge.methods)
        assertEquals(210, porridge.nutritionPerServing!!.kcal)

        // единица не совпадает с ингредиентом — рецепт пропущен, а не весь каталог
        assertNull(catalog.recipe("2"))

        // аллерген, которого нет в приложении, — данные неполные
        val eggs = catalog.recipe("3")!!
        assertFalse(eggs.allergenDataComplete)
        assertNull(eggs.dietaryFacts.glutenFree)
        assertEquals("", eggs.photo)
        assertEquals(setOf(CookingMethod.NO_COOK), eggs.methods)
    }

    @Test
    fun loadsCatalogOnceAndFallsBackToDemo() = runTest {
        var calls = 0
        val scope = TestScope(StandardTestDispatcher(testScheduler))
        val ok = ServerCatalogRepository(api { calls++; ApiResponse(200, JSONObject(body), null, null) }, DemoCatalog.catalog, scope)
        scope.advanceUntilIdle()
        assertEquals(setOf("1", "3"), ok.catalog.first().recipes.map { it.id }.toSet())
        assertEquals(setOf("1", "3"), ok.catalog.first().recipes.map { it.id }.toSet())
        assertEquals(1, calls)

        val offline = ServerCatalogRepository(api { throw IOException("offline") }, DemoCatalog.catalog, scope)
        scope.advanceUntilIdle()
        assertSame(DemoCatalog.catalog, offline.catalog.first())
    }

    private fun api(reply: (ApiRequest) -> ApiResponse) =
        object : AuthenticatedApi {
            override suspend fun execute(request: ApiRequest): ApiResponse {
                assertEquals("catalog", request.path)
                return reply(request)
            }
        }
}
