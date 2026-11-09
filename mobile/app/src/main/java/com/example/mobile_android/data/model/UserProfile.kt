package com.example.mobile_android.data.model

data class UserProfile(
    val login: String = "",
    val allergens: Set<String> = emptySet(),
    val diets: Set<DietTag> = emptySet(),
    val budget: Double = 5000.0,
    // TODO: стол по Познеру и прочие ограничения (требование 2)
)