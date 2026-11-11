package com.example.mobile_android.data.local

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import com.example.mobile_android.data.remote.RefreshWait
import com.example.mobile_android.data.remote.SessionStore
import com.example.mobile_android.data.remote.SessionTokens

internal class DataStoreSessionStore(
    private val store: DataStore<Preferences>,
    private val serverKey: String,
) : SessionStore {
    private val server = stringPreferencesKey("session_server")
    private val user = stringPreferencesKey("session_user_id")
    private val access = stringPreferencesKey("session_access_token")
    private val refresh = stringPreferencesKey("session_refresh_token")
    private val accessUntil = longPreferencesKey("session_access_until")
    private val refreshUntil = longPreferencesKey("session_refresh_until")
    private val navigationKey = stringPreferencesKey("session_navigation_key")
    private val retryStatus = intPreferencesKey("session_refresh_retry_status")
    private val retryUntil = longPreferencesKey("session_refresh_retry_until")

    override suspend fun read(): SessionTokens? {
        val saved = store.edit {
            it.remove(stringPreferencesKey("server_url"))
            it.remove(booleanPreferencesKey("demo_signed_in"))
            it.remove(stringPreferencesKey("yandex_oauth_token"))
            if (it[server] != serverKey || serverKey.isEmpty()) {
                it.remove(server)
                it.remove(user)
                it.remove(access)
                it.remove(refresh)
                it.remove(accessUntil)
                it.remove(refreshUntil)
                it.remove(navigationKey)
                it.remove(retryStatus)
                it.remove(retryUntil)
            }
        }
        val wait = saved[retryStatus]?.let { status ->
            saved[retryUntil]?.let { until -> RefreshWait(status, until) }
        }
        return SessionTokens(
            saved[user] ?: return null,
            saved[access] ?: return null,
            saved[refresh] ?: return null,
            saved[accessUntil] ?: return null,
            saved[refreshUntil] ?: return null,
            saved[navigationKey] ?: return null,
            wait,
        )
    }

    override suspend fun write(tokens: SessionTokens?) {
        store.edit {
            it.remove(retryStatus)
            it.remove(retryUntil)
            if (tokens == null) {
                it.remove(server)
                it.remove(user)
                it.remove(access)
                it.remove(refresh)
                it.remove(accessUntil)
                it.remove(refreshUntil)
                it.remove(navigationKey)
            } else {
                it[server] = serverKey
                it[user] = tokens.userId
                it[access] = tokens.access
                it[refresh] = tokens.refresh
                it[accessUntil] = tokens.accessUntil
                it[refreshUntil] = tokens.refreshUntil
                it[navigationKey] = tokens.navigationKey
                tokens.refreshWait?.let { wait ->
                    it[retryStatus] = wait.status
                    it[retryUntil] = wait.until
                }
            }
        }
    }
}
