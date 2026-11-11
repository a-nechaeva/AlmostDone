package com.example.mobile_android.feature.favorites.localwiring

import android.net.Uri
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.createSavedStateHandle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.example.mobile_android.feature.favorites.FavoritesRoute
import com.example.mobile_android.feature.favorites.FavoritesViewModel
import com.example.mobile_android.feature.recipe.RecipeScreen
import com.example.mobile_android.feature.recipe.RecipeViewModel
import com.example.mobile_android.ui.components.BrandTopBar
import com.example.mobile_android.ui.components.LoadContent
import com.example.mobile_android.ui.theme.AlmostReadyTheme

@Composable
internal fun FavoritesLocalWiringHost(fixture: FavoritesLocalWiringFixture) {
    CompositionLocalProvider(LocalDensity provides Density(2f, 1f)) {
        AlmostReadyTheme {
            val nav = rememberNavController()
            NavHost(nav, startDestination = "favorites") {
                composable("favorites") {
                    val factory = remember {
                        viewModelFactory {
                            initializer {
                                FavoritesViewModel(fixture.catalog, fixture.household, fixture.preferences)
                            }
                        }
                    }
                    val favorites: FavoritesViewModel = viewModel(factory = factory)
                    LocalWiringScaffold("Избранное", onBack = { nav.popBackStack() }) {
                        FavoritesRoute(favorites) { id -> nav.navigate("recipe/${Uri.encode(id)}") }
                    }
                }
                composable(
                    "recipe/{recipeId}",
                    arguments = listOf(navArgument("recipeId") { type = NavType.StringType }),
                ) {
                    val factory = remember {
                        viewModelFactory {
                            initializer {
                                RecipeViewModel(
                                    fixture.catalog, fixture.household, fixture.preferences,
                                    createSavedStateHandle(),
                                )
                            }
                        }
                    }
                    val recipe: RecipeViewModel = viewModel(factory = factory)
                    val state by recipe.state.collectAsStateWithLifecycle()
                    val action by recipe.actions.state.collectAsStateWithLifecycle()
                    LocalWiringScaffold("Рецепт", onBack = { nav.popBackStack() }) {
                        LoadContent(state, recipe::retry) {
                            RecipeScreen(
                                it, action, recipe::servingsChanged, recipe::favorite,
                                recipe::addToShopping, {}, recipe.actions::dismiss,
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun LocalWiringScaffold(title: String, onBack: () -> Unit, content: @Composable () -> Unit) {
    Scaffold(topBar = { BrandTopBar(title, onBack = onBack) }) { padding ->
        Box(Modifier.fillMaxSize().padding(padding).consumeWindowInsets(padding)) { content() }
    }
}
