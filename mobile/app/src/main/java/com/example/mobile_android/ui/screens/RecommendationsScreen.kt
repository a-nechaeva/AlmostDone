package com.example.mobile_android.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.mobile_android.navigation.MainTab
import com.example.mobile_android.ui.components.MainScaffold
import com.example.mobile_android.viewmodel.RecommendationsViewModel

@Composable
fun RecommendationsScreen(onTabSelect: (MainTab) -> Unit, viewModel: RecommendationsViewModel = viewModel()) {
    MainScaffold(currentTab = MainTab.RECOMMENDATIONS, onTabSelect = onTabSelect) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text("Рекомендации", style = MaterialTheme.typography.headlineSmall)
            Button(onClick = { viewModel.computeBestPurchase(2000.0) }) {
                Text("Лучшая покупка под бюджет")
            }
            viewModel.result?.let { Text(it) }
            // TODO: требование 6 — план покупок под бюджет
        }
    }
}