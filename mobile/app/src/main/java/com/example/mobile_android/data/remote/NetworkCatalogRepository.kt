package com.example.mobile_android.data.remote

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import com.example.mobile_android.domain.*
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

/**
 * Каталог с сервера (GET /api/v1/catalog/android) вместо встроенного демо.
 *
 * Если сервер недоступен, отдаётся [fallback] (DemoCatalog), а в [status] — причина. Адрес
 * сервера хранится в DataStore и меняется на экране «Фото чека» без пересборки приложения.
 */
class NetworkCatalogRepository(
    private val scope: CoroutineScope,
    private val store: DataStore<Preferences>,
    private val fallback: Catalog,
) : CatalogRepository, ServerConnection {
    private val urlKey = stringPreferencesKey("server_url")
    private val current = MutableStateFlow<Catalog?>(null)
    private val _status = MutableStateFlow<ServerStatus>(ServerStatus.Connecting(ApiClient.DEFAULT_URL))
    private var gramsPerPiece: Map<String, Double> = emptyMap()

    /** Вызывается после успешной загрузки каталога: (каталог, демо-кладовка с сервера). */
    var onConnected: (suspend (Catalog, List<String>) -> Unit)? = null

    override val catalog: Flow<Catalog> = current.filterNotNull()
    override val status: StateFlow<ServerStatus> = _status.asStateFlow()

    init {
        scope.launch {
            val saved = store.data.map { it[urlKey] }.first() ?: ApiClient.DEFAULT_URL
            connect(saved)
        }
    }

    override suspend fun connect(url: String) {
        val normalized = ApiClient.normalize(url)
        _status.value = ServerStatus.Connecting(normalized)
        try {
            val json = withContext(Dispatchers.IO) { ApiClient(normalized).getJson("catalog/android", 30_000) }
            val (catalog, pieces, demo) = withContext(Dispatchers.Default) { parse(json) }
            gramsPerPiece = pieces
            current.value = catalog
            store.edit { it[urlKey] = normalized }
            _status.value = ServerStatus.Connected(normalized, catalog.recipes.size, catalog.ingredients.size)
            onConnected?.invoke(catalog, demo)
        } catch (e: Exception) {
            if (current.value == null) current.value = fallback
            _status.value = ServerStatus.Offline(normalized, e.message ?: "Сервер недоступен")
        }
    }

    override suspend fun recognize(kind: RecognitionKind, jpeg: ByteArray): List<RecognizedLine> {
        val url = _status.value.url
        val json =
            withContext(Dispatchers.IO) {
                ApiClient(url).postMultipart("recognitions", mapOf("kind" to kind.api), "file", "photo.jpg", "image/jpeg", jpeg)
            }
        if (json.optString("status") == "failed") {
            val reason = json.optJSONObject("failure")?.optString("message").orEmpty()
            throw ApiException(reason.ifBlank { "Не удалось распознать фото" })
        }
        val catalog = current.value ?: fallback
        return json.getJSONArray("items").objects().map { line -> toLine(line, catalog) }
    }

    private fun toLine(line: JSONObject, catalog: Catalog): RecognizedLine {
        val candidate = line.getJSONArray("candidates").objects().firstOrNull()
        val id = candidate?.getString("ingredient_id")?.takeIf { catalog.ingredient(it) != null }
        val suggested = line.optJSONObject("suggested_quantity")
        return RecognizedLine(
            lineId = line.getString("line_id"),
            rawName = line.getString("raw_name"),
            ingredientId = id,
            name = id?.let { catalog.ingredient(it)?.name } ?: candidate?.optString("name"),
            confidence = candidate?.optDouble("confidence", 0.0) ?: 0.0,
            quantity = id?.let { grams(it, suggested, catalog) },
            status = line.getString("status"),
        )
    }

    /** Количество с фото → граммы приложения; не видно на фото — одна упаковка. */
    private fun grams(id: String, q: JSONObject?, catalog: Catalog): Quantity? {
        val pack = catalog.ingredient(id)?.offer?.quantity
        if (q == null) return pack
        val value = q.getDouble("value")
        val g =
            when (q.getString("unit")) {
                "pcs" -> gramsPerPiece[id]?.let { value * it }
                else -> value // g; ml считаем 1:1, как на сервере
            }
        return if (g != null && g > 0 && g <= 1_000_000) Quantity(g, QuantityUnit.GRAM) else pack
    }

    private fun parse(json: JSONObject): Triple<Catalog, Map<String, Double>, List<String>> {
        val pieces = mutableMapOf<String, Double>()
        val ingredients =
            json.getJSONArray("ingredients").objects().map { i ->
                val id = i.getString("id")
                if (!i.isNull("grams_per_piece")) pieces[id] = i.getDouble("grams_per_piece")
                val offer = i.optJSONObject("offer")
                Ingredient(
                    id = id,
                    name = i.getString("name"),
                    unit = QuantityUnit.valueOf(i.getString("unit")),
                    offer = offer?.let { PackageOffer(quantity(it.getJSONObject("quantity")), it.getLong("price_kopecks")) },
                )
            }
        val recipes =
            json.getJSONArray("recipes").objects().map { r ->
                val n = r.optJSONObject("nutrition")
                val d = r.getJSONObject("dietary")
                Recipe(
                    id = r.getString("id"),
                    title = r.getString("title"),
                    ingredients =
                        r.getJSONArray("ingredients").objects().map {
                            RecipeIngredient(it.getString("ingredient_id"), quantity(it.getJSONObject("quantity")))
                        },
                    steps = r.getJSONArray("steps").strings(),
                    minutes = r.getInt("minutes"),
                    servings = r.getInt("servings"),
                    nutritionPerServing =
                        n?.let { Nutrition(it.getInt("kcal"), it.getInt("protein"), it.getInt("fat"), it.getInt("carbs")) },
                    allergens = r.getJSONArray("allergens").strings().map { Allergen.valueOf(it) }.toSet(),
                    allergenDataComplete = r.getBoolean("allergen_data_complete"),
                    dietaryFacts =
                        DietaryFacts(d.optBool("vegetarian"), d.optBool("vegan"), d.optBool("gluten_free"), d.optBool("lactose_free")),
                    methods = r.getJSONArray("methods").strings().map { CookingMethod.valueOf(it) }.toSet(),
                    photo = r.optString("photo"),
                )
            }
        val demo = json.optJSONArray("demo_pantry")?.strings().orEmpty()
        return Triple(Catalog(ingredients, recipes), pieces, demo)
    }

    private fun quantity(q: JSONObject) = Quantity(q.getDouble("value"), QuantityUnit.valueOf(q.getString("unit")))
}

private fun JSONArray.objects(): List<JSONObject> = (0 until length()).map { getJSONObject(it) }

private fun JSONArray.strings(): List<String> = (0 until length()).map { getString(it) }

private fun JSONObject.optBool(name: String): Boolean? = if (isNull(name)) null else getBoolean(name)
