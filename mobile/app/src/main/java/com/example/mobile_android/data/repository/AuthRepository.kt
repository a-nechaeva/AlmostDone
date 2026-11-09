package com.example.mobile_android.data.repository

object AuthRepository {
    // Заглушка (требование 1): позже заменить на реальную проверку
    fun login(login: String, password: String): Result<Unit> = when {
        login.isBlank() -> Result.failure(Exception("Введите логин"))
        password.length < 4 -> Result.failure(Exception("Пароль минимум 4 символа"))
        else -> Result.success(Unit)
    }
}