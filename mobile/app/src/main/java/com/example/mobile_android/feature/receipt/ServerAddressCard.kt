package com.example.mobile_android.feature.receipt

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.example.mobile_android.data.remote.ServerStatus

/**
 * Адрес сервера — только когда связи нет: при подключении по Wi-Fi нужен IP ноутбука,
 * а по кабелю (`adb reverse tcp:8000 tcp:8000`) хватает адреса по умолчанию 127.0.0.1:8000.
 */
@Composable
internal fun ServerAddressCard(status: ServerStatus, connect: (String) -> Unit) {
    if (status !is ServerStatus.Connected) ServerAddressForm(status, connect)
}

@Composable
private fun ServerAddressForm(status: ServerStatus, connect: (String) -> Unit) {
    var address by rememberSaveable(status.url) { mutableStateOf(shortAddress(status.url)) }
    val connecting = status is ServerStatus.Connecting
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                if (connecting) "Подключаемся к серверу…" else "Сервер недоступен",
                style = MaterialTheme.typography.titleSmall,
            )
            if (status is ServerStatus.Offline) {
                Text(
                    "Подбор работает на демо-каталоге. Проверьте, что сервер запущен, и адрес.",
                    style = MaterialTheme.typography.bodySmall,
                )
            }
            OutlinedTextField(
                value = address,
                onValueChange = { address = it },
                singleLine = true,
                label = { Text("Адрес сервера") },
                supportingText = { Text("По кабелю: 127.0.0.1:8000 · по Wi-Fi: IP ноутбука:8000") },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedButton(onClick = { connect(address) }, enabled = !connecting && address.isNotBlank()) {
                Text("Подключиться")
            }
        }
    }
}

/** http://192.168.1.5:8000/api/v1/ → 192.168.1.5:8000 */
private fun shortAddress(url: String) =
    url.removePrefix("http://").removePrefix("https://").removeSuffix("/").removeSuffix("/api/v1")
