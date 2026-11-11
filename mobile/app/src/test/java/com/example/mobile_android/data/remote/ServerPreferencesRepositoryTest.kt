package com.example.mobile_android.data.remote

import com.example.mobile_android.domain.Allergen
import com.example.mobile_android.domain.FoodPreferences
import com.example.mobile_android.domain.FoodType
import java.util.ArrayDeque
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.test.runTest
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], application = android.app.Application::class)
class ServerPreferencesRepositoryTest {
    private class FakeApi : AuthenticatedApi {
        val requests = mutableListOf<ApiRequest>()
        val responses = ArrayDeque<ApiResponse>()
        var failure: Exception? = null

        override suspend fun execute(request: ApiRequest): ApiResponse {
            requests += request
            failure?.let { failure = null; throw it }
            val response = responses.poll() ?: error("Unexpected request: ${request.method} ${request.path}")
            if (response.status !in 200..299) throw ApiHttpException(response.status, null, response.etag, response.retryAfter)
            return response
        }
    }

    private fun profile(
        etag: String,
        foodType: String = "any",
        allergens: List<String> = emptyList(),
        glutenFree: Boolean = false,
        lactoseFree: Boolean = false,
        diabetes: Boolean = false,
        dietTableId: String? = null,
    ): ApiResponse {
        val array = JSONArray()
        allergens.forEach(array::put)
        val body =
            JSONObject()
                .put("user_id", "user-1")
                .put("display_name", JSONObject.NULL)
                .put(
                    "preferences",
                    JSONObject()
                        .put("food_type", foodType)
                        .put("excluded_allergens", array)
                        .put("gluten_free", glutenFree)
                        .put("lactose_free", lactoseFree)
                        .put("diabetes", diabetes)
                        .put("diet_table_id", dietTableId ?: JSONObject.NULL),
                )
                .put("unsupported_restrictions", JSONArray())
                .put("state_version", 1)
        return ApiResponse(200, body, etag, null)
    }

    @Test
    fun loadsProfileAndMapsAllergens() = runTest {
        val api = FakeApi()
        api.responses += profile(
            "\"state-1\"",
            foodType = "vegetarian",
            allergens = listOf("peanuts", "sesame", "milk", "unknown-allergen"),
            lactoseFree = true,
            dietTableId = "table-9",
        )
        val repository = ServerPreferencesRepository(api)

        val prefs = repository.preferences.first()

        assertEquals(
            FoodPreferences(
                foodType = FoodType.VEGETARIAN,
                excludedAllergens = setOf(Allergen.PEANUTS, Allergen.SESAME, Allergen.MILK),
                lactoseFree = true,
                dietTable = "table-9",
            ),
            prefs,
        )
        assertEquals(listOf("me"), api.requests.map { it.path })
        assertEquals(listOf(ApiMethod.GET), api.requests.map { it.method })
    }

    @Test
    fun savesFullDraftWithIfMatch() = runTest {
        val api = FakeApi()
        api.responses += profile("\"state-1\"")
        api.responses += profile("\"state-2\"", foodType = "vegan", allergens = listOf("eggs", "peanuts"))
        val repository = ServerPreferencesRepository(api)
        repository.preferences.first()

        repository.update {
            it.copy(
                foodType = FoodType.VEGAN,
                excludedAllergens = setOf(Allergen.PEANUTS, Allergen.EGGS),
                dietTable = "",
            )
        }

        val patch = api.requests[1]
        assertEquals("me", patch.path)
        assertEquals(ApiMethod.PATCH, patch.method)
        assertEquals("\"state-1\"", patch.ifMatch)
        val sent = JSONObject(checkNotNull(patch.jsonBody)).getJSONObject("preferences")
        assertEquals("vegan", sent.getString("food_type"))
        assertEquals(
            listOf("eggs", "peanuts"),
            sent.getJSONArray("excluded_allergens").let { a -> List(a.length()) { a.getString(it) } },
        )
        assertTrue(sent.isNull("diet_table_id"))
        assertEquals(
            FoodPreferences(FoodType.VEGAN, setOf(Allergen.PEANUTS, Allergen.EGGS)),
            repository.preferences.first(),
        )
    }

    @Test
    fun conflictReloadsStateAndRetriesTransformOnce() = runTest {
        val api = FakeApi()
        api.responses += profile("\"state-1\"")
        api.responses += ApiResponse(412, null, null, null)
        api.responses += profile("\"state-2\"", foodType = "vegan")
        api.responses += profile("\"state-3\"", foodType = "vegan", diabetes = true)
        val repository = ServerPreferencesRepository(api)
        repository.preferences.first()

        repository.update { it.copy(diabetes = true) }

        assertEquals(
            listOf(ApiMethod.GET, ApiMethod.PATCH, ApiMethod.GET, ApiMethod.PATCH),
            api.requests.map { it.method },
        )
        assertEquals("\"state-2\"", api.requests[3].ifMatch)
        // Преобразование применилось к свежему состоянию: выбор сервера (vegan) не потерян.
        assertEquals(
            FoodPreferences(FoodType.VEGAN, diabetes = true),
            repository.preferences.first(),
        )
    }

    @Test
    fun readErrorPropagatesToTheScreenState() = runTest {
        val api = FakeApi()
        api.failure = ApiNetworkException(timedOut = false)
        val repository = ServerPreferencesRepository(api)

        assertThrows(ApiNetworkException::class.java) {
            kotlinx.coroutines.runBlocking { repository.preferences.first() }
        }
    }

    @Test
    fun secondCollectorSeesUpdatesWithoutNewRequests() = runTest {
        val api = FakeApi()
        api.responses += profile("\"state-1\"")
        api.responses += profile("\"state-2\"", glutenFree = true)
        val repository = ServerPreferencesRepository(api)

        val first = repository.preferences.take(1).toList()
        repository.update { it.copy(glutenFree = true) }
        val second = repository.preferences.take(1).toList()

        assertEquals(listOf(FoodPreferences()), first)
        assertEquals(listOf(FoodPreferences(glutenFree = true)), second)
        // GET + PATCH: повторный коллектор читает снимок, а не сеть.
        assertEquals(2, api.requests.size)
    }
}
