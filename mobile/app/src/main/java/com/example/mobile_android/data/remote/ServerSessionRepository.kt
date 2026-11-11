package com.example.mobile_android.data.remote

import com.example.mobile_android.domain.SessionRepository
import java.io.IOException
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.emitAll
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.json.JSONObject

internal class SessionTokens(
    val userId: String,
    val access: String,
    val refresh: String,
    val accessUntil: Long,
    val refreshUntil: Long,
    val navigationKey: String,
    val refreshWait: RefreshWait? = null,
) {
    fun withRefreshWait(wait: RefreshWait) =
        SessionTokens(userId, access, refresh, accessUntil, refreshUntil, navigationKey, wait)
}

internal class RefreshWait(val status: Int, val until: Long)

internal interface SessionStore {
    suspend fun read(): SessionTokens?
    suspend fun write(tokens: SessionTokens?)
}

class SessionExpiredException internal constructor() : IOException()

internal class ServerSessionRepository(
    private val api: ApiClient,
    private val store: SessionStore,
    private val now: () -> Long = System::currentTimeMillis,
) : SessionRepository, AuthenticatedApi {
    private class Session(var tokens: SessionTokens) {
        val userId = tokens.userId
        val navigationKey = tokens.navigationKey
        val rotation = Mutex()
        var refreshRetired = false
        var rejection: RefreshRejection? = null
    }

    private class RefreshRejection(val error: ApiHttpException, now: Long) {
        private val seconds = maxOf(1L, error.retryAfter?.toLongOrNull() ?: 1L)
        val wait = RefreshWait(error.status, try {
            Math.addExact(now, Math.multiplyExact(seconds, 1_000L))
        } catch (_: ArithmeticException) {
            Long.MAX_VALUE
        })
    }

    private val lock = Mutex()
    private val restoration = Mutex()
    private val navigation = MutableStateFlow<String?>(null)
    private var current: Session? = null
    private var generation = 0L
    private var loaded = false
    private var restored = false

    override val sessionKey = flow {
        restore()
        emitAll(navigation)
    }

    private suspend fun restore() {
        restoration.withLock {
            val session = lock.withLock {
                if (restored) return
                if (!loaded) {
                    current = store.read()?.let(::Session)
                    loaded = true
                }
                current ?: run {
                    restored = true
                    return
                }
            }
            try {
                verify(session)
            } catch (_: SessionExpiredException) {
                // The protected request already invalidated this session, or it was replaced.
            } catch (_: ApiProtocolException) {
                invalidate(session)
            }
            lock.withLock {
                if (current === session) navigation.value = session.navigationKey
                restored = true
            }
        }
    }

    override suspend fun signInWithToken(token: String) {
        require(token.isNotBlank())
        val attempt = updateSession {
            store.write(null)
            current = null
            navigation.value = null
            loaded = true
            restored = true
            ++generation
        }
        val tokens = exchange("auth/yandex", "oauth_token", token, UUID.randomUUID().toString())
        val session = Session(tokens)
        updateSession {
            if (generation != attempt) throw SessionExpiredException()
            store.write(tokens)
            current = session
        }
        try {
            verify(session)
            lock.withLock {
                requireCurrent(session)
                navigation.value = session.navigationKey
            }
        } catch (error: Exception) {
            invalidate(session)
            throw error
        }
    }

    override suspend fun signOut() {
        val session = updateSession {
            val previous = current
            store.write(null)
            current = null
            ++generation
            loaded = true
            restored = true
            navigation.value = null
            previous
        } ?: return
        // If a rotation was sent before logout, revoke using its replacement access token.
        session.rotation.withLock {
            val tokens = session.tokens
            if (tokens.accessUntil > now() || !canRefresh(session)) {
                if (revoke(tokens.access) || !canRefresh(session)) return@withLock
            }
            try {
                revoke(refresh(session).access)
            } catch (error: ApiHttpException) {
                if (error.status != 401) throw error
            }
        }
    }

    private suspend fun revoke(access: String): Boolean = try {
        val request = ApiRequest("auth/logout", ApiMethod.POST)
        try {
            api.execute(request, access)
        } catch (error: ApiNetworkException) {
            if (error.timedOut) throw error
            // A closed idle connection can fail before we get a response. Revocation is safe to repeat.
            api.execute(request, access)
        }
        true
    } catch (error: ApiHttpException) {
        if (error.status != 401) throw error
        false
    }

    override suspend fun execute(request: ApiRequest): ApiResponse {
        val session = lock.withLock {
            if (navigation.value == null) throw SessionExpiredException()
            current ?: throw SessionExpiredException()
        }
        return execute(session, request)
    }

    private suspend fun verify(session: Session) {
        val state = execute(session, ApiRequest("me/state")).json ?: throw ApiProtocolException()
        val version = state.opt("state_version") as? Number
        val catalog = state.opt("catalog_version") as? String
        if (version == null || version.toLong() < 0 || catalog.isNullOrBlank() || state.opt("user_id") != session.userId) {
            throw ApiProtocolException()
        }
    }

    private suspend fun execute(session: Session, request: ApiRequest): ApiResponse {
        val initial = lock.withLock {
            requireCurrent(session)
            session.tokens
        }
        var tokens = if (initial.accessUntil <= now()) rotate(session, initial) else initial
        try {
            return send(session, tokens, request)
        } catch (error: ApiHttpException) {
            if (error.status != 401) throw error
        }
        tokens = rotate(session, tokens)
        try {
            return send(session, tokens, request)
        } catch (error: ApiHttpException) {
            if (error.status != 401) throw error
            invalidate(session, tokens)
            throw SessionExpiredException()
        }
    }

    private suspend fun send(session: Session, tokens: SessionTokens, request: ApiRequest): ApiResponse {
        lock.withLock { requireCurrent(session) }
        val result = try {
            api.execute(request, tokens.access)
        } catch (error: IOException) {
            lock.withLock { requireCurrent(session) }
            throw error
        }
        lock.withLock { requireCurrent(session) }
        return result
    }

    private suspend fun rotate(session: Session, rejected: SessionTokens): SessionTokens =
        session.rotation.withLock {
            val tokens = updateSession {
                requireCurrent(session)
                val latest = session.tokens
                if (latest === rejected) {
                    checkRefreshRejection(session)
                    // Retire the single-use token on disk before sending it, including across process death.
                    store.write(null)
                }
                latest
            }
            if (tokens !== rejected) return@withLock tokens
            try {
                val replacement = refresh(session)
                updateSession {
                    // Logout can still revoke the replacement after detaching this session.
                    session.tokens = replacement
                    requireCurrent(session)
                    store.write(replacement)
                }
                replacement
            } catch (error: Exception) {
                val wait = session.rejection?.takeIf { it.error === error }?.wait
                val active = updateSession {
                    if (current !== session) false
                    else {
                        if (wait != null) store.write(tokens.withRefreshWait(wait))
                        else {
                            current = null
                            navigation.value = null
                        }
                        true
                    }
                }
                if (error is CancellationException || (active && wait != null)) throw error
                throw SessionExpiredException()
            }
        }

    private fun canRefresh(session: Session): Boolean =
        !session.refreshRetired && session.tokens.refreshUntil > now()

    private fun checkRefreshRejection(session: Session) {
        val time = now()
        if (session.tokens.refreshUntil <= time) return
        session.rejection?.takeIf { it.wait.until > time }?.let { throw it.error }
        val wait = session.tokens.refreshWait?.takeIf { it.until > time } ?: return
        val remainingSeconds = (wait.until - time - 1) / 1_000 + 1
        throw ApiHttpException(wait.status, null, null, remainingSeconds.toString())
    }

    // Called under the session's rotation mutex, including the final rotation before logout.
    private suspend fun refresh(session: Session): SessionTokens {
        val tokens = session.tokens
        if (!canRefresh(session)) throw SessionExpiredException()
        checkRefreshRejection(session)
        session.rejection = null
        session.refreshRetired = true
        val replacement = try {
            exchange("auth/refresh", "refresh_token", tokens.refresh, tokens.navigationKey)
        } catch (error: ApiHttpException) {
            // These structured responses from the API reject the request before committing rotation.
            val code = error.error?.code
            val rejected = (error.status == 429 && code == "rate_limited") ||
                (error.status == 503 && code == "service_unavailable")
            if (rejected && error.error?.retryable == true) {
                session.refreshRetired = false
                session.rejection = RefreshRejection(error, now())
            }
            throw error
        }
        if (replacement.userId != session.userId) throw ApiProtocolException()
        session.refreshRetired = false
        return replacement
    }

    private suspend fun invalidate(session: Session, tokens: SessionTokens? = null) = updateSession {
        if (current === session && (tokens == null || session.tokens === tokens)) {
            store.write(null)
            current = null
            navigation.value = null
        }
    }

    private fun requireCurrent(session: Session) {
        if (current !== session) throw SessionExpiredException()
    }

    private suspend fun <T> updateSession(update: suspend () -> T): T =
        withContext(NonCancellable) { lock.withLock { update() } }

    private suspend fun exchange(
        path: String,
        field: String,
        value: String,
        navigationKey: String,
    ): SessionTokens {
        val start = now()
        val json = api.execute(ApiRequest(path, ApiMethod.POST, JSONObject().put(field, value))).json
            ?: throw ApiProtocolException()
        return runCatching {
            val userId = json.get("user_id") as String
            val access = json.get("access_token") as String
            val refresh = json.get("refresh_token") as String
            val accessSeconds = json.getLong("expires_in")
            val refreshSeconds = json.getLong("refresh_expires_in")
            require(json.get("token_type") == "Bearer" && userId.isNotBlank() &&
                access.isNotBlank() && refresh.isNotBlank() && accessSeconds > 0 && refreshSeconds > 0)
            SessionTokens(
                userId,
                access,
                refresh,
                Math.addExact(start, Math.multiplyExact(accessSeconds, 1_000L)),
                Math.addExact(start, Math.multiplyExact(refreshSeconds, 1_000L)),
                navigationKey,
            )
        }.getOrElse { throw ApiProtocolException() }
    }
}
