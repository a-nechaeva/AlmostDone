package com.example.mobile_android.feature.recipe.localwiring

import android.net.Uri
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
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
import com.example.mobile_android.domain.CatalogRepository
import com.example.mobile_android.feature.common.ScreenState
import com.example.mobile_android.feature.recipe.RecipeFavoriteButton
import com.example.mobile_android.feature.recipe.RecipeScreen
import com.example.mobile_android.feature.recipe.RecipeUiHousehold
import com.example.mobile_android.feature.recipe.RecipeUiPreferences
import com.example.mobile_android.feature.recipe.RecipeViewModel
import com.example.mobile_android.ui.components.LoadContent

internal const val RECIPE_ID = "cheese"
internal const val RECIPE_TOP_BAR = "recipe-local-wiring-top-bar"
internal const val SOURCE_DRAFT = "recipe-local-wiring-source-draft"

internal enum class RecipeSource(val route: String, val title: String, val draftLabel: String) {
    Dishes("dishes", "Подбор", "Поиск"),
    Graph("graph", "Граф", "Фильтр графа"),
    Favorites("favorites", "Избранное", "Поиск в избранном"),
    Shopping("shopping", "Покупки", "Заметка к покупкам"),
    Budget("budget", "План под бюджет", "Бюджет"),
}

@Composable
internal fun RecipeLocalWiringHost(
    household: RecipeUiHousehold,
    catalog: CatalogRepository,
    startSource: RecipeSource? = null,
    recipeId: String = RECIPE_ID,
) {
    val nav = rememberNavController()
    val preferences = remember { RecipeUiPreferences() }
    NavHost(nav, startDestination = startSource?.route ?: "sources") {
        composable("sources") {
            Column {
                RecipeSource.entries.forEach { source ->
                    Button(onClick = { nav.navigate(source.route) }) { Text(source.title) }
                }
            }
        }
        RecipeSource.entries.forEach { source ->
            composable(source.route) {
                val home by household.values.collectAsStateWithLifecycle()
                var draft by rememberSaveable { mutableStateOf("") }
                Column {
                    Text(source.title)
                    OutlinedTextField(
                        value = draft,
                        onValueChange = { draft = it },
                        label = { Text(source.draftLabel) },
                        modifier = Modifier.testTag(SOURCE_DRAFT),
                    )
                    if (source == RecipeSource.Favorites && RECIPE_ID in home.favoriteRecipes) {
                        Text("Рецепт сохранён")
                    }
                    if (source == RecipeSource.Shopping) {
                        home.plan.forEach { Text("Порции в покупках: ${it.servings}") }
                    }
                    Button(onClick = { nav.navigate("recipe/${Uri.encode(recipeId)}") }) {
                        Text("Открыть рецепт")
                    }
                }
            }
        }
        composable(
            "recipe/{recipeId}",
            arguments = listOf(navArgument("recipeId") { type = NavType.StringType }),
        ) { entry ->
            val vm: RecipeViewModel = viewModel(
                viewModelStoreOwner = entry,
                factory = viewModelFactory {
                    initializer { RecipeViewModel(catalog, household, preferences, createSavedStateHandle()) }
                },
            )
            val state by vm.state.collectAsStateWithLifecycle()
            val action by vm.actions.state.collectAsStateWithLifecycle()
            Scaffold(
                topBar = {
                    TopAppBar(
                        modifier = Modifier.testTag(RECIPE_TOP_BAR),
                        title = { Text("Рецепт", fontWeight = FontWeight.Bold) },
                        navigationIcon = {
                            IconButton(onClick = { nav.popBackStack() }) {
                                Icon(Icons.AutoMirrored.Filled.ArrowBack, "Назад")
                            }
                        },
                        actions = {
                            (state as? ScreenState.Ready)?.let {
                                RecipeFavoriteButton(it.data, action, vm::favorite)
                            }
                        },
                        colors = TopAppBarDefaults.topAppBarColors(
                            containerColor = MaterialTheme.colorScheme.background,
                        ),
                    )
                },
                contentWindowInsets = WindowInsets.safeDrawing,
            ) { padding ->
                Box(Modifier.fillMaxSize().padding(padding).consumeWindowInsets(padding)) {
                    LoadContent(state, vm::retry) {
                        RecipeScreen(
                            state = it,
                            action = action,
                            servings = vm::servingsChanged,
                            favorite = vm::favorite,
                            addToShopping = vm::addToShopping,
                            shopping = {
                                if (!nav.popBackStack(RecipeSource.Shopping.route, inclusive = false)) {
                                    nav.navigate(RecipeSource.Shopping.route) {
                                        popUpTo(entry.destination.id) { inclusive = true }
                                    }
                                }
                            },
                            dismiss = vm.actions::dismiss,
                            showFavoriteInCard = false,
                        )
                    }
                }
            }
        }
    }
}
