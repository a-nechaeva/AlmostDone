package com.example.mobile_android.feature.profile.localwiring

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavController
import androidx.navigation.NavHostController
import androidx.navigation.compose.*
import com.example.mobile_android.data.DemoCatalog
import com.example.mobile_android.data.DemoCatalogRepository
import com.example.mobile_android.domain.*
import com.example.mobile_android.feature.common.ActionState
import com.example.mobile_android.feature.dishes.DishesViewModel
import com.example.mobile_android.feature.profile.ProfileScreen
import com.example.mobile_android.feature.profile.ProfileViewModel
import com.example.mobile_android.navigation.AppTab
import com.example.mobile_android.ui.components.BrandTopBar
import com.example.mobile_android.ui.components.LoadContent
import java.io.IOException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOf

@OptIn(ExperimentalCoroutinesApi::class)
internal class RecordingPreferences(private val delegate: PreferencesRepository) :
    PreferencesRepository by delegate {
    var attempts = 0
        private set
    var writes = 0
        private set
    var failNext = false
    var gate: CompletableDeferred<Unit>? = null
    var finishGate: CompletableDeferred<Unit>? = null
    val readFailure = MutableStateFlow(false)

    override val preferences = readFailure.flatMapLatest { failing ->
        if (failing) flow { throw IOException("Test read failure") } else delegate.preferences
    }

    override suspend fun update(transform: (FoodPreferences) -> FoodPreferences) {
        attempts++
        gate?.await()
        if (failNext) {
            failNext = false
            throw IOException("Test write failure")
        }
        delegate.update(transform)
        writes++
        finishGate?.await()
    }
}

@Composable
internal fun ProfileLocalWiringHost(
    repository: PreferencesRepository,
    nav: NavHostController,
    onEditorVisibilityChanged: (Boolean) -> Unit,
    logout: () -> Unit,
) {
    val currentEntry by nav.currentBackStackEntryAsState()
    var profileVisit by rememberSaveable { mutableIntStateOf(0) }
    DisposableEffect(nav) {
        var wasProfile = nav.currentDestination?.route == AppTab.PROFILE.route
        val listener = NavController.OnDestinationChangedListener { _, destination, _ ->
            val isProfile = destination.route == AppTab.PROFILE.route
            if (wasProfile && !isProfile) profileVisit++
            wasProfile = isProfile
        }
        nav.addOnDestinationChangedListener(listener)
        onDispose { nav.removeOnDestinationChangedListener(listener) }
    }
    val dishes: DishesViewModel = viewModel(
        factory = viewModelFactory {
            initializer {
                DishesViewModel(
                    DemoCatalogRepository(),
                    ReadOnlyHousehold,
                    repository,
                    SavedStateHandle(),
                    Dispatchers.Main.immediate,
                )
            }
        }
    )
    val results by dishes.state.collectAsStateWithLifecycle()

    NavHost(nav, startDestination = AppTab.PANTRY.route) {
        composable(AppTab.PANTRY.route) {
            TestTabScaffold(AppTab.PANTRY, nav) { Text("Продукты дома") }
        }
        composable(AppTab.DISHES.route) {
            TestTabScaffold(AppTab.DISHES, nav) {
                LoadContent(results, dishes::retry) { data ->
                    Column {
                        data.matches.forEach { match ->
                            Text("${match.recipe.title}: ${match.dietary.status}")
                        }
                    }
                }
            }
        }
        composable(AppTab.SHOPPING.route) {
            TestTabScaffold(AppTab.SHOPPING, nav) { Text("Список покупок") }
        }
        composable(AppTab.PROFILE.route) { entry ->
            val vm: ProfileViewModel = viewModel(
                factory = viewModelFactory { initializer { ProfileViewModel(repository) } }
            )
            val state by vm.state.collectAsStateWithLifecycle()
            val action by vm.actions.state.collectAsStateWithLifecycle()
            var editorVisible by remember { mutableStateOf(false) }
            val isRouteActive = currentEntry == entry
            val homeScrollState = rememberScrollState()
            TestTabScaffold(AppTab.PROFILE, nav, hideBars = isRouteActive && editorVisible) {
                key(profileVisit) {
                    LoadContent(state, vm::retry) { preferences ->
                        ProfileScreen(
                            preferences,
                            action,
                            ActionState(),
                            vm::foodType,
                            vm::allergen,
                            vm::gluten,
                            vm::lactose,
                            vm::diabetes,
                            vm::table,
                            { nav.navigate("favorites") },
                            logout,
                            vm.actions::dismiss,
                            {},
                            onSave = vm::save,
                            onMyProducts = { nav.navigateTestTab(AppTab.PANTRY) },
                            onEditorVisibilityChanged = {
                                editorVisible = it
                                onEditorVisibilityChanged(it)
                            },
                            isRouteActive = isRouteActive,
                            homeScrollState = homeScrollState,
                        )
                    }
                }
            }
        }
        composable("favorites") { Text("Избранное открыто") }
    }
}

internal fun NavHostController.navigateTestTab(tab: AppTab) {
    navigate(tab.route) {
        popUpTo(graph.findStartDestination().id) { saveState = true }
        launchSingleTop = true
        restoreState = true
    }
}

@Composable
private fun TestTabScaffold(
    selected: AppTab,
    nav: NavHostController,
    hideBars: Boolean = false,
    content: @Composable () -> Unit,
) {
    Scaffold(
        topBar = {
            if (!hideBars) {
                Box(Modifier.testTag("top-bar")) {
                    BrandTopBar(onFavorites = { nav.navigate("favorites") })
                }
            }
        },
        bottomBar = {
            if (!hideBars) {
                NavigationBar(Modifier.testTag("bottom-bar")) {
                    AppTab.entries.forEach { tab ->
                        NavigationBarItem(
                            selected = selected == tab,
                            onClick = { nav.navigateTestTab(tab) },
                            icon = { Icon(tab.icon, contentDescription = null) },
                            label = { Text(tab.label) },
                            modifier = Modifier.testTag(tab.route),
                        )
                    }
                }
            }
        },
        contentWindowInsets = WindowInsets.safeDrawing,
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding).consumeWindowInsets(padding)) { content() }
    }
}

private object ReadOnlyHousehold : HouseholdRepository {
    override val household = flowOf(Household(pantry = DemoCatalog.initialPantry))

    override suspend fun addPantry(id: String, quantity: Quantity?) = unexpectedWrite()
    override suspend fun setPantry(id: String, quantity: Quantity?) = unexpectedWrite()
    override suspend fun removePantry(id: String) = unexpectedWrite()
    override suspend fun toggleFavorite(id: String, ingredient: Boolean) = unexpectedWrite()
    override suspend fun planRecipe(id: String, servings: Int) = unexpectedWrite()
    override suspend fun removePlannedRecipe(id: String) = unexpectedWrite()
    override suspend fun addManualPurchase(id: String, quantity: Quantity) = unexpectedWrite()
    override suspend fun removeManualPurchase(id: String) = unexpectedWrite()
    override suspend fun toggleCheckedPurchase(id: String) = unexpectedWrite()
    override suspend fun addCheckedPurchasesToPantry() = unexpectedWrite()

    private fun unexpectedWrite(): Nothing = error("This host only reads the household")
}
