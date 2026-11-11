package com.example.mobile_android.app

import android.app.Application
import android.content.Context
import androidx.activity.result.contract.ActivityResultContract
import com.example.mobile_android.BuildConfig
import com.example.mobile_android.data.local.DataStoreSessionStore
import com.example.mobile_android.data.local.householdPreferences
import com.example.mobile_android.data.remote.ApiClient
import com.example.mobile_android.data.remote.AuthenticatedApi
import com.example.mobile_android.data.remote.HttpTransport
import com.example.mobile_android.data.remote.OkHttpTransport
import com.example.mobile_android.data.remote.ServerSessionRepository
import com.example.mobile_android.domain.CatalogRepository
import com.example.mobile_android.domain.HouseholdRepository
import com.example.mobile_android.domain.PreferencesRepository
import com.example.mobile_android.domain.SessionRepository
import com.example.mobile_android.feature.auth.YandexLogin
import com.example.mobile_android.feature.auth.YandexLoginResult
import com.example.mobile_android.feature.receipt.ReceiptImporter
import com.example.mobile_android.feature.shopping.ShoppingBudgetPlanWriter

class AlmostReadyApplication : Application() {
    val container: AppContainer by lazy { AppContainer(this) }
}

interface AppDependencies {
    val session: SessionRepository
    val yandexLogin: ActivityResultContract<Unit, YandexLoginResult>
}

/** Dependencies for hosts that exercise the feature screens with local data. */
interface LocalFeatureDependencies : AppDependencies {
    val catalog: CatalogRepository
    val household: HouseholdRepository
    val preferences: PreferencesRepository
    val receiptImporter: ReceiptImporter? get() = null
    val budgetPlanWriter: ShoppingBudgetPlanWriter? get() = null
}

class AppContainer internal constructor(
    context: Context,
    baseUrl: String,
    transport: HttpTransport,
    override val yandexLogin: ActivityResultContract<Unit, YandexLoginResult>,
) : AppDependencies {
    constructor(context: Context) :
        this(context, BuildConfig.API_BASE_URL, OkHttpTransport(), YandexLogin(context))

    private val client = ApiClient(baseUrl, transport, BuildConfig.DEBUG)
    private val sessions = ServerSessionRepository(
        client,
        DataStoreSessionStore(context.applicationContext.householdPreferences, client.serverKey),
    )
    override val session: SessionRepository = sessions

    val api: AuthenticatedApi = sessions
}
