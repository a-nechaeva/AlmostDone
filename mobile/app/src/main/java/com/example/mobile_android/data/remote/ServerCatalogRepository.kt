package com.example.mobile_android.data.remote

import android.util.Log
import com.example.mobile_android.domain.Catalog
import com.example.mobile_android.domain.CatalogRepository
import com.example.mobile_android.domain.CookingMethod
import com.example.mobile_android.domain.DietaryFacts
import com.example.mobile_android.domain.Ingredient
import com.example.mobile_android.domain.Nutrition
import com.example.mobile_android.domain.PackageOffer
import com.example.mobile_android.domain.Quantity
import com.example.mobile_android.domain.Recipe
import com.example.mobile_android.domain.RecipeIngredient
import kotlin.math.roundToInt
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

/**
 * Каталог сервера (`GET /catalog`): рецепты подбираются на устройстве локальным движком.
 *
 * Загружается один раз на сессию. Если сервер недоступен или ответ не разобрался, экраны
 * получают [fallback] (встроенный демо-каталог), чтобы приложение оставалось рабочим.
 */
class ServerCatalogRepository(
    private val api: AuthenticatedApi,
    private val fallback: Catalog,
    scope: CoroutineScope,
) : CatalogRepository {
    private val loaded = MutableStateFlow<Catalog?>(null)

    override val catalog: Flow<Catalog> = loaded.filterNotNull()

    init {
        scope.launch {
            loaded.value =
                try {
                    val json = api.execute(ApiRequest("catalog")).json ?: throw ApiProtocolException()
                    withContext(Dispatchers.Default) { parseServerCatalog(json) }
                } catch (cancelled: CancellationException) {
                    throw cancelled
                } catch (error: Exception) {
                    Log.w("ServerCatalog", "Каталог сервера недоступен, используется демо-каталог", error)
                    fallback
                }
        }
    }
}

/** Рецепт на устройстве — не больше 12 порций (ограничение модели); количества пересчитываются. */
private const val MAX_SERVINGS = 12

internal fun parseServerCatalog(json: JSONObject): Catalog {
    val ingredients =
        json.getJSONArray("ingredients").objects().mapNotNull { item ->
            val unit = quantityUnitFromApiId(item.getString("unit")) ?: return@mapNotNull null
            val offer =
                item.optJSONObject("offer")?.let { offer ->
                    val quantity = parseQuantity(offer.getJSONObject("quantity"))
                    val price = offer.getJSONObject("price").getLong("minor_units")
                    if (quantity == null || quantity.unit != unit || quantity.value <= 0) null
                    else PackageOffer(quantity, price)
                }
            Ingredient(
                item.getString("id"),
                item.getString("name"),
                unit,
                offer,
                nutritionPer100g = parseIngredientNutrition(item.optJSONObject("nutrition_per_100g")),
            )
        }
    val known = ingredients.associateBy { it.id }
    val recipes =
        json.getJSONArray("recipes").objects().mapNotNull { item ->
            // Рецепт с непонятными для приложения данными пропускаем, а не роняем весь каталог.
            runCatching { parseRecipe(item, known) }.getOrNull()
        }
    return Catalog(ingredients, recipes)
}

private fun parseRecipe(item: JSONObject, known: Map<String, Ingredient>): Recipe? {
    val servings = item.getInt("servings")
    val shown = servings.coerceIn(1, MAX_SERVINGS)
    val factor = shown.toDouble() / servings
    val ingredients =
        item.getJSONArray("ingredients").objects().map { line ->
            val id = line.getString("ingredient_id")
            val quantity = parseQuantity(line.getJSONObject("quantity")) ?: return null
            if (known[id]?.unit != quantity.unit) return null
            RecipeIngredient(id, Quantity(quantity.value * factor, quantity.unit))
        }
    if (ingredients.isEmpty()) return null
    val codes = item.getJSONArray("allergens").strings()
    val allergens = codes.mapNotNull(::allergenFromApiId).toSet()
    val complete = item.getBoolean("allergen_data_complete") && allergens.size == codes.size
    val nutrition = item.getJSONObject("nutrition_per_serving")
    return Recipe(
        id = item.getString("id"),
        title = item.getString("title"),
        ingredients = ingredients,
        steps = item.getJSONArray("steps").strings(),
        minutes = item.getInt("minutes"),
        servings = shown,
        nutritionPerServing =
            Nutrition(
                nutrition.getDouble("kcal").roundToInt(),
                nutrition.getDouble("protein_g").roundToInt(),
                nutrition.getDouble("fat_g").roundToInt(),
                nutrition.getDouble("carbs_g").roundToInt(),
            ),
        allergens = allergens,
        allergenDataComplete = complete,
        // Без полных данных об аллергенах «без глютена/лактозы» не обещаем.
        dietaryFacts =
            DietaryFacts(
                vegetarian = null,
                vegan = null,
                glutenFree = if (complete) "gluten" !in codes else null,
                lactoseFree = if (complete) "milk" !in codes else null,
            ),
        methods =
            item.getJSONArray("methods").strings().mapNotNull { method ->
                CookingMethod.entries.find { it.name.equals(method, ignoreCase = true) }
            }.toSet(),
        photo = if (item.isNull("photo_url")) "" else item.getString("photo_url"),
    )
}

/**
 * КБЖУ ингредиента на 100 г (`nutrition_per_100g`). Сервер отдаёт null при неполных данных;
 * битые или отрицательные значения тоже считаем отсутствием данных, а не ошибкой каталога.
 */
private fun parseIngredientNutrition(json: JSONObject?): Nutrition? {
    json ?: return null
    val values =
        listOf("kcal", "protein_g", "fat_g", "carbs_g").map { key ->
            val value = json.optDouble(key, Double.NaN)
            if (!value.isFinite() || value < 0) return null
            value
        }
    return Nutrition(
        values[0].roundToInt(),
        values[1].roundToInt(),
        values[2].roundToInt(),
        values[3].roundToInt(),
    )
}

private fun JSONArray.objects(): List<JSONObject> = List(length()) { getJSONObject(it) }

private fun JSONArray.strings(): List<String> = List(length()) { getString(it) }
