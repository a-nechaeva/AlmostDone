package com.example.mobile_android.navigation

sealed class Screen(val route: String) {
    object Login : Screen("login")
    object Home : Screen("home")
    object Favorites : Screen("favorites")
    object Pantry : Screen("pantry")
    object Recommendations : Screen("recommendations")
    object Profile : Screen("profile")
    object RecipeDetail : Screen("recipe/{recipeId}") {
        fun route(recipeId: String) = "recipe/$recipeId"
    }
}