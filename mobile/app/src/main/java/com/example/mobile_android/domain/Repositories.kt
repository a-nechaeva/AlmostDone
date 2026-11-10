package com.example.mobile_android.domain

import kotlinx.coroutines.flow.Flow

interface CatalogRepository {
    val catalog: Flow<Catalog>
}

interface HouseholdRepository {
    val household: Flow<Household>

    suspend fun addPantry(id: String, quantity: Quantity?)

    suspend fun setPantry(id: String, quantity: Quantity?)

    suspend fun removePantry(id: String)

    suspend fun toggleFavorite(id: String, ingredient: Boolean)

    suspend fun planRecipe(id: String, servings: Int)

    suspend fun removePlannedRecipe(id: String)

    suspend fun addManualPurchase(id: String, quantity: Quantity)

    suspend fun removeManualPurchase(id: String)

    suspend fun toggleCheckedPurchase(id: String)

    suspend fun addCheckedPurchasesToPantry()
}

interface PreferencesRepository {
    val preferences: Flow<FoodPreferences>

    suspend fun update(transform: (FoodPreferences) -> FoodPreferences)
}

interface SessionRepository {
    val signedIn: Flow<Boolean>

    suspend fun signIn(login: String, password: String)

    suspend fun signInWithToken(token: String)

    suspend fun signOut()
}
