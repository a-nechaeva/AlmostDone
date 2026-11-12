package com.example.mobile_android.data.remote

import com.example.mobile_android.data.local.RoomHouseholdRepository
import com.example.mobile_android.domain.CatalogRepository
import com.example.mobile_android.domain.Household
import com.example.mobile_android.domain.HouseholdRepository
import com.example.mobile_android.domain.PantryItem
import com.example.mobile_android.domain.Quantity
import com.example.mobile_android.domain.shoppingQuote
import com.example.mobile_android.feature.receipt.ReceiptImporter
import com.example.mobile_android.feature.receipt.ServerReceiptImporter
import com.example.mobile_android.feature.receipt.ReceiptImportLine
import java.net.URLEncoder
import java.util.UUID
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.onStart
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONArray
import org.json.JSONObject

/**
 * Серверные продукты дома и избранное (OpenAPI `pantry_*`, `favorites_*`) поверх локального
 * зеркала Room.
 *
 * Сервер — источник истины: каждая запись сначала уходит на сервер с `If-Match` по последней
 * известной версии состояния (а для retryable-операций — с `Idempotency-Key`), затем ответ
 * зеркалируется в Room, откуда экраны реактивно читают [Household]. На `412/428` версия
 * перечитывается через `GET /me/state` и операция повторяется один раз. Ошибка сети или
 * сервера пробрасывается вызывающему: локальное состояние не меняется, ложного успеха нет.
 *
 * При первом чтении запасы и избранное подтягиваются с сервера (восстановление после
 * переустановки/смены устройства); если сервер недоступен, экраны работают с локальным
 * зеркалом, а синхронизация повторится при следующем обращении.
 *
 * Локальными остаются план блюд, ручные покупки и отметки «куплено» — серверных операций
 * для них нет, список покупок живёт на устройстве.
 */
class ServerHouseholdRepository(
    private val local: RoomHouseholdRepository,
    private val catalog: CatalogRepository,
    private val api: AuthenticatedApi,
) : HouseholdRepository, ReceiptImporter, ServerReceiptImporter {
    private val lock = Mutex()
    private var etag: String? = null
    private var synced = false

    override val household: Flow<Household> = local.household.onStart { syncFromServer() }

    // --- Начальная синхронизация -------------------------------------------------

    private suspend fun syncFromServer() {
        lock.withLock {
            if (synced) return
            try {
                val pantry = api.execute(ApiRequest("me/pantry?limit=1000"))
                etag = pantry.etag ?: etag
                local.mirrorPantry(parsePantryItems(pantry.json ?: throw ApiProtocolException()))
                local.mirrorFavorites(
                    recipes = favoriteIds("me/favorites/recipes"),
                    ingredients = favoriteIds("me/favorites/ingredients"),
                )
                synced = true
            } catch (cancelled: kotlinx.coroutines.CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                // Офлайн-старт: работаем с локальным зеркалом, синхронизация повторится позже.
            }
        }
    }

    private suspend fun favoriteIds(path: String): Set<String> {
        val ids = mutableSetOf<String>()
        var cursor: String? = null
        do {
            val query = buildString {
                append("?limit=100")
                cursor?.let { append("&cursor=" + URLEncoder.encode(it, "UTF-8")) }
            }
            val json = api.execute(ApiRequest(path + query)).json ?: throw ApiProtocolException()
            val items = json.getJSONArray("items")
            for (i in 0 until items.length()) ids += items.getJSONObject(i).getString("id")
            val page = json.getJSONObject("page")
            cursor =
                if (page.getBoolean("has_more") && !page.isNull("next_cursor"))
                    page.getString("next_cursor")
                else null
        } while (cursor != null)
        return ids
    }

    // --- Версия состояния и повтор после конфликта --------------------------------

    private suspend fun currentEtag(): String =
        etag ?: loadVersion().also { etag = it }

    private suspend fun loadVersion(): String {
        val response = api.execute(ApiRequest("me/state"))
        return response.etag
            ?: response.json?.let { "\"state-${it.getInt("state_version")}\"" }
            ?: throw ApiProtocolException()
    }

    /** Одна мутация с `If-Match`; при конфликте версии — одно перечитывание и один повтор. */
    private suspend fun mutate(request: (etag: String) -> ApiRequest): Pair<JSONObject?, String?> =
        lock.withLock {
            val send = suspend {
                val version = currentEtag()
                api.execute(request(version))
            }
            val response =
                try {
                    send()
                } catch (conflict: ApiHttpException) {
                    if (conflict.status != 412 && conflict.status != 428) throw conflict
                    etag = loadVersion()
                    send()
                }
            etag = response.etag ?: etag
            response.json to response.etag
        }

    private suspend fun mutatePantry(request: (etag: String) -> ApiRequest) {
        val (json, _) = mutate(request)
        local.mirrorPantry(parsePantryItems(json ?: throw ApiProtocolException()))
    }

    // --- Продукты дома (#57) -------------------------------------------------------

    override suspend fun addPantry(id: String, quantity: Quantity?) {
        require(quantity == null || quantity.value > 0) { "Добавление требует положительное количество." }
        mutatePantry { version ->
            ApiRequest(
                "me/pantry/add",
                ApiMethod.POST,
                JSONObject()
                    .put("ingredient_id", id)
                    .put("quantity", quantity?.let(::quantityJson) ?: JSONObject.NULL),
                ifMatch = version,
                idempotencyKey = UUID.randomUUID().toString(),
            )
        }
    }

    override suspend fun setPantry(id: String, quantity: Quantity?) {
        mutatePantry { version ->
            ApiRequest(
                "me/pantry/" + URLEncoder.encode(id, "UTF-8"),
                ApiMethod.PUT,
                JSONObject().put("quantity", quantity?.let(::quantityJson) ?: JSONObject.NULL),
                ifMatch = version,
            )
        }
    }

    override suspend fun removePantry(id: String) {
        mutatePantry { version ->
            ApiRequest("me/pantry/" + URLEncoder.encode(id, "UTF-8"), ApiMethod.DELETE, ifMatch = version)
        }
    }

    /** Импорт чека без серверного распознавания (демо-строки): складываем через pantry_add. */
    override suspend fun add(quantities: Map<String, Quantity>) {
        require(quantities.isNotEmpty())
        quantities.forEach { (id, quantity) ->
            require(quantity.value > 0)
            addPantry(id, quantity)
        }
    }

    /** Перенос отмеченных покупок в запасы через `POST /me/pantry/purchased`. */
    override suspend fun addCheckedPurchasesToPantry() {
        val current = local.household.first()
        val quote = shoppingQuote(catalog.catalog.first(), current)
        val checked = quote.lines.filter { it.checked }
        require(checked.isNotEmpty()) { "Сначала отметьте купленные продукты." }
        require(checked.all { it.buyQuantity != null }) {
            "Для этих продуктов нужно уточнить количество и упаковку."
        }
        val merged = LinkedHashMap<String, Quantity>()
        for (line in checked) {
            val quantity = requireNotNull(line.buyQuantity)
            val previous = merged[line.ingredientId]
            require(previous == null || previous.unit == quantity.unit) {
                "Несовместимые единицы. Измените количество продукта вручную."
            }
            merged[line.ingredientId] =
                previous?.let { Quantity(it.value + quantity.value, it.unit) } ?: quantity
        }
        val items = JSONArray()
        merged.forEach { (id, quantity) ->
            items.put(JSONObject().put("ingredient_id", id).put("quantity", quantityJson(quantity)))
        }
        mutatePantry { version ->
            ApiRequest(
                "me/pantry/purchased",
                ApiMethod.POST,
                JSONObject().put("items", items),
                ifMatch = version,
                idempotencyKey = UUID.randomUUID().toString(),
            )
        }
        local.completeCheckedPurchases(checked.map { it.ingredientId }.toSet())
    }

    // --- Избранное (#68) ------------------------------------------------------------

    override suspend fun toggleFavorite(id: String, ingredient: Boolean) {
        val current = local.household.first()
        val isFavorite =
            if (ingredient) id in current.favoriteIngredients else id in current.favoriteRecipes
        val path =
            (if (ingredient) "me/favorites/ingredients/" else "me/favorites/recipes/") +
                URLEncoder.encode(id, "UTF-8")
        val method = if (isFavorite) ApiMethod.DELETE else ApiMethod.PUT
        mutate { version -> ApiRequest(path, method, ifMatch = version) }
        local.mirrorFavorite(id, ingredient, favorite = !isFavorite)
    }

    // --- Подтверждение распознанного чека (#71) --------------------------------------

    override suspend fun importReceipt(
        recognitionId: String,
        kind: String,
        lines: List<ReceiptImportLine>,
    ) {
        require(lines.isNotEmpty())
        val items = JSONArray()
        for (line in lines) {
            items.put(
                JSONObject()
                    .put("line_id", line.lineId)
                    .put("ingredient_id", line.ingredientId)
                    .put("quantity", line.quantity?.let(::quantityJson) ?: JSONObject.NULL)
            )
        }
        val (json, _) =
            mutate { version ->
                ApiRequest(
                    "recognition-imports",
                    ApiMethod.POST,
                    JSONObject()
                        .put("recognition_id", recognitionId)
                        .put("kind", kind)
                        .put("items", items),
                    ifMatch = version,
                    idempotencyKey = UUID.randomUUID().toString(),
                )
            }
        val body = json ?: throw ApiProtocolException()
        local.mirrorPantry(parsePantryItems(body.getJSONArray("pantry")))
    }

    // --- Локальный список покупок (серверных операций нет) ---------------------------

    override suspend fun planRecipe(id: String, servings: Int) = local.planRecipe(id, servings)

    override suspend fun removePlannedRecipe(id: String) = local.removePlannedRecipe(id)

    override suspend fun addManualPurchase(id: String, quantity: Quantity) =
        local.addManualPurchase(id, quantity)

    override suspend fun removeManualPurchase(id: String) = local.removeManualPurchase(id)

    override suspend fun toggleCheckedPurchase(id: String) = local.toggleCheckedPurchase(id)

    private companion object {
        fun parsePantryItems(json: JSONObject): List<PantryItem> = parsePantryItems(json.getJSONArray("items"))

        fun parsePantryItems(items: JSONArray): List<PantryItem> =
            List(items.length()) { index ->
                val item = items.getJSONObject(index)
                PantryItem(
                    ingredientId = item.getString("ingredient_id"),
                    quantity =
                        if (item.isNull("quantity")) null
                        else parseQuantity(item.getJSONObject("quantity")),
                )
            }
    }
}
