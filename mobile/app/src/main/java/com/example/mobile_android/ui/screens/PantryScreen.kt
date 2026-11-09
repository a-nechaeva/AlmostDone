package com.example.mobile_android.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.mobile_android.navigation.MainTab
import com.example.mobile_android.ui.components.MainScaffold
import com.example.mobile_android.viewmodel.PantryViewModel

@Composable
fun PantryScreen(onTabSelect: (MainTab) -> Unit, viewModel: PantryViewModel = viewModel()) {
    MainScaffold(currentTab = MainTab.PANTRY, onTabSelect = onTabSelect) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize().padding(padding).padding(16.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text("Мои продукты", style = MaterialTheme.typography.headlineSmall)
            OutlinedTextField(
                value = viewModel.query,
                onValueChange = viewModel::onQueryChange,
                label = { Text("Ввести продукт вручную") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
            )
            // Автодополнение (требование 3): простая подсказка списком,
            // позже можно заменить на ExposedDropdownMenuBox
            viewModel.suggestions.take(5).forEach { ingredient ->
                TextButton(onClick = { viewModel.add(ingredient.id) }) {
                    Text("+ ${ingredient.name}")
                }
            }
            Spacer(Modifier.height(8.dp))
            Text("Добавлено (${viewModel.added.size}):", style = MaterialTheme.typography.titleMedium)
            viewModel.added.forEach { ingredient ->
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                    Text(ingredient.name, modifier = Modifier.weight(1f))
                    IconButton(onClick = { viewModel.remove(ingredient.id) }) {
                        Icon(Icons.Filled.Close, contentDescription = "Убрать")
                    }
                }
            }
        }
    }
}