package com.example.mobile_android.feature.auth

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.example.mobile_android.feature.common.ActionState
import com.example.mobile_android.ui.components.ActionMessage
import com.example.mobile_android.ui.components.PageHeading
import com.example.mobile_android.ui.components.PrimaryButton

@Composable
fun LoginScreen(
    action: ActionState,
    yandexPending: Boolean,
    yandexSignIn: () -> Unit,
    dismiss: () -> Unit,
) {
    val pending = action.pending || yandexPending
    Column(
        Modifier.fillMaxSize()
            .safeDrawingPadding()
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Spacer(Modifier.height(32.dp))
        PageHeading("Почти готово", "Выберите, что приготовить из продуктов дома")
        Spacer(Modifier.height(24.dp))
        Text("Вход в приложение", style = MaterialTheme.typography.titleLarge)
        ActionMessage(action, dismiss)
        PrimaryButton(
            yandexSignIn,
            Modifier.fillMaxWidth().heightIn(min = 48.dp),
            enabled = !pending,
        ) {
            Text(if (pending) "Подключаемся…" else "Войти через Яндекс ID")
        }
    }
}
