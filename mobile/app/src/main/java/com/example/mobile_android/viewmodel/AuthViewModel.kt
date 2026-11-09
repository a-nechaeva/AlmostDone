package com.example.mobile_android.viewmodel

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import com.example.mobile_android.data.repository.AuthRepository

class AuthViewModel : ViewModel() {
    var login by mutableStateOf("")
        private set
    var password by mutableStateOf("")
        private set
    var error by mutableStateOf<String?>(null)
        private set

    fun onLoginChange(value: String) { login = value }
    fun onPasswordChange(value: String) { password = value }

    fun submit(onSuccess: () -> Unit) {
        AuthRepository.login(login, password)
            .onSuccess { onSuccess() }
            .onFailure { error = it.message }
    }
}