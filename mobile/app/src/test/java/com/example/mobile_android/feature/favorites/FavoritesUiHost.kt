package com.example.mobile_android.feature.favorites

import androidx.compose.foundation.layout.*
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import com.example.mobile_android.feature.common.ActionState
import com.example.mobile_android.ui.components.BrandTopBar
import com.example.mobile_android.ui.theme.AlmostReadyTheme

@Composable
internal fun FavoritesUiHost(
    state: FavoritesState = favoritesFixture(),
    action: ActionState = ActionState(),
    favorite: (String, Boolean) -> Unit = { _, _ -> },
    recipe: (String) -> Unit = {},
    dismiss: () -> Unit = {},
    selection: ((FavoritesIngredientSelection) -> Unit)? = null,
    fontScale: Float = 1f,
) {
    CompositionLocalProvider(LocalDensity provides Density(2f, fontScale)) {
        AlmostReadyTheme {
            Scaffold(topBar = { BrandTopBar("Избранное", onBack = {}) }) { padding ->
                Box(Modifier.fillMaxSize().padding(padding).consumeWindowInsets(padding)) {
                    FavoritesContent(state, action, favorite, recipe, dismiss, selection)
                }
            }
        }
    }
}
