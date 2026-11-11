package com.example.mobile_android.app

import android.app.Application
import android.content.Context
import androidx.activity.result.contract.ActivityResultContract
import androidx.room.Room
import com.example.mobile_android.BuildConfig
import com.example.mobile_android.data.DemoCatalogRepository
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
import com.example.mobile_android.feature.shopping.ShoppingBudgetPlanWriter
import java.util.Locale
import kotlinx.coroutines.CancellationException

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

    /**
     * Серверное распознавание фото чека/продуктов. null — экран использует демо-заглушку
     * (строки помечаются как демонстрационные, а не серверные).
     */
    val receiptPhotoRecognizer: (suspend (ByteArray, ReceiptPhotoKind) -> List<ReceiptLine>)?
        get() = null
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
 * Продукты, план, покупки и отметки хранятся в Room-файле этой сессии и восстанавливаются
 * после перезапуска; профиль читается и сохраняется через `GET/PATCH /me`; распознавание чека
 * идёт через `POST /recognitions`. Каталог пока демонстрационный: контракт не даёт перечислить
 * серверный каталог (поиск требует непустого `q`), поэтому серверные синонимы догоняются
 * отдельным согласованием контракта (#17/#34).
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

    override val catalog: CatalogRepository = DemoCatalogRepository()

    private val room = RoomHouseholdRepository(database, catalog, emptyList())

    override val household: HouseholdRepository = room
    override val preferences: PreferencesRepository = ServerPreferencesRepository(api)
    override val receiptImporter: ReceiptImporter = room
    override val budgetPlanWriter: ShoppingBudgetPlanWriter = room

    override val receiptPhotoRecognizer: suspend (ByteArray, ReceiptPhotoKind) -> List<ReceiptLine> =
        { jpeg, kind ->
            try {
                recognitions.recognize(jpeg, kind.apiKind).toReceiptLines()
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                throw ReceiptServerException(error.message, error)
            }
        }

    fun close() {
        database.close()
    }
}

private fun RecognitionResult.toReceiptLines(): List<ReceiptLine> =
    lines.mapIndexed { index, line ->
        ReceiptLine(
            id = index + 1,
            text = line.rawName,
            ingredientId = line.ingredientId,
            amount = line.quantity?.let(::formatAmount).orEmpty(),
            unit = line.quantity?.unit,
            selected = line.matched && line.quantity != null,
        )
    }

private fun formatAmount(quantity: com.example.mobile_android.domain.Quantity): String {
    val value = quantity.value
    val rounded = value.toLong()
    return if (value == rounded.toDouble()) rounded.toString()
    else String.format(Locale.US, "%.2f", value).trimEnd('0').trimEnd('.')
}
