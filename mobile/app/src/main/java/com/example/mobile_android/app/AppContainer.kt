package com.example.mobile_android.app

import android.app.Application
import android.content.Context
import androidx.room.Room
import com.example.mobile_android.data.DemoCatalog
import com.example.mobile_android.data.DemoCatalogRepository
import com.example.mobile_android.data.local.*
import com.example.mobile_android.domain.*
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
    val yandexAuth: YandexAuthSdk
}

class AppContainer(context: Context) : AppDependencies {
    override val catalog: CatalogRepository = DemoCatalogRepository()
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
}
