package com.example.mobile_android.data.model

data class Ingredient(
    val id: String,
    val name: String,
    val kcalPer100g: Double,
    val proteinPer100g: Double,
    val fatPer100g: Double,
    val carbPer100g: Double,
    val pricePer100g: Double, // для стоимости блюда и планов покупок
    val allergens: Set<String> = emptySet(),
)