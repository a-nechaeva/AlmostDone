package com.example.mobile_android.data.remote

import com.example.mobile_android.domain.FoodPreferences
import com.example.mobile_android.domain.PreferencesRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.emitAll
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Профиль текущего пользователя через `GET /me` и `PATCH /me` (см. OpenAPI `profile_get`/`profile_save`).
 *
 * Одна отправка записывает полный черновик `Preferences` с `If-Match` по последней известной версии
 * состояния. На `412 state_conflict` профиль перечитывается, преобразование применяется к свежему
 * состоянию и сохранение повторяется один раз с актуальным `If-Match`; дальнейший конфликт отдаётся
 * вызывающему как ошибка, ввод при этом не теряется (черновик хранит форма).
 */
class ServerPreferencesRepository(private val api: AuthenticatedApi) : PreferencesRepository {
    private class Snapshot(val etag: String?, val preferences: FoodPreferences)

    private val lock = Mutex()
    private val snapshot = MutableStateFlow<Snapshot?>(null)

    override val preferences: Flow<FoodPreferences> =
        flow {
                emit(load())
                emitAll(snapshot.filterNotNull().map { it.preferences })
            }
            .distinctUntilChanged()

    private suspend fun load(): FoodPreferences =
        lock.withLock {
            snapshot.value?.preferences?.let { return it }
            val response = api.execute(ApiRequest("me"))
            val body = response.json ?: throw ApiProtocolException()
            val parsed = parseProfilePreferences(body)
            snapshot.value = Snapshot(response.etag, parsed)
            parsed
        }

    override suspend fun update(transform: (FoodPreferences) -> FoodPreferences) {
        lock.withLock {
            val current = snapshot.value ?: run {
                val response = api.execute(ApiRequest("me"))
                val body = response.json ?: throw ApiProtocolException()
                Snapshot(response.etag, parseProfilePreferences(body)).also { snapshot.value = it }
            }
            val draft = transform(current.preferences)
            if (draft == current.preferences) return
            try {
                save(current.etag, draft)
            } catch (conflict: ApiHttpException) {
                if (conflict.status != 412 && conflict.status != 428) throw conflict
                val fresh = reload()
                val retried = transform(fresh.preferences)
                if (retried != fresh.preferences) save(fresh.etag, retried)
            }
        }
    }

    /** Перечитать профиль после конфликта версии, сохранив ввод вызывающего для повторного применения. */
    private suspend fun reload(): Snapshot {
        val response = api.execute(ApiRequest("me"))
        val body = response.json ?: throw ApiProtocolException()
        return Snapshot(response.etag, parseProfilePreferences(body)).also { snapshot.value = it }
    }

    private suspend fun save(etag: String?, draft: FoodPreferences) {
        val response =
            api.execute(
                ApiRequest(
                    "me",
                    ApiMethod.PATCH,
                    profileUpdateJson(draft),
                    ifMatch = etag ?: throw ApiProtocolException(),
                )
            )
        val body = response.json ?: throw ApiProtocolException()
        snapshot.value = Snapshot(response.etag ?: etag, parseProfilePreferences(body))
    }
}
