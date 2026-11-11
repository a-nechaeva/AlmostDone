package com.example.mobile_android.data.remote

import android.app.Application
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import com.example.mobile_android.app.AppContainer
import com.example.mobile_android.data.local.householdPreferences
import com.example.mobile_android.ui.FakeYandexLogin
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], application = Application::class)
class LegacySessionMigrationTest {
    @Test
    fun appContainerNeverUsesOldSignedInFlagProviderTokenOrServerAddress() = runTest {
        val context = RuntimeEnvironment.getApplication()
        val store = context.householdPreferences
        val oldServer = stringPreferencesKey("server_url")
        val oldSignedIn = booleanPreferencesKey("demo_signed_in")
        val oldProviderToken = stringPreferencesKey("yandex_oauth_token")
        store.edit {
            it.clear()
            it[oldServer] = "https://old.example.test/api/v1/"
            it[oldSignedIn] = true
            it[oldProviderToken] = "old-provider-token"
        }
        val requests = mutableListOf<HttpRequest>()
        val transport = HttpTransport {
            requests += it
            when (it.url.encodedPath) {
                "/api/v1/auth/yandex" -> session("first")
                "/api/v1/me/state" -> state()
                else -> error("Unexpected request")
            }
        }
        val app = AppContainer(context, "https://new.example.test", transport, FakeYandexLogin())
        assertNull(app.session.sessionKey.first())
        assertTrue(requests.isEmpty())
        val prefs = store.data.first()
        assertNull(prefs[oldServer])
        assertNull(prefs[oldSignedIn])
        assertNull(prefs[oldProviderToken])

        app.session.signInWithToken("new-provider-token")
        val key = app.session.sessionKey.first()
        assertNotNull(key)
        val restarted = AppContainer(context, "https://new.example.test", transport, FakeYandexLogin())
        assertEquals(key, restarted.session.sessionKey.first())
        assertEquals(List(3) { "new.example.test" }, requests.map { it.url.host })

        val otherServer = AppContainer(context, "https://another.example.test", transport, FakeYandexLogin())
        assertNull(otherServer.session.sessionKey.first())
        assertEquals(3, requests.size)
    }
}
