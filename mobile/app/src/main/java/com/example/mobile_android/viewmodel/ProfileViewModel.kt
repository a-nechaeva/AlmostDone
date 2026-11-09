package com.example.mobile_android.viewmodel

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import com.example.mobile_android.data.model.DietTag
import com.example.mobile_android.data.model.UserProfile

class ProfileViewModel : ViewModel() {
    var profile by mutableStateOf(UserProfile())
        private set

    fun toggleAllergen(allergen: String) {
        val set = profile.allergens
        profile = profile.copy(allergens = if (allergen in set) set - allergen else set + allergen)
    }

    fun toggleDiet(diet: DietTag) {
        val set = profile.diets
        profile = profile.copy(diets = if (diet in set) set - diet else set + diet)
    }
}