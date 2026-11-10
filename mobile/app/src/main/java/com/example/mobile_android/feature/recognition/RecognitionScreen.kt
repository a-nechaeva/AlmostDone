package com.example.mobile_android.feature.recognition

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.example.mobile_android.data.remote.RecognitionKind
import com.example.mobile_android.data.remote.RecognizedLine
import com.example.mobile_android.data.remote.ServerStatus
import com.example.mobile_android.ui.components.*
import java.io.ByteArrayOutputStream
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun RecognitionRoute(vm: RecognitionViewModel, done: () -> Unit) {
    val state by vm.state.collectAsStateWithLifecycle()
    val status by vm.status.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val picker =
        rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
            if (uri != null)
                scope.launch {
                    val jpeg = withContext(Dispatchers.IO) { runCatching { prepareJpeg(context, uri) }.getOrNull() }
                    if (jpeg == null) vm.failed("Не удалось прочитать фото") else vm.recognize(jpeg)
                }
        }
    RecognitionScreen(
        state = state,
        status = status,
        connect = vm::connect,
        kind = vm::kind,
        pick = { picker.launch("image/*") },
        toggle = vm::toggle,
        import = vm::import,
        reset = vm::reset,
        done = done,
    )
}

@Composable
fun RecognitionScreen(
    state: RecognitionState,
    status: ServerStatus,
    connect: (String) -> Unit,
    kind: (RecognitionKind) -> Unit,
    pick: () -> Unit,
    toggle: (RecognizedLine) -> Unit,
    import: () -> Unit,
    reset: () -> Unit,
    done: () -> Unit,
) {
    var url by rememberSaveable(status.url) { mutableStateOf(status.url) }
    val uploading = state.phase == RecognitionPhase.Uploading
    LazyColumn(
        contentPadding = PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item { PageHeading("Фото чека или продуктов", "Распознаём через сервер и добавляем в «Продукты»") }
        item {
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Сервер", fontWeight = FontWeight.SemiBold)
                    OutlinedTextField(
                        value = url,
                        onValueChange = { url = it },
                        singleLine = true,
                        label = { Text("Адрес") },
                        supportingText = { Text("Эмулятор: 10.0.2.2:8000 · телефон: IP ноутбука:8000") },
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        OutlinedButton(onClick = { connect(url) }, enabled = status !is ServerStatus.Connecting) {
                            Text("Подключиться")
                        }
                        Spacer(Modifier.width(12.dp))
                        Text(statusText(status), style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
        }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                RecognitionKind.entries.forEach { k ->
                    ChoiceChip(selected = state.kind == k, onClick = { kind(k) }) { Text(k.label) }
                }
            }
        }
        item {
            PrimaryButton(
                onClick = pick,
                modifier = Modifier.fillMaxWidth(),
                enabled = !uploading && status is ServerStatus.Connected,
            ) {
                Text(if (state.kind == RecognitionKind.RECEIPT) "Выбрать фото чека" else "Выбрать фото продуктов")
            }
        }
        when (val phase = state.phase) {
            RecognitionPhase.Idle -> Unit
            RecognitionPhase.Uploading ->
                item {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        CircularProgressIndicator(Modifier.size(24.dp))
                        Spacer(Modifier.width(12.dp))
                        Text("Распознаём… это до 20 секунд")
                    }
                }
            is RecognitionPhase.Failed ->
                item { EmptyPanel("Не получилось", phase.message, "Попробовать ещё раз", reset) }
            is RecognitionPhase.Imported ->
                item {
                    EmptyPanel(
                        "Добавлено продуктов: ${phase.count}",
                        "Откройте «Блюда» — подбор уже учитывает новые продукты.",
                        "К продуктам",
                        done,
                    )
                }
            is RecognitionPhase.Results -> {
                if (phase.lines.isEmpty())
                    item { EmptyPanel("Продукты не найдены", "Попробуйте другое фото.", "Ещё раз", reset) }
                else {
                    item {
                        Text(
                            "Проверьте список: отмечены уверенные совпадения, сомнительные — отметьте сами.",
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                    items(phase.lines, key = { it.lineId }) { line -> LineRow(line, line.lineId in state.selected, toggle) }
                    item {
                        PrimaryButton(onClick = import, modifier = Modifier.fillMaxWidth(), enabled = state.selected.isNotEmpty()) {
                            Text("Добавить в продукты (${state.selected.size})")
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun LineRow(line: RecognizedLine, checked: Boolean, toggle: (RecognizedLine) -> Unit) {
    val known = line.ingredientId != null
    Row(
        Modifier.fillMaxWidth().clickable(enabled = known) { toggle(line) }.padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Checkbox(checked = checked, onCheckedChange = { toggle(line) }, enabled = known)
        Column(Modifier.weight(1f)) {
            Text(
                if (known) line.name.orEmpty() else "Нет в каталоге",
                fontWeight = if (known) FontWeight.Medium else FontWeight.Normal,
                color = if (known) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant,
            )
            val details =
                buildList {
                    add(line.rawName)
                    line.quantity?.let { add("${"%.0f".format(it.value)} г") }
                    if (line.status == "ambiguous") add("проверьте")
                }
            Text(details.joinToString(" · "), style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

private fun statusText(status: ServerStatus): String =
    when (status) {
        is ServerStatus.Connecting -> "Подключаемся…"
        is ServerStatus.Connected -> "Подключено: ${status.recipes} рецептов"
        is ServerStatus.Offline -> "Нет связи — работаем на демо-каталоге. ${status.reason}"
    }

/** Фото из галереи → JPEG не больше 1600 px по длинной стороне (меньше трафика, без HEIC). */
private fun prepareJpeg(context: Context, uri: Uri): ByteArray {
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    context.contentResolver.openInputStream(uri).use { BitmapFactory.decodeStream(it, null, bounds) }
    var sample = 1
    while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= 1600) sample *= 2
    val bitmap =
        context.contentResolver.openInputStream(uri).use {
            BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample })
        } ?: error("Не удалось прочитать фото")
    val longest = maxOf(bitmap.width, bitmap.height)
    val scaled =
        if (longest > 1600) Bitmap.createScaledBitmap(bitmap, bitmap.width * 1600 / longest, bitmap.height * 1600 / longest, true)
        else bitmap
    return ByteArrayOutputStream().use { out ->
        scaled.compress(Bitmap.CompressFormat.JPEG, 85, out)
        out.toByteArray()
    }
}
