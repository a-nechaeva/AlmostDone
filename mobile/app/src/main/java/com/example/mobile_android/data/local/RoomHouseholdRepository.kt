package com.example.mobile_android.data.local

import androidx.room.withTransaction
import com.example.mobile_android.domain.*
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onStart

class RoomHouseholdRepository(
    private val database: HouseholdDatabase,
    private val catalogRepository: CatalogRepository,
    private val initialPantry: List<PantryItem>,
) : HouseholdRepository {
    private val dao = database.householdDao()
    override val household: Flow<Household> =
        database.invalidationTracker
            .createFlow(
                "pantry",
                "favorites",
                "recipe_plan",
                "manual_purchases",
                "checked_purchases",
            )
            .onStart { initialize() }
            .map { database.withTransaction { snapshot() } }

    private suspend fun initialize() =
        database.withTransaction {
            if (dao.metadata("seeded") == null) {
                initialPantry.forEach { save(it) }
                dao.saveMetadata(MetadataEntity("seeded", "1"))
            }
        }

    private suspend fun snapshot(): Household {
        val favorites = dao.favorites()
        return Household(
            pantry = dao.pantry().map { it.toDomain() },
            favoriteRecipes = favorites.filterNot { it.ingredient }.map { it.itemId }.toSet(),
            favoriteIngredients = favorites.filter { it.ingredient }.map { it.itemId }.toSet(),
            plan = dao.plan().map { PlannedRecipe(it.recipeId, it.servings) },
            manualPurchases = dao.manual().map { it.toDomain() },
            checkedPurchases = dao.checked().map { it.ingredientId }.toSet(),
        )
    }

    private suspend fun save(item: PantryItem) {
        if (item.quantity?.value == 0.0) dao.removePantry(item.ingredientId)
        else
            dao.savePantry(
                PantryEntity(item.ingredientId, item.quantity?.value, item.quantity?.unit?.name)
            )
    }

    private suspend fun add(id: String, added: Quantity?) {
        val previous = dao.pantry().find { it.ingredientId == id }
        if (previous == null) {
            save(PantryItem(id, added))
            return
        }
        val old = storedQuantity(previous.amount, previous.unit)
        require(old == null || added == null || old.unit == added.unit) {
            "Несовместимые единицы. Измените количество продукта вручную."
        }
        val result =
            if (old == null || added == null) null else Quantity(old.value + added.value, old.unit)
        save(PantryItem(id, result))
    }

    private suspend fun changeShopping(change: suspend (Catalog) -> Unit) {
        initialize()
        val catalog = catalogRepository.catalog.first()
        database.withTransaction {
            val before = shoppingQuote(catalog, snapshot())
            change(catalog)
            val after = shoppingQuote(catalog, snapshot())
            dao.checked().forEach { checked ->
                val oldLine = before.lines.find { it.ingredientId == checked.ingredientId }
                val newLine = after.lines.find { it.ingredientId == checked.ingredientId }
                if (newLine == null || oldLine?.buyQuantity != newLine.buyQuantity)
                    dao.removeChecked(checked.ingredientId)
            }
        }
    }

    private fun validateIngredient(catalog: Catalog, id: String, quantity: Quantity?) {
        val ingredient = requireNotNull(catalog.ingredient(id)) { "Продукт недоступен в каталоге." }
        require(quantity == null || quantity.unit == ingredient.unit) {
            "Несовместимые единицы. Уточните количество продукта."
        }
    }

    override suspend fun addPantry(id: String, quantity: Quantity?) = changeShopping { c ->
        validateIngredient(c, id, quantity)
        add(id, quantity)
    }

    override suspend fun setPantry(id: String, quantity: Quantity?) = changeShopping { c ->
        validateIngredient(c, id, quantity)
        save(PantryItem(id, quantity))
    }

    override suspend fun removePantry(id: String) = changeShopping { dao.removePantry(id) }

    override suspend fun toggleFavorite(id: String, ingredient: Boolean) {
        initialize()
        database.withTransaction {
            if (dao.favorites().any { it.itemId == id && it.ingredient == ingredient })
                dao.removeFavorite(id, ingredient)
            else dao.addFavorite(FavoriteEntity(id, ingredient))
        }
    }

    override suspend fun planRecipe(id: String, servings: Int) = changeShopping { catalog ->
        require(servings in 1..12)
        requireNotNull(catalog.recipe(id)) { "Рецепт недоступен." }
        dao.savePlan(PlanEntity(id, servings))
    }

    override suspend fun removePlannedRecipe(id: String) = changeShopping { dao.removePlan(id) }

    override suspend fun addManualPurchase(id: String, quantity: Quantity) = changeShopping { c ->
        validateIngredient(c, id, quantity)
        require(quantity.value > 0) { "Количество покупки должно быть больше нуля." }
        dao.saveManual(ManualPurchaseEntity(id, quantity.value, quantity.unit.name))
    }

    override suspend fun removeManualPurchase(id: String) = changeShopping { dao.removeManual(id) }

    override suspend fun toggleCheckedPurchase(id: String) =
        database.withTransaction {
            if (dao.checked().any { it.ingredientId == id }) dao.removeChecked(id)
            else dao.addChecked(CheckedPurchaseEntity(id))
        }

    override suspend fun addCheckedPurchasesToPantry() {
        initialize()
        val catalog = catalogRepository.catalog.first()
        database.withTransaction {
            val before = snapshot()
            val quote = shoppingQuote(catalog, before)
            val checked = quote.lines.filter { it.checked }
            require(checked.isNotEmpty()) { "Сначала отметьте купленные продукты." }
            require(checked.all { it.buyQuantity != null }) {
                "Для этих продуктов нужно уточнить количество и упаковку."
            }
            checked.forEach {
                add(it.ingredientId, it.buyQuantity)
                dao.removeManual(it.ingredientId)
            }
            if (checked.size == quote.lines.size) {
                dao.clearPlan()
                dao.clearManual()
            }
            dao.clearChecked()
        }
    }
}
