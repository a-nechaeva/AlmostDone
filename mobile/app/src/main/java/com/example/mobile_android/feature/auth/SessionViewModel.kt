package com.example.mobile_android.feature.auth

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.mobile_android.domain.SessionRepository
import com.example.mobile_android.feature.common.*
import kotlinx.coroutines.flow.*

data class LoginForm(val login: String = "", val password: String = "")

class SessionViewModel(private val repository: SessionRepository) : ViewModel() {
    private val refresh = MutableStateFlow(0)
    val actions = ScreenActions(viewModelScope)
    private val mutableForm = MutableStateFlow(LoginForm())
    val form = mutableForm.asStateFlow()
    val state =
        loadingStates(refresh) { repository.signedIn }
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), ScreenState.Loading)

    fun retry() {
        refresh.update { it + 1 }
    }

    fun loginChanged(value: String) {
        mutableForm.update { it.copy(login = value.take(80)) }
    }

    fun passwordChanged(value: String) {
        mutableForm.update { it.copy(password = value.take(128)) }
    }

    fun signIn() {
        val input = mutableForm.value
        mutableForm.update { it.copy(password = "") }
        actions.run { repository.signIn(input.login, input.password) }
    }

    fun signOut() {
        mutableForm.value = LoginForm()
        actions.run { repository.signOut() }
    }
}
