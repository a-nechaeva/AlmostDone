package com.example.mobile_android.navigation

import androidx.compose.runtime.Composable
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.example.mobile_android.ui.screens.FavoritesScreen
import com.example.mobile_android.ui.screens.HomeScreen
import com.example.mobile_android.ui.screens.LoginScreen
import com.example.mobile_android.ui.screens.PantryScreen
import com.example.mobile_android.ui.screens.ProfileScreen
import com.example.mobile_android.ui.screens.RecipeDetailScreen
import com.example.mobile_android.ui.screens.RecommendationsScreen
import com.example.mobile_android.viewmodel.FavoritesViewModel
import com.example.mobile_android.viewmodel.ProfileViewModel

@Composable
fun AppNavGraph(navController: NavHostController = rememberNavController()) {
    // Общие для всех экранов ViewModel (созданы на уровне Activity)
    val favoritesViewModel: FavoritesViewModel = viewModel()
    val profileViewModel: ProfileViewModel = viewModel()

    NavHost(navController = navController, startDestination = Screen.Login.route) {
        composable(Screen.Login.route) {
            LoginScreen(
                onSuccess = {
                    navController.navigate(Screen.Home.route) {
                        popUpTo(Screen.Login.route) { inclusive = true }
                    }
                }
            )
        }
        composable(Screen.Home.route) {
            HomeScreen(
                onRecipeClick = { navController.navigate(Screen.RecipeDetail.route(it)) },
                onTabSelect = { navController.navigateTab(it) },
            )
        }
        composable(Screen.Favorites.route) {
            FavoritesScreen(
                onRecipeClick = { navController.navigate(Screen.RecipeDetail.route(it)) },
                onTabSelect = { navController.navigateTab(it) },
                favoritesViewModel = favoritesViewModel,
            )
        }
        composable(Screen.Pantry.route) {
            PantryScreen(onTabSelect = { navController.navigateTab(it) })
        }
        composable(Screen.Recommendations.route) {
            RecommendationsScreen(onTabSelect = { navController.navigateTab(it) })
        }
        composable(Screen.Profile.route) {
            ProfileScreen(onTabSelect = { navController.navigateTab(it) }, profileViewModel = profileViewModel)
        }
        composable(Screen.RecipeDetail.route) { entry ->
            RecipeDetailScreen(
                recipeId = entry.arguments?.getString("recipeId").orEmpty(),
                onBack = { navController.popBackStack() },
                favoritesViewModel = favoritesViewModel,
            )
        }
    }
}

fun NavHostController.navigateTab(tab: MainTab) {
    navigate(tab.route) {
        popUpTo(Screen.Home.route) { saveState = true }
        launchSingleTop = true
        restoreState = true
    }
}