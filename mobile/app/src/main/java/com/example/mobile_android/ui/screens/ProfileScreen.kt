package com.example.mobile_android.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Checkbox
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.example.mobile_android.data.model.Allergens
import com.example.mobile_android.data.model.DietTag
import com.example.mobile_android.navigation.MainTab
import com.example.mobile_android.ui.components.MainScaffold
import com.example.mobile_android.viewmodel.ProfileViewModel

@Composable
fun ProfileScreen(onTabSelect: (MainTab) -> Unit, profileViewModel: ProfileViewModel) {
    MainScaffold(currentTab = MainTab.PROFILE, onTabSelect = onTabSelect) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).padding(16.dp).verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text("Профиль и ограничения", style = MaterialTheme.typography.headlineSmall)
            Text("Аллергены", style = MaterialTheme.typography.titleMedium)
            Allergens.ALL.forEach { allergen ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Checkbox(
                        checked = allergen in profileViewModel.profile.allergens,
                        onCheckedChange = { profileViewModel.toggleAllergen(allergen) },
                    )
                    Text(allergen)
                }
            }
            Text("Диеты", style = MaterialTheme.typography.titleMedium)
            DietTag.entries.forEach { diet ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Checkbox(
                        checked = diet in profileViewModel.profile.diets,
                        onCheckedChange = { profileViewModel.toggleDiet(diet) },
                    )
                    Text(diet.title)
                }
            }
            // TODO: требование 2 — стол по Познеру, бюджет, выход из аккаунта
        }
    }
}