package com.example.mobile_android.navigation

import android.content.ActivityNotFoundException
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelStoreOwner
import androidx.lifecycle.viewmodel.compose.LocalViewModelStoreOwner
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
import com.example.mobile_android.app.AppContainer
import com.example.mobile_android.app.AppDependencies
import com.example.mobile_android.app.LocalFeatureDependencies
import com.example.mobile_android.feature.auth.*
import com.example.mobile_android.feature.common.*
import com.example.mobile_android.feature.dishes.*
import com.example.mobile_android.feature.favorites.*
import com.example.mobile_android.feature.pantry.*
import com.example.mobile_android.feature.profile.*
import com.example.mobile_android.feature.receipt.ReceiptRoute
import com.example.mobile_android.feature.recipe.*
import com.example.mobile_android.feature.shopping.*
import com.example.mobile_android.ui.components.*
import com.example.mobile_android.data.DemoCatalog

enum class AppTab(val route: String, val label: String, val icon: ImageVector) {
    PANTRY("pantry", "Продукты", Icons.Outlined.Kitchen),
    DISHES("dishes", "Блюда", Icons.Outlined.Restaurant),
    SHOPPING("shopping", "Покупки", Icons.Outlined.ShoppingBag),
    PROFILE("profile", "Профиль", Icons.Outlined.Person),
}

@Composable
private inline fun <reified T : ViewModel> injectedViewModel(
    owner: ViewModelStoreOwner = checkNotNull(LocalViewModelStoreOwner.current),
    crossinline create: CreationExtras.() -> T
): T {
    val factory = remember { viewModelFactory { initializer { create() } } }
    return viewModel(viewModelStoreOwner = owner, factory = factory)
}

@Composable
fun AppRoot(container: AppDependencies) {
    val session: SessionViewModel = injectedViewModel { SessionViewModel(container.session) }
    val state by session.state.collectAsStateWithLifecycle()
    val action by session.actions.state.collectAsStateWithLifecycle()
    var yandexPending by rememberSaveable { mutableStateOf(false) }
    val yandexLauncher = rememberLauncherForActivityResult(container.yandexLogin) { result ->
        yandexPending = false
        when (result) {
            is YandexLoginResult.Success -> session.signInWithYandex(result.token)
            YandexLoginResult.Failure -> session.yandexAuthFailed()
            YandexLoginResult.Cancelled -> Unit
        }
    }
    val navigationState = rememberSaveableStateHolder()
    var previousSession by rememberSaveable { mutableStateOf<String?>(null) }
    if (state is ScreenState.Error) {
        Box(Modifier.safeDrawingPadding()) { LoadContent(state, session::retry) {} }
        return
    }
    LoadContent(state, session::retry) { sessionKey ->
        LaunchedEffect(sessionKey) {
            if (previousSession != sessionKey) {
                previousSession?.let(navigationState::removeState)
                previousSession = sessionKey
            }
        }
        if (sessionKey != null) {
            navigationState.SaveableStateProvider(sessionKey) {
                ApplicationNavigation(
                    featureDependencies(container, sessionKey),
                    session::signOut,
                    action,
                    session.actions::dismiss,
                )
            }
        } else {
            LoginScreen(action, yandexPending, yandexSignIn = {
                yandexPending = true
                session.actions.dismiss()
                try {
                    yandexLauncher.launch(Unit)
                } catch (_: ActivityNotFoundException) {
                    yandexPending = false
                    session.yandexAuthFailed()
                }
            }, dismiss = session.actions::dismiss)
        }
    }
}

/**
 * Зависимости экранов: настоящее приложение получает изолированные данные текущей сессии,
 * тестовые host'ы передают свои [LocalFeatureDependencies] напрямую.
 */
private fun featureDependencies(container: AppDependencies, sessionKey: String): LocalFeatureDependencies? =
    (container as? AppContainer)?.sessionFeatures(sessionKey)
        ?: container as? LocalFeatureDependencies

@Composable
private fun ApplicationNavigation(
    c: LocalFeatureDependencies?,
    logout: () -> Unit,
    sessionAction: ActionState,
    dismissSession: () -> Unit,
) {
    val nav = rememberNavController()
    // Подписи «Демо» — только пока экраны работают на встроенном каталоге (сервер недоступен).
    val catalog = remember(c) { c?.catalog?.catalog }?.collectAsStateWithLifecycle(null)?.value
    CompositionLocalProvider(LocalDemoData provides (catalog == null || catalog === DemoCatalog.catalog)) {
    NavHost(nav, startDestination = AppTab.PANTRY.route) {
        composable(AppTab.PANTRY.route) {
            if (c == null) {
                FeatureScaffold(AppTab.PANTRY, nav) {
                    UnavailableFeature("Мои продукты", "Каталог и запасы ещё подключаются.") {
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            SearchField("", {}, "Добавить продукт", Modifier.weight(1f), enabled = false)
                            FilledTonalIconButton(onClick = { nav.navigate("receipt") }) {
                                Icon(Icons.Outlined.PhotoCamera, "Добавить по фото чека")
                            }
                        }
                        TextButton(onClick = { nav.navigateTab(AppTab.DISHES) }) { Text("Подобрать блюда") }
                    }
                }
                return@composable
            }
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
        composable(AppTab.DISHES.route) { entry ->
            if (c == null) {
                var view by rememberSaveable { mutableStateOf(DishesView.LIST) }
                FeatureScaffold(AppTab.DISHES, nav) {
                    val graph = view == DishesView.GRAPH
                    val title = if (graph) "Больше блюд с одной покупкой" else "Что приготовим?"
                    val message = if (graph) "Граф покупок ещё подключается." else "Подбор блюд ещё подключается."
                    UnavailableFeature(title, message) {
                        if (graph) {
                            DishesViewSelector(view) { view = it }
                            TextButton(onClick = { nav.navigateTab(AppTab.PANTRY) }) {
                                Text("Изменить продукты дома")
                            }
                        } else DishesListViewSelector(view) { view = it }
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            SearchField("", {}, "Найти блюдо", Modifier.weight(1f), enabled = false)
                            IconButton(onClick = {}, enabled = false) {
                                Icon(Icons.Outlined.Tune, "Открыть фильтры")
                            }
                        }
                        TextButton(onClick = { nav.navigate("hidden") }) { Text("Скрытые блюда") }
                    }
                }
            } else DishesRoute(c, nav, entry, hidden = false)
        }
        composable("hidden") { entry ->
            if (c == null) {
                FeatureScaffold(null, nav, "Скрытые блюда") {
                    UnavailableFeature("Почему блюда скрыты", "Подбор блюд ещё подключается.")
                }
            } else {
                val dishes = remember(entry) { nav.getBackStackEntry(AppTab.DISHES.route) }
                DishesRoute(c, nav, dishes, hidden = true)
            }
        }
        composable(AppTab.SHOPPING.route) { entry ->
            if (c == null) {
                FeatureScaffold(AppTab.SHOPPING, nav) {
                    UnavailableFeature("Что докупить", "Покупки и план под бюджет ещё подключаются.") {
                        PrimaryButton({}, Modifier.fillMaxWidth(), enabled = false) { Text("Подобрать покупки") }
                        TextButton(onClick = { nav.navigateTab(AppTab.DISHES) }) { Text("Выбрать блюда") }
                    }
                }
                return@composable
            }
            val vm: ShoppingViewModel = injectedViewModel {
                ShoppingViewModel(
                    c.catalog,
                    c.household,
                    c.preferences,
                    createSavedStateHandle(),
                    c.suggestionSource ?: FakeShoppingSuggestionSource(),
                )
            }
            val state by vm.state.collectAsStateWithLifecycle()
            val action by vm.actions.state.collectAsStateWithLifecycle()
            val currentEntry by nav.currentBackStackEntryAsState()
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
                        openRecipe = { id -> nav.navigate("recipe/${Uri.encode(id)}") },
                        openPantry = { nav.navigateTab(AppTab.PANTRY) },
                        budgetPlanWriter = c.budgetPlanWriter,
                        budgetSource = c.budgetSource,
                        isRouteActive = currentEntry == entry,
                    )
                }
            }
        }
        composable(AppTab.PROFILE.route) { entry ->
            if (c == null) {
                FeatureScaffold(AppTab.PROFILE, nav) {
                    ProfileContent(
                        preferences = null,
                        action = ActionState(),
                        logoutAction = sessionAction,
                        favorites = { nav.navigate("favorites") },
                        logout = logout,
                        dismiss = {},
                        dismissLogout = dismissSession,
                        onSave = null,
                        onMyProducts = { nav.navigateTab(AppTab.PANTRY) },
                    )
                }
                return@composable
            }
            val vm: ProfileViewModel = injectedViewModel { ProfileViewModel(c.preferences) }
            val state by vm.state.collectAsStateWithLifecycle()
            val action by vm.actions.state.collectAsStateWithLifecycle()
            val currentEntry by nav.currentBackStackEntryAsState()
            var editorVisible by remember { mutableStateOf(false) }
            val isRouteActive = currentEntry == entry
            FeatureScaffold(AppTab.PROFILE, nav, hideBars = isRouteActive && editorVisible) {
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
                        onSave = vm::save,
                        onMyProducts = { nav.navigateTab(AppTab.PANTRY) },
                        onEditorVisibilityChanged = { editorVisible = it },
                        isRouteActive = isRouteActive,
                    )
                }
            }
        }
        composable(
            "recipe/{recipeId}",
            arguments = listOf(navArgument("recipeId") { type = NavType.StringType }),
        ) {
            if (c == null) {
                FeatureScaffold(null, nav, "Рецепт") {
                    UnavailableFeature("Состав и приготовление", "Рецепты и фотографии ещё подключаются.")
                }
                return@composable
            }
            val vm: RecipeViewModel = injectedViewModel {
                RecipeViewModel(c.catalog, c.household, c.preferences, createSavedStateHandle())
            }
            val state by vm.state.collectAsStateWithLifecycle()
            val action by vm.actions.state.collectAsStateWithLifecycle()
            FeatureScaffold(
                null,
                nav,
                "Рецепт",
                topBarActions = {
                    (state as? ScreenState.Ready)?.let { RecipeFavoriteButton(it.data, action, vm::favorite) }
                },
            ) {
                LoadContent(state, vm::retry) {
                    RecipeScreen(
                        it,
                        action,
                        vm::servingsChanged,
                        vm::favorite,
                        vm::addToShopping,
                        { nav.navigateTab(AppTab.SHOPPING) },
                        vm.actions::dismiss,
                        showFavoriteInCard = false,
                    )
                }
            }
        }
        composable("favorites") {
            if (c == null) {
                FeatureScaffold(null, nav, "Избранное") {
                    var ingredients by rememberSaveable { mutableStateOf(false) }
                    UnavailableFeature("Избранное", "Блюда и ингредиенты ещё подключаются.") {
                        FavoritesTabs(ingredients) { ingredients = it }
                    }
                }
                return@composable
            }
            val vm: FavoritesViewModel = injectedViewModel {
                FavoritesViewModel(c.catalog, c.household, c.preferences)
            }
            FeatureScaffold(null, nav, "Избранное") {
                FavoritesRoute(vm) { id -> nav.navigate("recipe/${Uri.encode(id)}") }
            }
        }
        composable("receipt") { ReceiptRoute(c) { nav.popBackStack() } }
    }
    }
}

@Composable
private fun UnavailableFeature(
    title: String,
    message: String,
    content: @Composable ColumnScope.() -> Unit = {},
) {
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        PageHeading(title)
        EmptyPanel("Пока недоступно", message)
        content()
    }
}

@Composable
private fun DishesRoute(
    c: LocalFeatureDependencies,
    nav: NavHostController,
    owner: NavBackStackEntry,
    hidden: Boolean,
) {
    val vm: DishesViewModel = injectedViewModel(owner) {
        DishesViewModel(c.catalog, c.household, c.preferences, createSavedStateHandle())
    }
    FeatureScaffold(if (hidden) null else AppTab.DISHES, nav, "Скрытые блюда") {
        DishesContent(
            model = vm,
            showHidden = hidden,
            openRecipe = { id -> nav.navigate("recipe/${Uri.encode(id)}") },
            openHidden = { nav.navigate("hidden") },
            openPantry = { nav.navigateTab(AppTab.PANTRY) },
        )
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
    hideBars: Boolean = false,
    topBarActions: @Composable RowScope.() -> Unit = {},
    content: @Composable () -> Unit,
) {
    Scaffold(
        topBar = {
            if (!hideBars) {
                if (tab == null) {
                    BrandTopBar(title, onBack = { nav.popBackStack() }, topBarActions = topBarActions)
                } else BrandTopBar(onFavorites = { nav.navigate("favorites") })
            }
        },
        bottomBar = { if (!hideBars && tab != null) FloatingNavigation(tab) { nav.navigateTab(it) } },
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
