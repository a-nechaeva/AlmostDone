package com.example.mobile_android.data.model

data class RecipeIngredient(
    val ingredientId: String,
    val grams: Double,
)

data class Recipe(
    val id: String,
    val title: String,
    val ingredients: List<RecipeIngredient>,
    val steps: List<String>,
    val timeMinutes: Int,
    val portions: Int,
    val tags: Set<DietTag> = emptySet(),
    val methods: Set<CookingMethod> = emptySet(),
    val warnings: List<String> = emptyList(), // «скрытая плашка»: что нежелательно
)

data class RecipeMetrics(
    val cost: Double,
    val kcal: Double,
    val protein: Double,
    val fat: Double,
    val carb: Double,
    val allergens: Set<String>,
)