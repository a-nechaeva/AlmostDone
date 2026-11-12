package com.example.mobile_android.data.local

import androidx.room.withTransaction
import com.example.mobile_android.domain.*
import com.example.mobile_android.feature.receipt.ReceiptImporter
import com.example.mobile_android.feature.receipt.UnknownReceiptPantryQuantity
import com.example.mobile_android.feature.shopping.BudgetPlanAddition
import com.example.mobile_android.feature.shopping.BudgetPlanUndo
import com.example.mobile_android.feature.shopping.BudgetPurchaseReceipt
import com.example.mobile_android.feature.shopping.ShoppingBudgetPlanWriter
import com.example.mobile_android.feature.shopping.ShoppingPackageSelection
import java.util.UUID
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onStart
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

class RoomHouseholdRepository(
    private val database: HouseholdDatabase,
    private val catalogRepository: CatalogRepository,
    private val initialPantry: List<PantryItem>,
) : HouseholdRepository, ReceiptImporter, ShoppingBudgetPlanWriter {
    private val dao = database.householdDao()
    private val budgetWrites = Mutex()
    private val budgetReceipts = mutableMapOf<BudgetPurchaseReceipt, Map<String, PurchaseState>>()
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

    private suspend fun changeShopping(
        manualWrite: String? = null,
        change: suspend (Catalog) -> Unit,
    ) {
        shoppingTransaction(manualWrite = manualWrite) { catalog, _, _ -> change(catalog) }
    }

    private suspend fun <T> shoppingTransaction(
        revision: String = UUID.randomUUID().toString(),
        manualWrite: String? = null,
        change: suspend (Catalog, Household, ShoppingQuote) -> T,
    ): T {
        initialize()
        val catalog = catalogRepository.catalog.first()
        return database.withTransaction {
            val before = snapshot()
            val oldQuote = shoppingQuote(catalog, before)
            val result = change(catalog, before, oldQuote)
            val after = snapshot()
            val newQuote = shoppingQuote(catalog, after)
            val removedChecks = after.checkedPurchases.filter { id ->
                val oldLine = oldQuote.lines.find { it.ingredientId == id }
                val newLine = newQuote.lines.find { it.ingredientId == id }
                newLine == null || oldLine?.buyQuantity != newLine.buyQuantity
            }
            removedChecks.forEach { dao.removeChecked(it) }
            markPurchaseChanges(
                purchases(before, oldQuote),
                purchases(after.copy(checkedPurchases = after.checkedPurchases - removedChecks.toSet()), newQuote),
                revision,
                manualWrite,
            )
            result
        }
    }

    private data class PurchaseState(
        val manual: Quantity?,
        val line: ShoppingLine?,
        val checked: Boolean,
    )

    private fun purchases(household: Household, quote: ShoppingQuote): Map<String, PurchaseState> {
        val manual = household.manualPurchases.associate { it.ingredientId to it.quantity }
        val lines = quote.lines.associateBy { it.ingredientId }
        return (manual.keys + lines.keys + household.checkedPurchases).associateWith { id ->
            val checked = id in household.checkedPurchases
            PurchaseState(manual[id], lines[id]?.copy(checked = checked), checked)
        }
    }

    private fun revisionKey(id: String) = "shopping-revision:$id"

    private suspend fun markPurchaseChanges(
        before: Map<String, PurchaseState>,
        after: Map<String, PurchaseState>,
        revision: String = UUID.randomUUID().toString(),
        manualWrite: String? = null,
    ) {
        val changed = (before.keys + after.keys).filterTo(mutableSetOf()) { before[it] != after[it] }
        // An explicit write supersedes an undo receipt even when the amount is identical.
        if (manualWrite != null) changed.add(manualWrite)
        changed.forEach { id ->
            dao.saveMetadata(MetadataEntity(revisionKey(id), revision))
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

    override suspend fun add(quantities: Map<String, Quantity?>) {
        shoppingTransaction { catalog, before, _ ->
            require(quantities.isNotEmpty())
            // К неизвестному остатку нельзя прибавить число, но добавить «без веса» можно.
            val unknown = before.pantry.firstOrNull { it.quantity == null && quantities[it.ingredientId] != null }
            if (unknown != null) throw UnknownReceiptPantryQuantity(unknown.ingredientId)
            quantities.forEach { (id, quantity) ->
                validateIngredient(catalog, id, quantity)
                require(quantity == null || quantity.value > 0)
            }
            quantities.forEach { (id, quantity) -> add(id, quantity) }
        }
    }

    override suspend fun add(packages: List<ShoppingPackageSelection>): BudgetPlanAddition =
        budgetWrites.withLock {
            require(packages.isNotEmpty())
            val receipt = BudgetPurchaseReceipt(UUID.randomUUID().toString())
            val (originals, alreadyCovered) = shoppingTransaction(receipt.id) { catalog, before, quote ->
                val desired = packages.groupBy { it.ingredientId }.mapValues { (id, items) ->
                    val offer = requireNotNull(catalog.ingredient(id)?.offer)
                    // One offer per ingredient: "<id>-default" (как на сервере); старые ID упаковок
                    // демо-примера тоже принимаются.
                    val packageIds = setOfNotNull(defaultPackageId(id), LEGACY_DEMO_PACKAGES[id])
                    require(items.all { item ->
                        item.packageId in packageIds && item.packageQuantity == offer.quantity &&
                            item.packageCount > 0
                    })
                    Quantity(items.sumOf { it.packageCount * offer.quantity.value }, offer.quantity.unit)
                }
                val original = purchases(before, quote)
                val changed = desired.filter { (id, quantity) ->
                    val covered = original[id]?.line?.buyQuantity
                    covered == null || covered.unit != quantity.unit || covered.value < quantity.value
                }
                changed.forEach { (id, quantity) ->
                    dao.saveManual(ManualPurchaseEntity(id, quantity.value, quantity.unit.name))
                }
                val updated = shoppingQuote(catalog, snapshot()).lines.associateBy { it.ingredientId }
                desired.forEach { (id, quantity) ->
                    val available = updated[id]?.buyQuantity
                    require(available != null && available.unit == quantity.unit && available.value >= quantity.value)
                }
                changed.keys.associateWith { original[it] ?: PurchaseState(null, null, false) } to
                    (desired.size - changed.size)
            }
            if (originals.isEmpty()) return@withLock BudgetPlanAddition.AlreadyInList
            budgetReceipts.entries.removeAll { (_, lines) -> lines.keys.any { it in originals } }
            budgetReceipts[receipt] = originals
            BudgetPlanAddition.Added(receipt, alreadyCovered)
        }

    override suspend fun undo(receipt: BudgetPurchaseReceipt): BudgetPlanUndo = budgetWrites.withLock {
        val originals = budgetReceipts[receipt] ?: return@withLock BudgetPlanUndo.PurchasesChanged
        val catalog = catalogRepository.catalog.first()
        val result = database.withTransaction {
            if (originals.keys.any { dao.metadata(revisionKey(it)) != receipt.id })
                return@withTransaction BudgetPlanUndo.PurchasesChanged
            val before = snapshot()
            originals.forEach { (id, original) ->
                val manual = original.manual
                if (manual == null) dao.removeManual(id)
                else dao.saveManual(ManualPurchaseEntity(id, manual.value, manual.unit.name))
                if (original.checked) dao.addChecked(CheckedPurchaseEntity(id))
                else dao.removeChecked(id)
            }
            val after = snapshot()
            markPurchaseChanges(purchases(before, shoppingQuote(catalog, before)), purchases(after, shoppingQuote(catalog, after)))
            BudgetPlanUndo.Restored
        }
        budgetReceipts.remove(receipt)
        result
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

    override suspend fun addManualPurchase(id: String, quantity: Quantity) = changeShopping(manualWrite = id) { c ->
        validateIngredient(c, id, quantity)
        require(quantity.value > 0) { "Количество покупки должно быть больше нуля." }
        dao.saveManual(ManualPurchaseEntity(id, quantity.value, quantity.unit.name))
    }

    override suspend fun removeManualPurchase(id: String) = changeShopping { dao.removeManual(id) }

    override suspend fun toggleCheckedPurchase(id: String) =
        database.withTransaction {
            if (dao.checked().any { it.ingredientId == id }) dao.removeChecked(id)
            else dao.addChecked(CheckedPurchaseEntity(id))
            dao.saveMetadata(MetadataEntity(revisionKey(id), UUID.randomUUID().toString()))
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
            val after = snapshot()
            markPurchaseChanges(purchases(before, quote), purchases(after, shoppingQuote(catalog, after)))
        }
    }

    /**
     * Полностью заменить локальное зеркало запасов серверным состоянием. Вызывается
     * [com.example.mobile_android.data.remote.ServerHouseholdRepository] после успешного
     * чтения или записи на сервере.
     */
    suspend fun mirrorPantry(items: List<PantryItem>) {
        initialize()
        database.withTransaction {
            dao.clearPantry()
            items.forEach { save(it) }
        }
    }

    /** Полностью заменить локальное зеркало избранного серверным состоянием. */
    suspend fun mirrorFavorites(recipes: Set<String>, ingredients: Set<String>) {
        initialize()
        database.withTransaction {
            dao.clearFavorites()
            recipes.forEach { dao.addFavorite(FavoriteEntity(it, ingredient = false)) }
            ingredients.forEach { dao.addFavorite(FavoriteEntity(it, ingredient = true)) }
        }
    }

    /** Точечно применить результат серверного PUT/DELETE избранного к зеркалу. */
    suspend fun mirrorFavorite(id: String, ingredient: Boolean, favorite: Boolean) {
        initialize()
        database.withTransaction {
            if (favorite) dao.addFavorite(FavoriteEntity(id, ingredient))
            else dao.removeFavorite(id, ingredient)
        }
    }

    /**
     * Локальная часть переноса купленного в запасы, когда запасы уже обновил сервер
     * (`pantry_add_purchased`): снять отметки и очистить обработанные строки списка.
     */
    suspend fun completeCheckedPurchases(checkedIds: Set<String>) {
        initialize()
        val catalog = catalogRepository.catalog.first()
        database.withTransaction {
            val before = snapshot()
            val quote = shoppingQuote(catalog, before)
            val checked = quote.lines.filter { it.checked && it.ingredientId in checkedIds }
            checked.forEach { dao.removeManual(it.ingredientId) }
            if (checked.size == quote.lines.size) {
                dao.clearPlan()
                dao.clearManual()
            }
            dao.clearChecked()
            val after = snapshot()
            markPurchaseChanges(purchases(before, quote), purchases(after, shoppingQuote(catalog, after)))
        }
    }
}

private val LEGACY_DEMO_PACKAGES = mapOf("hard-cheese" to "hard-cheese-200g", "tomatoes" to "tomatoes-500g")
