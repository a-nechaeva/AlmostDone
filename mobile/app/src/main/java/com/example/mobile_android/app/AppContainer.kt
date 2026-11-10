package com.example.mobile_android.app

import android.app.Application
import android.content.Context
import androidx.room.Room
import com.example.mobile_android.data.DemoCatalog
import com.example.mobile_android.data.local.*
import com.example.mobile_android.data.remote.NetworkCatalogRepository
import com.example.mobile_android.data.remote.ServerConnection
import com.example.mobile_android.domain.*
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.first
import com.yandex.authsdk.YandexAuthOptions
import com.yandex.authsdk.YandexAuthSdk

class AlmostReadyApplication : Application() {
    val container: AppContainer by lazy { AppContainer(this) }
}

interface AppDependencies {
    val catalog: CatalogRepository
    val household: HouseholdRepository
    val preferences: PreferencesRepository
    val session: SessionRepository

    /** Сервер «Почти готово»; null — работа только на встроенном демо-каталоге (тесты, превью). */
    val server: ServerConnection?
        get() = null
    val yandexAuth: YandexAuthSdk
}

class AppContainer(context: Context) : AppDependencies {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val network =
        NetworkCatalogRepository(scope, context.applicationContext.householdPreferences, DemoCatalog.catalog)
    override val catalog: CatalogRepository = network
    override val server: ServerConnection = network
    private val database =
        Room.databaseBuilder(
                context.applicationContext,
                HouseholdDatabase::class.java,
                "household.db",
            )
            .build()
    override val household: HouseholdRepository =
        RoomHouseholdRepository(database, catalog, DemoCatalog.initialPantry)
    private val localPreferences = LocalPreferences(context.applicationContext.householdPreferences)
    override val preferences: PreferencesRepository = localPreferences
    override val session: SessionRepository = localPreferences
    override val yandexAuth: YandexAuthSdk =
        YandexAuthSdk.create(YandexAuthOptions(context.applicationContext))

    init {
        network.onConnected = { catalog, demoPantry -> seedDemoPantry(catalog, demoPantry) }
    }

    /**
     * Первое подключение к серверу: если в кладовке нет ни одного продукта из реального каталога,
     * кладём демо-набор с сервера — по одной упаковке каждого продукта.
     */
    private suspend fun seedDemoPantry(catalog: Catalog, demoPantry: List<String>) {
        val pantry = household.household.first().pantry
        if (pantry.any { catalog.ingredient(it.ingredientId) != null }) return
        demoPantry.forEach { id -> catalog.ingredient(id)?.let { household.addPantry(id, it.offer?.quantity) } }
    }
}
