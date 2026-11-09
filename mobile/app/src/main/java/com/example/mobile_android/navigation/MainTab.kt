package com.example.mobile_android.navigation

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.ShoppingCart
import androidx.compose.material.icons.filled.Star
import androidx.compose.ui.graphics.vector.ImageVector

enum class MainTab(val title: String, val icon: ImageVector, val route: String) {
    HOME("Рецепты", Icons.Filled.Home, Screen.Home.route),
    FAVORITES("Избранное", Icons.Filled.Favorite, Screen.Favorites.route),
    PANTRY("Продукты", Icons.Filled.ShoppingCart, Screen.Pantry.route),
    RECOMMENDATIONS("Рекомендации", Icons.Filled.Star, Screen.Recommendations.route),
    PROFILE("Профиль", Icons.Filled.Person, Screen.Profile.route),
}