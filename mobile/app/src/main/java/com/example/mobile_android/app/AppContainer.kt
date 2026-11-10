package com.example.mobile_android.app

import android.app.Application
import android.content.Context
import androidx.room.Room
import com.example.mobile_android.data.DemoCatalog
import com.example.mobile_android.data.DemoCatalogRepository
import com.example.mobile_android.data.local.*
import com.example.mobile_android.domain.*

class AlmostReadyApplication : Application() {
    val container: AppContainer by lazy { AppContainer(this) }
}

class AppContainer(context: Context) {
    val catalog: CatalogRepository = DemoCatalogRepository()
    private val database =
        Room.databaseBuilder(
                context.applicationContext,
                HouseholdDatabase::class.java,
                "household.db",
            )
            .build()
    val household: HouseholdRepository =
        RoomHouseholdRepository(database, catalog, DemoCatalog.initialPantry)
    private val localPreferences = LocalPreferences(context.applicationContext.householdPreferences)
    val preferences: PreferencesRepository = localPreferences
    val session: SessionRepository = localPreferences
}
