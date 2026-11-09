package com.example.mobile_android.ui.components

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.example.mobile_android.data.model.Recipe
import com.example.mobile_android.data.repository.RecipeRepository

@Composable
fun RecipeCard(recipe: Recipe, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val metrics = remember(recipe) { RecipeRepository.metrics(recipe) }
    Card(onClick = onClick, modifier = modifier.fillMaxWidth()) {
        Column(Modifier.padding(12.dp)) {
            Text(recipe.title, style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.height(4.dp))
            Text(
                "${recipe.timeMinutes} мин · ${metrics.kcal.toInt()} ккал · ≈${metrics.cost.toInt()} ₽ · ${recipe.portions} порц.",
                style = MaterialTheme.typography.bodyMedium,
            )
            if (recipe.warnings.isNotEmpty()) {
                Text(
                    "⚠ ${recipe.warnings.joinToString("; ")}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                )
            }
        }
    }
}