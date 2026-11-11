package com.example.mobile_android.feature.recipe

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.IconToggleButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import com.example.mobile_android.feature.common.ActionState

@Composable
fun RecipeFavoriteButton(state: RecipeState, action: ActionState, onClick: () -> Unit) {
    if (state.match == null) return

    IconToggleButton(
        checked = state.favorite,
        onCheckedChange = { onClick() },
        enabled = !action.pending,
        colors = IconButtonDefaults.iconToggleButtonColors(
            contentColor = MaterialTheme.colorScheme.primary,
            checkedContentColor = MaterialTheme.colorScheme.primary,
        ),
    ) {
        Icon(
            imageVector = if (state.favorite) Icons.Default.Favorite else Icons.Default.FavoriteBorder,
            contentDescription =
                if (state.favorite) "Убрать рецепт из избранного" else "Сохранить рецепт в избранное",
        )
    }
}
