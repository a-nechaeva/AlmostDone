package com.example.mobile_android.feature.auth

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.mobile_android.data.remote.ApiConfigurationException
import com.example.mobile_android.data.remote.ApiHttpException
import com.example.mobile_android.data.remote.ApiNetworkException
import com.example.mobile_android.data.remote.SessionExpiredException
import com.example.mobile_android.domain.SessionRepository
import com.example.mobile_android.feature.common.ScreenActions
import com.example.mobile_android.feature.common.ScreenState
import com.example.mobile_android.feature.common.loadingStates
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update

class SessionViewModel(private val repository: SessionRepository) : ViewModel() {
    private val refresh = MutableStateFlow(0)
    val actions = ScreenActions(viewModelScope)

    // Session state owns the navigation graph, so a lifecycle pause must not restart it.
    val state = loadingStates(refresh, { ScreenState.Error(messageFor(it)) }) { repository.sessionKey }
        .stateIn(viewModelScope, SharingStarted.Eagerly, ScreenState.Loading)

    fun retry() {
        refresh.update { it + 1 }
    }

    fun signInWithYandex(token: String) {
        runAction { repository.signInWithToken(token) }
    }

    fun yandexAuthFailed() {
        actions.showError("Не удалось войти через Яндекс. Попробуйте ещё раз.")
    }

    fun signOut() {
        runAction { repository.signOut() }
    }

    private fun runAction(action: suspend () -> Unit) {
        actions.run {
            try {
                action()
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                throw IllegalArgumentException(messageFor(error))
            }
        }
    }

    private fun messageFor(error: Throwable): String = when (error) {
        is ApiConfigurationException -> "В этой сборке не задан адрес сервера."
        is ApiNetworkException -> if (error.timedOut) "Сервер не ответил вовремя." else "Нет связи с сервером."
        is SessionExpiredException -> "Сессия завершилась. Войдите снова."
        is ApiHttpException -> when (error.status) {
            401 -> "Яндекс не подтвердил вход. Попробуйте ещё раз."
            429 -> "Слишком много запросов. Попробуйте позже."
            else -> "Сервер не смог выполнить запрос. Попробуйте позже."
        }
        else -> "Не удалось выполнить действие. Попробуйте ещё раз."
    }
}
