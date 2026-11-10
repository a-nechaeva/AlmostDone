package com.example.mobile_android.feature.auth

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.*
import androidx.compose.ui.unit.dp
import com.example.mobile_android.feature.common.ActionState
import com.example.mobile_android.ui.components.*

@Composable
fun LoginScreen(
    form: LoginForm,
    action: ActionState,
    loginChanged: (String) -> Unit,
    passwordChanged: (String) -> Unit,
    signIn: () -> Unit,
    yandexSignIn: () -> Unit,
    dismiss: () -> Unit,
) {
    Column(
        Modifier.fillMaxSize()
            .safeDrawingPadding()
            .imePadding()
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Spacer(Modifier.height(32.dp))
        PageHeading("Почти готово", "Выберите, что приготовить из продуктов дома")
        Spacer(Modifier.height(24.dp))
        Text("Вход в демонстрационный режим", style = MaterialTheme.typography.titleLarge)
        Text(
            "Тестовые логин и пароль: demo / demo. Продукты и настройки сохраняются на этом устройстве."
        )
        OutlinedTextField(
            form.login,
            loginChanged,
            Modifier.fillMaxWidth(),
            label = { Text("Логин") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
            enabled = !action.pending,
        )
        OutlinedTextField(
            form.password,
            passwordChanged,
            Modifier.fillMaxWidth(),
            label = { Text("Пароль") },
            visualTransformation = PasswordVisualTransformation(),
            singleLine = true,
            keyboardOptions =
                KeyboardOptions(keyboardType = KeyboardType.Password, imeAction = ImeAction.Done),
            keyboardActions = KeyboardActions(onDone = { if (!action.pending) signIn() }),
            enabled = !action.pending,
        )
        ActionMessage(action, dismiss)
        PrimaryButton(
            signIn,
            Modifier.fillMaxWidth().heightIn(min = 48.dp),
            enabled = !action.pending,
        ) {
            Text(if (action.pending) "Входим…" else "Войти в демо")
        }
        OutlinedButton(
            onClick = yandexSignIn,
            modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
            enabled = !action.pending,
        ) {
            Text("Войти через Яндекс")
        }
        DemoNotice()
    }
}
