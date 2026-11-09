package com.example.mobile_android.viewmodel

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel

class RecommendationsViewModel : ViewModel() {
    var result by mutableStateOf<String?>(null)
        private set

    fun computeBestPurchase(budget: Double) {
        // TODO: требование 6 — алгоритм лучшей одиночной покупки и плана под бюджет
        result = "Заглушка: здесь будет расчёт покупок под бюджет $budget ₽"
    }
}