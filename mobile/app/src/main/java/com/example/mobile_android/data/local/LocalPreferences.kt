package com.example.mobile_android.data.local

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.*
import androidx.datastore.preferences.preferencesDataStore
import com.example.mobile_android.domain.*
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map

val Context.householdPreferences by preferencesDataStore(name = "household_preferences")

class LocalPreferences(private val store: DataStore<Preferences>) :
    PreferencesRepository, SessionRepository {
    private val foodType = stringPreferencesKey("food_type")
    private val allergens = stringSetPreferencesKey("excluded_allergens")
    private val gluten = booleanPreferencesKey("gluten_free")
    private val lactose = booleanPreferencesKey("lactose_free")
    private val diabetes = booleanPreferencesKey("diabetes")
    private val table = stringPreferencesKey("diet_table")
    private val session = booleanPreferencesKey("demo_signed_in")
    private val yandexToken = stringPreferencesKey("yandex_oauth_token")

    private fun decode(p: Preferences) =
        FoodPreferences(
            foodType = FoodType.valueOf(p[foodType] ?: FoodType.ANY.name),
            excludedAllergens = p[allergens].orEmpty().map { Allergen.valueOf(it) }.toSet(),
            glutenFree = p[gluten] ?: false,
            lactoseFree = p[lactose] ?: false,
            diabetes = p[diabetes] ?: false,
            dietTable = p[table].orEmpty(),
        )

    override val preferences: Flow<FoodPreferences> =
        store.data.map(::decode).distinctUntilChanged()
    override val signedIn = store.data.map { it[session] ?: false }.distinctUntilChanged()

    override suspend fun update(transform: (FoodPreferences) -> FoodPreferences) {
        store.edit { p ->
            val changed = transform(decode(p))
            p[foodType] = changed.foodType.name
            p[allergens] = changed.excludedAllergens.map { it.name }.toSet()
            p[gluten] = changed.glutenFree
            p[lactose] = changed.lactoseFree
            p[diabetes] = changed.diabetes
            p[table] = changed.dietTable
        }
    }

    override suspend fun signIn(login: String, password: String) {
        require(login.trim() == "demo" && password == "demo") {
            "Для демонстрационного входа используйте demo / demo."
        }
        store.edit { it[session] = true }
    }

    override suspend fun signInWithToken(token: String) {
        require(token.isNotBlank()) { "Яндекс не вернул токен доступа. Попробуйте ещё раз." }
        store.edit {
            it[session] = true
            it[yandexToken] = token
        }
    }

    override suspend fun signOut() {
        store.edit {
            it[session] = false
            it.remove(yandexToken)
        }
    }
}
