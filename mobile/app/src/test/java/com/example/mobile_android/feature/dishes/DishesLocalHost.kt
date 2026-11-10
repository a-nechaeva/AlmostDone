package com.example.mobile_android.feature.dishes

import android.net.Uri
import androidx.compose.foundation.layout.*
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.lifecycle.createSavedStateHandle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.example.mobile_android.data.DemoCatalog
import com.example.mobile_android.domain.Catalog
import com.example.mobile_android.domain.CatalogRepository
import com.example.mobile_android.feature.FakeHousehold
import com.example.mobile_android.feature.FakePreferences
import com.example.mobile_android.ui.components.BrandTopBar
import com.example.mobile_android.ui.theme.AlmostReadyTheme
import java.io.IOException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.emitAll
import kotlinx.coroutines.flow.flow

internal class DishesHostCatalog(ready: Boolean = true) : CatalogRepository {
    val values = MutableSharedFlow<Catalog>(replay = 1)
    var failRead = false

    init {
        if (ready) values.tryEmit(DemoCatalog.catalog)
    }

    override val catalog = flow {
        if (failRead) throw IOException("test catalog unavailable")
        emitAll(values)
    }
}

@Composable
internal fun DishesLocalHost(
    catalog: DishesHostCatalog,
    preferences: FakePreferences,
    fontScale: Float = 1f,
    computation: CoroutineDispatcher = Dispatchers.Default,
) {
    val nav = rememberNavController()
    val household = remember { FakeHousehold() }
    val factory =
        remember(catalog, preferences, household, computation) {
            viewModelFactory {
                initializer {
                    DishesViewModel(
                        catalog,
                        household,
                        preferences,
                        createSavedStateHandle(),
                        computation,
                    )
                }
            }
        }

    CompositionLocalProvider(LocalDensity provides Density(2f, fontScale)) {
        AlmostReadyTheme {
            Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                NavHost(nav, startDestination = "dishes") {
                    composable("dishes") { entry ->
                        val model: DishesViewModel =
                            viewModel(viewModelStoreOwner = entry, factory = factory)
                        Column {
                            BrandTopBar(onFavorites = {})
                            DishesContent(
                                model,
                                false,
                                { nav.navigate("recipe/${Uri.encode(it)}") },
                                { nav.navigate("hidden") },
                                { nav.navigate("pantry") },
                            )
                        }
                    }
                    composable("hidden") { entry ->
                        val owner = remember(entry) { nav.getBackStackEntry("dishes") }
                        val model: DishesViewModel =
                            viewModel(viewModelStoreOwner = owner, factory = factory)
                        Column {
                            BrandTopBar("Скрытые блюда", onBack = { nav.popBackStack() })
                            DishesContent(
                                model,
                                true,
                                { nav.navigate("recipe/${Uri.encode(it)}") },
                                { nav.navigate("hidden") },
                                { nav.navigate("pantry") },
                            )
                        }
                    }
                    composable("recipe/{recipeId}") {
                        Text("Рецепт ${it.arguments?.getString("recipeId")}")
                    }
                    composable("pantry") { Text("Продукты") }
                }
            }
        }
    }
}
