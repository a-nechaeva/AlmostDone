package com.example.mobile_android.feature.favorites.localwiring

import com.example.mobile_android.data.DemoCatalog
import com.example.mobile_android.domain.Catalog
import com.example.mobile_android.domain.CatalogRepository
import com.example.mobile_android.domain.Household
import com.example.mobile_android.domain.HouseholdRepository
import com.example.mobile_android.domain.PantryItem
import com.example.mobile_android.domain.Quantity
import com.example.mobile_android.feature.favorites.FavoritesHouseholdFake
import com.example.mobile_android.feature.favorites.FavoritesIngredientSelection
import com.example.mobile_android.feature.favorites.FavoritesPreferencesFake
import java.io.IOException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.update

internal class FavoritesLocalWiringFixture(
    data: Catalog = DemoCatalog.catalog,
    initial: Household = Household(
        pantry = DemoCatalog.initialPantry,
        favoriteRecipes = setOf("omelette"),
        favoriteIngredients = setOf("eggs", "tomatoes"),
    ),
) {
    var catalogGate: CompletableDeferred<Unit>? = null
    val catalog = object : CatalogRepository {
        override val catalog = flow {
            catalogGate?.await()
            emit(data)
        }
    }
    val household = LocalWiringHouseholdFake(FavoritesHouseholdFake(initial))
    val preferences = FavoritesPreferencesFake()
}

internal class LocalWiringHouseholdFake(
    private val shared: FavoritesHouseholdFake,
) : HouseholdRepository by shared {
    val values get() = shared.values
    val pantryAdds = mutableListOf<FavoritesIngredientSelection>()
    var pantryGate: CompletableDeferred<Unit>? = null
    var failAdd = false

    override suspend fun addPantry(id: String, quantity: Quantity?) {
        pantryAdds += FavoritesIngredientSelection(id, quantity)
        pantryGate?.await()
        if (failAdd) throw IOException("pantry write")
        values.update { current ->
            val existing = current.pantry.find { it.ingredientId == id }
            val old = existing?.quantity
            val total = when {
                existing == null -> quantity
                old == null || quantity == null -> null
                else -> {
                    require(old.unit == quantity.unit)
                    Quantity(old.value + quantity.value, old.unit)
                }
            }
            val others = current.pantry.filterNot { it.ingredientId == id }
            current.copy(pantry = if (total?.value == 0.0) others else others + PantryItem(id, total))
        }
    }
}
