package com.example.mobile_android.app

import android.app.Application
import android.content.Context
import androidx.activity.result.contract.ActivityResultContract
import androidx.room.Room
import com.example.mobile_android.BuildConfig
import com.example.mobile_android.data.DemoCatalog
import com.example.mobile_android.data.local.DataStoreSessionStore
import com.example.mobile_android.data.local.HouseholdDatabase
import com.example.mobile_android.data.local.RoomHouseholdRepository
import com.example.mobile_android.data.local.householdPreferences
import com.example.mobile_android.data.remote.ApiClient
import com.example.mobile_android.data.remote.AuthenticatedApi
import com.example.mobile_android.data.remote.HttpTransport
import com.example.mobile_android.data.remote.OkHttpTransport
import com.example.mobile_android.data.remote.RecognitionApi
import com.example.mobile_android.data.remote.RecognitionResult
import com.example.mobile_android.data.remote.ServerCatalogRepository
import com.example.mobile_android.data.remote.ServerHouseholdRepository
import com.example.mobile_android.data.remote.ServerPreferencesRepository
import com.example.mobile_android.data.remote.ServerSessionRepository
import com.example.mobile_android.domain.CatalogRepository
import com.example.mobile_android.domain.HouseholdRepository
import com.example.mobile_android.domain.PreferencesRepository
import com.example.mobile_android.domain.SessionRepository
import com.example.mobile_android.feature.auth.YandexLogin
import com.example.mobile_android.feature.auth.YandexLoginResult
import com.example.mobile_android.feature.receipt.ReceiptImporter
import com.example.mobile_android.feature.receipt.ReceiptLine
import com.example.mobile_android.feature.receipt.ReceiptPhotoKind
import com.example.mobile_android.feature.receipt.ReceiptServerException
import com.example.mobile_android.feature.receipt.RecognizedReceipt
import com.example.mobile_android.feature.receipt.ServerReceiptImporter
import com.example.mobile_android.feature.shopping.EngineShoppingBudgetSource
import com.example.mobile_android.feature.shopping.EngineShoppingSuggestionSource
import com.example.mobile_android.feature.shopping.ShoppingBudgetPlanWriter
import com.example.mobile_android.feature.shopping.ShoppingBudgetSource
import com.example.mobile_android.feature.shopping.ShoppingSuggestionSource
import java.util.Locale
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel

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

    /** Подбор покупок на бюджет и подсказка «что докупить»; null — фиксированные UI-примеры. */
    val budgetSource: ShoppingBudgetSource? get() = null
    val suggestionSource: ShoppingSuggestionSource? get() = null

    /**
     * Серверное распознавание фото чека/продуктов. null — экран использует демо-заглушку
     * (строки помечаются как демонстрационные, а не серверные).
     */
    val receiptPhotoRecognizer: (suspend (ByteArray, ReceiptPhotoKind) -> RecognizedReceipt)?
        get() = null

    /**
     * Подтверждение импорта распознанного чека на сервере (`POST /recognition-imports`).
     * null — подтверждение пишет только в локальное хранилище через [receiptImporter].
     */
    val serverReceiptImporter: ServerReceiptImporter? get() = null
}

class AppContainer internal constructor(
    context: Context,
    baseUrl: String,
    transport: HttpTransport,
    override val yandexLogin: ActivityResultContract<Unit, YandexLoginResult>,
) : AppDependencies {
    constructor(context: Context) :
        this(context, BuildConfig.API_BASE_URL, OkHttpTransport(), YandexLogin(context))

    private val appContext = context.applicationContext
    private val client = ApiClient(baseUrl, transport, BuildConfig.DEBUG)
    private val sessions = ServerSessionRepository(
        client,
        DataStoreSessionStore(context.applicationContext.householdPreferences, client.serverKey),
    )
    override val session: SessionRepository = sessions

    val api: AuthenticatedApi = sessions

    private val recognitions = RecognitionApi(api)

    /**
     * Данные экранов создаются заново для каждой подтверждённой сессии: локальная база
     * привязана к ключу сессии, поэтому продукты, покупки и черновики разных аккаунтов
     * изолированы, а при смене пользователя прежняя база закрывается.
     */
    @Volatile private var activeFeatures: Pair<String, SessionFeatures>? = null

    @Synchronized
    fun sessionFeatures(sessionKey: String): LocalFeatureDependencies {
        activeFeatures?.takeIf { it.first == sessionKey }?.let { return it.second }
        activeFeatures?.second?.close()
        val created = SessionFeatures(appContext, this, api, recognitions, sessionKey)
        activeFeatures = sessionKey to created
        return created
    }
}

/**
 * Зависимости экранов одной подтверждённой сессии.
 *
 * План блюд, список покупок и отметки «куплено» хранятся в Room-файле этой сессии и
 * восстанавливаются после перезапуска; профиль читается и сохраняется через `GET/PATCH /me`;
 * продукты дома и избранное пишутся на сервер (`pantry_*`, `favorites_*`) и зеркалируются
 * в Room; распознавание чека идёт через `POST /recognitions`, подтверждение импорта — через
 * `POST /recognition-imports`. Каталог загружается с сервера (`GET /catalog`); пока он
 * грузится или если сервер недоступен, экраны работают на встроенном демо-каталоге.
 */
private class SessionFeatures(
    context: Context,
    container: AppDependencies,
    api: AuthenticatedApi,
    recognitions: RecognitionApi,
    sessionKey: String,
) : LocalFeatureDependencies, AppDependencies by container {
    private val database =
        Room.databaseBuilder(
                context,
                HouseholdDatabase::class.java,
                "household-" + sessionKey.filter { it.isLetterOrDigit() }.take(64) + ".db",
            )
            .build()

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override val catalog: CatalogRepository = ServerCatalogRepository(api, DemoCatalog.catalog, scope)

    private val room = RoomHouseholdRepository(database, catalog, emptyList())
    private val serverHousehold = ServerHouseholdRepository(room, catalog, api)

    override val household: HouseholdRepository = serverHousehold
    override val preferences: PreferencesRepository = ServerPreferencesRepository(api)
    override val receiptImporter: ReceiptImporter = serverHousehold
    override val serverReceiptImporter: ServerReceiptImporter = serverHousehold
    override val budgetPlanWriter: ShoppingBudgetPlanWriter = room
    override val budgetSource: ShoppingBudgetSource =
        EngineShoppingBudgetSource(catalog, household, preferences)
    override val suggestionSource: ShoppingSuggestionSource = EngineShoppingSuggestionSource()

    override val receiptPhotoRecognizer: suspend (ByteArray, ReceiptPhotoKind) -> RecognizedReceipt =
        { jpeg, kind ->
            try {
                recognitions.recognize(jpeg, kind.apiKind).toRecognizedReceipt()
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                throw ReceiptServerException(error.message, error)
            }
        }

    fun close() {
        scope.cancel()
        database.close()
    }
}

private fun RecognitionResult.toRecognizedReceipt(): RecognizedReceipt =
    RecognizedReceipt(
        id,
        lines.mapIndexed { index, line ->
            ReceiptLine(
                id = index + 1,
                text = line.rawName,
                ingredientId = line.ingredientId,
                amount = line.quantity?.let(::formatAmount).orEmpty(),
                unit = line.quantity?.unit,
                selected = line.matched && line.quantity != null,
                serverLineId = line.lineId,
            )
        },
    )

private fun formatAmount(quantity: com.example.mobile_android.domain.Quantity): String {
    val value = quantity.value
    val rounded = value.toLong()
    return if (value == rounded.toDouble()) rounded.toString()
    else String.format(Locale.US, "%.2f", value).trimEnd('0').trimEnd('.')
}
