package com.example.mobile_android.navigation

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.createSavedStateHandle
import androidx.lifecycle.viewmodel.CreationExtras
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import androidx.navigation.*
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.*
import com.example.mobile_android.R
import com.example.mobile_android.app.AppDependencies
import com.example.mobile_android.feature.auth.*
import com.example.mobile_android.feature.common.*
import com.example.mobile_android.feature.dishes.*
import com.example.mobile_android.feature.favorites.*
import com.example.mobile_android.feature.pantry.*
import com.example.mobile_android.feature.profile.*
import com.example.mobile_android.feature.recipe.*
import com.example.mobile_android.feature.recognition.RecognitionRoute
import com.example.mobile_android.feature.recognition.RecognitionViewModel
import com.example.mobile_android.feature.shopping.*
import com.example.mobile_android.ui.components.*
import com.yandex.authsdk.YandexAuthLoginOptions
import com.yandex.authsdk.YandexAuthResult

enum class AppTab(val route: String, val label: String, val icon: ImageVector) {
    PANTRY("pantry", "Продукты", Icons.Outlined.Kitchen),
    DISHES("dishes", "Блюда", Icons.Outlined.Restaurant),
    SHOPPING("shopping", "Покупки", Icons.Outlined.ShoppingBag),
    PROFILE("profile", "Профиль", Icons.Outlined.Person),
}

@Composable
private inline fun <reified T : ViewModel> injectedViewModel(
    crossinline create: CreationExtras.() -> T
): T {
    val factory = remember { viewModelFactory { initializer { create() } } }
    return viewModel(factory = factory)
}

@Composable
fun AppRoot(container: AppDependencies) {
    val session: SessionViewModel = injectedViewModel { SessionViewModel(container.session) }
    val state by session.state.collectAsStateWithLifecycle()
    val form by session.form.collectAsStateWithLifecycle()
    val action by session.actions.state.collectAsStateWithLifecycle()
    val yandexLauncher =
        rememberLauncherForActivityResult(container.yandexAuth.contract) { result ->
            when (result) {
                is YandexAuthResult.Success -> session.signInWithYandex(result.token.value)
                is YandexAuthResult.Failure -> session.yandexAuthFailed()
                YandexAuthResult.Cancelled -> Unit
            }
        }
    LoadContent(state, session::retry) { signedIn ->
        if (!signedIn)
            LoginScreen(
                form,
                action,
                session::loginChanged,
                session::passwordChanged,
                session::signIn,
                { yandexLauncher.launch(YandexAuthLoginOptions()) },
                session.actions::dismiss,
            )
        else ApplicationNavigation(container, session::signOut, action, session.actions::dismiss)
    }
}

@Composable
private fun ApplicationNavigation(
    c: AppDependencies,
    logout: () -> Unit,
    sessionAction: ActionState,
    dismissSession: () -> Unit,
) {
    val nav = rememberNavController()
    NavHost(nav, startDestination = AppTab.PANTRY.route) {
        composable(AppTab.PANTRY.route) {
            val vm: PantryViewModel = injectedViewModel {
                PantryViewModel(c.catalog, c.household, createSavedStateHandle())
            }
            val state by vm.state.collectAsStateWithLifecycle()
            val action by vm.actions.state.collectAsStateWithLifecycle()
            val deleted by vm.deleted.collectAsStateWithLifecycle()
            FeatureScaffold(AppTab.PANTRY, nav) {
                LoadContent(state, vm::retry) {
                    PantryScreen(
                        it,
                        action,
                        deleted,
                        vm::queryChanged,
                        vm::add,
                        vm::edit,
                        vm::remove,
                        vm::undoDelete,
                        vm::favorite,
                        vm.actions::dismiss,
                        { nav.navigateTab(AppTab.DISHES) },
                        { nav.navigate("receipt") },
                    )
                }
            }
        }
        composable(AppTab.DISHES.route) { DishesRoute(c, nav, false) }
        composable("hidden") { DishesRoute(c, nav, true) }
        composable(AppTab.SHOPPING.route) {
            val vm: ShoppingViewModel = injectedViewModel {
                ShoppingViewModel(c.catalog, c.household, c.preferences, createSavedStateHandle())
            }
            val state by vm.state.collectAsStateWithLifecycle()
            val action by vm.actions.state.collectAsStateWithLifecycle()
            FeatureScaffold(AppTab.SHOPPING, nav) {
                LoadContent(state, vm::retry) {
                    ShoppingScreen(
                        it,
                        action,
                        vm::budgetChanged,
                        vm::toggleChecked,
                        vm::removeRecipe,
                        vm::removeManual,
                        vm::addBoughtToPantry,
                        vm::addSuggestion,
                        { nav.navigateTab(AppTab.DISHES) },
                        vm.actions::dismiss,
                    )
                }
            }
        }
        composable(AppTab.PROFILE.route) {
            val vm: ProfileViewModel = injectedViewModel { ProfileViewModel(c.preferences) }
            val state by vm.state.collectAsStateWithLifecycle()
            val action by vm.actions.state.collectAsStateWithLifecycle()
            FeatureScaffold(AppTab.PROFILE, nav) {
                LoadContent(state, vm::retry) {
                    ProfileScreen(
                        it,
                        action,
                        sessionAction,
                        vm::foodType,
                        vm::allergen,
                        vm::gluten,
                        vm::lactose,
                        vm::diabetes,
                        vm::table,
                        { nav.navigate("favorites") },
                        logout,
                        vm.actions::dismiss,
                        dismissSession,
                    )
                }
            }
        }
        composable(
            "recipe/{recipeId}",
            arguments = listOf(navArgument("recipeId") { type = NavType.StringType }),
        ) {
            val vm: RecipeViewModel = injectedViewModel {
                RecipeViewModel(c.catalog, c.household, c.preferences, createSavedStateHandle())
            }
            val state by vm.state.collectAsStateWithLifecycle()
            val action by vm.actions.state.collectAsStateWithLifecycle()
            FeatureScaffold(null, nav, "Рецепт") {
                LoadContent(state, vm::retry) {
                    RecipeScreen(
                        it,
                        action,
                        vm::servingsChanged,
                        vm::favorite,
                        vm::addToShopping,
                        { nav.navigateTab(AppTab.SHOPPING) },
                        vm.actions::dismiss,
                    )
                }
            }
        }
        composable("favorites") {
            val vm: FavoritesViewModel = injectedViewModel {
                FavoritesViewModel(c.catalog, c.household, c.preferences)
            }
            val state by vm.state.collectAsStateWithLifecycle()
            val action by vm.actions.state.collectAsStateWithLifecycle()
            FeatureScaffold(null, nav, "Избранное") {
                LoadContent(state, vm::retry) {
                    FavoritesScreen(
                        it,
                        action,
                        vm::favorite,
                        { id -> nav.navigate("recipe/${Uri.encode(id)}") },
                        vm.actions::dismiss,
                    )
                }
            }
        }
        composable("receipt") { ReceiptRoute(c, nav) }
    }
}

@Composable
private fun DishesRoute(c: AppDependencies, nav: NavHostController, hidden: Boolean) {
    val vm: DishesViewModel = injectedViewModel {
        DishesViewModel(c.catalog, c.household, c.preferences, createSavedStateHandle())
    }
    val state by vm.state.collectAsStateWithLifecycle()
    val action by vm.actions.state.collectAsStateWithLifecycle()
    val queryText by vm.query.collectAsStateWithLifecycle()
    FeatureScaffold(if (hidden) null else AppTab.DISHES, nav, "Скрытые блюда") {
        val selectedView by vm.view.collectAsStateWithLifecycle()
        val view = DishesView.valueOf(selectedView)
        Column {
            if (!hidden && state !is ScreenState.Ready)
                Box(Modifier.padding(20.dp)) { DishesViewSelector(view, vm::viewChanged) }
            Box(Modifier.weight(1f)) {
                LoadContent(state, vm::retry) {
                    DishesScreen(
                        it,
                        action,
                        hidden,
                        vm::queryChanged,
                        vm::availabilityChanged,
                        vm::maxMinutesChanged,
                        vm::maxKcalChanged,
                        vm::methodChanged,
                        vm::resetFilters,
                        vm::favorite,
                        { id -> nav.navigate("recipe/${Uri.encode(id)}") },
                        { nav.navigate("hidden") },
                        { nav.navigateTab(AppTab.PANTRY) },
                        vm.actions::dismiss,
                        view,
                        vm::viewChanged,
                        vm::addPurchase,
                        queryText = queryText,
                    )
                }
            }
        }
    }
}

private fun NavHostController.navigateTab(tab: AppTab) {
    navigate(tab.route) {
        popUpTo(graph.findStartDestination().id) { saveState = true }
        launchSingleTop = true
        restoreState = true
    }
}

@Composable
private fun FeatureScaffold(
    tab: AppTab?,
    nav: NavHostController,
    title: String = "",
    content: @Composable () -> Unit,
) {
    Scaffold(
        topBar = {
            if (tab == null) BrandTopBar(title, onBack = { nav.popBackStack() })
            else BrandTopBar(onFavorites = { nav.navigate("favorites") })
        },
        bottomBar = { if (tab != null) FloatingNavigation(tab) { nav.navigateTab(it) } },
        contentWindowInsets = WindowInsets.safeDrawing,
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding).consumeWindowInsets(padding)) { content() }
    }
}

@Composable
private fun FloatingNavigation(selected: AppTab, onSelect: (AppTab) -> Unit) {
    Surface(
        Modifier.padding(horizontal = 20.dp, vertical = 8.dp).navigationBarsPadding(),
        shape = RoundedCornerShape(28.dp),
        color = MaterialTheme.colorScheme.surface,
        shadowElevation = 6.dp,
    ) {
        Row(Modifier.fillMaxWidth()) {
            AppTab.entries.forEach { tab ->
                val active = tab == selected
                Column(
                    Modifier.weight(1f)
                        .heightIn(min = 64.dp)
                        .selectable(active, role = Role.Tab, onClick = { onSelect(tab) })
                        .padding(vertical = 6.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(2.dp),
                ) {
                    Surface(
                        shape = RoundedCornerShape(20.dp),
                        color =
                            if (active) MaterialTheme.colorScheme.primaryContainer
                            else MaterialTheme.colorScheme.surface,
                    ) {
                        if (tab == AppTab.DISHES)
                            Icon(
                                painterResource(R.drawable.ic_bowl),
                                null,
                                Modifier.padding(horizontal = 14.dp, vertical = 2.dp).size(24.dp),
                                tint =
                                    if (active) MaterialTheme.colorScheme.primary
                                    else MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        else
                            Icon(
                                tab.icon,
                                null,
                                Modifier.padding(horizontal = 14.dp, vertical = 2.dp).size(24.dp),
                                tint =
                                    if (active) MaterialTheme.colorScheme.primary
                                    else MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                    }
                    Text(
                        tab.label,
                        style = MaterialTheme.typography.labelSmall,
                        color =
                            if (active) MaterialTheme.colorScheme.primary
                            else MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(horizontal = 2.dp),
                    )
                }
            }
        }
    }
}

@Composable
private fun ReceiptRoute(c: AppDependencies, nav: NavHostController) {
    val server = c.server
    if (server != null) {
        val vm: RecognitionViewModel = injectedViewModel { RecognitionViewModel(server, c.household) }
        FeatureScaffold(null, nav, "Фото чека") { RecognitionRoute(vm) { nav.popBackStack() } }
    } else {
        FeatureScaffold(null, nav, "Фото чека") {
            EmptyPanel(
                "Распознавание пока недоступно",
                "В демонстрационном режиме добавьте нужные позиции вручную.",
                "Добавить вручную",
                { nav.popBackStack() },
            )
        }
    }
}
