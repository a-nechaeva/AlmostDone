package com.example.mobile_android.feature.receipt

import android.content.ActivityNotFoundException
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ReceiptLong
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.createSavedStateHandle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.example.mobile_android.app.AppDependencies
import com.example.mobile_android.data.remote.ServerStatus
import com.example.mobile_android.domain.Ingredient
import com.example.mobile_android.ui.components.BrandTopBar
import com.example.mobile_android.ui.components.PageHeading
import java.io.IOException
import kotlinx.coroutines.launch

@Composable
internal fun ReceiptRoute(dependencies: AppDependencies, close: () -> Unit) {
    val context = LocalContext.current.applicationContext
    val photos = remember(context) { ReceiptPhotos(context) }
    val model: ReceiptViewModel = viewModel(factory = remember(dependencies, photos) {
        viewModelFactory {
            initializer {
                ReceiptViewModel(
                    dependencies.catalog,
                    dependencies.receiptImporter,
                    createSavedStateHandle(),
                    photos::discard,
                    photoRecognizer = dependencies.server?.receiptRecognizer(),
                )
            }
        }
    })
    val state by model.state.collectAsStateWithLifecycle()
    val photoRequest by model.photoRequest.collectAsStateWithLifecycle()
    val kind by model.kind.collectAsStateWithLifecycle()
    val server = dependencies.server
    val serverStatus = server?.status?.collectAsStateWithLifecycle()?.value
    val scope = rememberCoroutineScope()
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (model.finishPhotoRequest(ReceiptPhotoRequest.PICKER) && uri != null) {
            model.readImage { photos.jpeg(uri) }
        }
    }
    val camera = rememberLauncherForActivityResult(TakeReceiptPhoto()) { success ->
        if (model.finishPhotoRequest(ReceiptPhotoRequest.CAMERA)) {
            val name = model.cameraFinished()
            if (name != null) {
                if (success && model.state.value is ReceiptState.Capture)
                    model.readImage { photos.consumeCaptureJpeg(name) }
                else photos.discard(name)
            }
        }
    }
    fun launchPhoto(request: ReceiptPhotoRequest, missing: ReceiptPhotoIssue, launch: () -> Unit) {
        if (!model.beginPhotoRequest(request)) return
        val issue = try {
            launch()
            return
        } catch (_: ActivityNotFoundException) {
            missing
        } catch (_: SecurityException) {
            ReceiptPhotoIssue.ACCESS
        } catch (_: IOException) {
            ReceiptPhotoIssue.UNREADABLE
        }
        if (request == ReceiptPhotoRequest.CAMERA) model.cameraFinished()?.let(photos::discard)
        model.finishPhotoRequest(request)
        model.photoIssue(issue)
    }
    ReceiptScreen(
        state = state,
        close = close,
        takePhoto = {
            launchPhoto(ReceiptPhotoRequest.CAMERA, ReceiptPhotoIssue.NO_CAMERA) {
                val file = photos.create()
                model.cameraFile = file.name
                camera.launch(photos.uri(file))
            }
        },
        choosePhoto = {
            launchPhoto(ReceiptPhotoRequest.PICKER, ReceiptPhotoIssue.NO_PICKER) {
                picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
            }
        },
        reset = model::reset,
        toggle = model::toggle,
        edit = model::edit,
        confirm = model::confirm,
        photoPending = photoRequest != null,
        kind = kind,
        chooseKind = if (model.canChooseKind) model::chooseKind else null,
        serverStatus = serverStatus,
        connectServer = { address -> server?.let { scope.launch { it.connect(address) } } },
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ReceiptScreen(
    state: ReceiptState,
    close: () -> Unit,
    takePhoto: () -> Unit,
    choosePhoto: () -> Unit,
    reset: () -> Unit,
    toggle: (Int, Boolean) -> Unit,
    edit: (Int, Ingredient, String) -> Unit,
    confirm: () -> Unit,
    photoPending: Boolean = false,
    kind: ReceiptPhotoKind = ReceiptPhotoKind.RECEIPT,
    /** null — выбора нет (демо-распознавание понимает только чек). */
    chooseKind: ((ReceiptPhotoKind) -> Unit)? = null,
    /** null — приложение без сервера (демо, тесты): карточки адреса нет. */
    serverStatus: ServerStatus? = null,
    connectServer: (String) -> Unit = {},
) {
    val products = kind == ReceiptPhotoKind.PRODUCTS
    val review = state as? ReceiptState.Review
    val saving = review?.saving == true
    val back: () -> Unit = {
        when (state) {
            ReceiptState.Reading, is ReceiptState.Review -> reset()
            else -> close()
        }
    }
    BackHandler(enabled = saving || state is ReceiptState.Reading || state is ReceiptState.Review) {
        if (!saving) back()
    }
    var editing by rememberSaveable { mutableStateOf<Int?>(null) }
    val editedLine = review?.lines?.find { it.id == editing }
    if (review != null && editedLine != null) {
        ReceiptLineEditor(editedLine, review.ingredients, { editing = null }) { ingredient, amount ->
            edit(editedLine.id, ingredient, amount)
            editing = null
        }
    }
    Scaffold(
        topBar = {
            val title = when (state) {
                is ReceiptState.Capture -> if (chooseKind != null) "Добавить по фото" else "Добавить по чеку"
                ReceiptState.Reading -> if (products) "Фото продуктов" else "Фото чека"
                is ReceiptState.Review -> "Проверить продукты"
                is ReceiptState.Added -> "Добавление продуктов"
            }
            if (saving) TopAppBar(title = { Text(title) })
            else BrandTopBar(title, onBack = back)
        },
    ) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).consumeWindowInsets(padding)
                .imePadding().verticalScroll(rememberScrollState()).padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            when (state) {
                is ReceiptState.Capture -> {
                    if (serverStatus != null) ServerAddressCard(serverStatus, connectServer)
                    ReceiptCapture(state, takePhoto, choosePhoto, close, enabled = !photoPending, kind, chooseKind)
                }
                ReceiptState.Reading -> {
                    if (products) PageHeading("Смотрим фото", "Ищем продукты — это до 20 секунд")
                    else PageHeading("Читаем чек", "Ищем продукты и количество")
                    LinearProgressIndicator(Modifier.fillMaxWidth())
                    OutlinedButton(onClick = reset, modifier = Modifier.fillMaxWidth()) { Text("Отменить") }
                }
                is ReceiptState.Review -> ReceiptReview(state, toggle, { editing = it }, confirm, products)
                is ReceiptState.Added -> {
                    PageHeading("Продукты добавлены домой", state.names.joinToString(", "))
                    Text("Запасы обновились. Можно заново проверить подбор блюд.")
                    Button(onClick = close, modifier = Modifier.fillMaxWidth()) { Text("Открыть продукты") }
                }
            }
        }
    }
}

@Composable
private fun ReceiptCapture(
    state: ReceiptState.Capture,
    takePhoto: () -> Unit,
    choosePhoto: () -> Unit,
    close: () -> Unit,
    enabled: Boolean,
    kind: ReceiptPhotoKind = ReceiptPhotoKind.RECEIPT,
    chooseKind: ((ReceiptPhotoKind) -> Unit)? = null,
) {
    val issue = state.issue
    val products = kind == ReceiptPhotoKind.PRODUCTS
    if (chooseKind != null) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(
                selected = !products,
                onClick = { chooseKind(ReceiptPhotoKind.RECEIPT) },
                label = { Text("Чек") },
                enabled = enabled,
            )
            FilterChip(
                selected = products,
                onClick = { chooseKind(ReceiptPhotoKind.PRODUCTS) },
                label = { Text("Продукты") },
                enabled = enabled,
            )
        }
    }
    if (issue == null) {
        if (products) PageHeading("Сфотографируйте продукты", "Холодильник, полку или пакет — чтобы были видны упаковки")
        else PageHeading("Сфотографируйте чек", "Целиком, при хорошем освещении")
        Surface(
            Modifier.fillMaxWidth().height(248.dp),
            shape = MaterialTheme.shapes.extraLarge,
            color = MaterialTheme.colorScheme.secondaryContainer,
        ) {
            Box(contentAlignment = Alignment.Center) {
                Surface(
                    Modifier.size(width = 132.dp, height = 186.dp),
                    shape = MaterialTheme.shapes.medium,
                    color = MaterialTheme.colorScheme.surface,
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Icon(Icons.AutoMirrored.Outlined.ReceiptLong, null, Modifier.size(72.dp))
                    }
                }
            }
        }
        Text("Перед добавлением проверьте названия и количество.")
    } else {
        val (title, details) = when (issue) {
            ReceiptPhotoIssue.NO_CAMERA -> "Камера недоступна" to (if (products) "Выберите готовое фото." else "Выберите готовое фото чека.")
            ReceiptPhotoIssue.NO_PICKER -> "Выбор фото недоступен" to "Сделайте фото или добавьте продукты вручную."
            ReceiptPhotoIssue.ACCESS -> "Нет доступа к фото" to "Проверьте доступ или выберите другое фото."
            ReceiptPhotoIssue.UNREADABLE -> (if (products) "Фото не удалось прочитать" else "Чек не удалось прочитать") to "Попробуйте снять ближе и без бликов."
            ReceiptPhotoIssue.EMPTY -> (if (products) "На фото не нашлось продуктов" else "В чеке не нашлось продуктов") to "Попробуйте другое фото."
            ReceiptPhotoIssue.SERVER -> "Сервер распознавания недоступен" to "Проверьте подключение к серверу и повторите."
        }
        PageHeading(title, details)
    }
    if (issue != ReceiptPhotoIssue.NO_CAMERA) {
        Button(onClick = takePhoto, modifier = Modifier.fillMaxWidth(), enabled = enabled) {
            Text(if (issue == null) "Сделать фото" else "Снять ещё раз")
        }
    }
    OutlinedButton(onClick = choosePhoto, modifier = Modifier.fillMaxWidth(), enabled = enabled) {
        Text("Выбрать из галереи")
    }
    if (issue != null) TextButton(onClick = close, modifier = Modifier.fillMaxWidth()) {
        Text("Добавить вручную")
    }
}

@Composable
private fun ReceiptReview(
    state: ReceiptState.Review,
    toggle: (Int, Boolean) -> Unit,
    edit: (Int) -> Unit,
    confirm: () -> Unit,
    products: Boolean = false,
) {
    PageHeading(if (products) "Нашли на фото" else "Нашли в чеке", "Выберите, что добавить домой")
    if (state.demo) Text("Демо · позиции взяты из примера чека", style = MaterialTheme.typography.bodySmall)
    for (line in state.lines) {
        val ingredient = state.ingredient(line)
        val quantity = line.quantity(ingredient)
        Card(
            colors = CardDefaults.cardColors(
                containerColor = if (ingredient == null) MaterialTheme.colorScheme.tertiaryContainer
                else MaterialTheme.colorScheme.surface,
            ),
            modifier = Modifier.fillMaxWidth(),
        ) {
            Column(Modifier.padding(12.dp)) {
                val selectable = !state.saving && quantity != null
                Row(
                    Modifier.fillMaxWidth().heightIn(min = 48.dp).toggleable(
                        value = line.selected,
                        enabled = selectable,
                        role = Role.Checkbox,
                        onValueChange = { toggle(line.id, it) },
                    ),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Checkbox(checked = line.selected, onCheckedChange = null, enabled = selectable)
                    Column(Modifier.weight(1f)) {
                        Text(
                            ingredient?.name ?: "Не распознали",
                            style = MaterialTheme.typography.titleMedium,
                        )
                        Text(line.text, style = MaterialTheme.typography.bodySmall)
                        if (quantity != null) Text("${line.amount} ${quantity.unit.label}")
                    }
                }
                TextButton(onClick = { edit(line.id) }, enabled = !state.saving) {
                    Text(if (ingredient == null) "Выбрать продукт из каталога" else "Исправить продукт")
                }
            }
        }
    }
    state.error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
    val selected = state.lines.count { it.selected }
    Button(
        onClick = confirm,
        enabled = selected > 0 && !state.saving,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Text(if (state.saving) "Добавляем…" else "Добавить выбранное ($selected)")
    }
    Text("Проверьте названия и количество перед подтверждением.")
}

@Composable
private fun ReceiptLineEditor(
    line: ReceiptLine,
    ingredients: List<Ingredient>,
    close: () -> Unit,
    save: (Ingredient, String) -> Unit,
) {
    var query by rememberSaveable(line.id) { mutableStateOf("") }
    var id by rememberSaveable(line.id) { mutableStateOf(line.ingredientId) }
    var amount by rememberSaveable(line.id) { mutableStateOf(line.amount) }
    val selected = ingredients.find { it.id == id }
    AlertDialog(
        onDismissRequest = close,
        title = { Text("Исправить продукт") },
        text = {
            LazyColumn(
                Modifier.fillMaxWidth().heightIn(max = 420.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                item { Text(line.text) }
                item {
                    OutlinedTextField(
                        query, { query = it }, label = { Text("Поиск по каталогу") },
                        singleLine = true, modifier = Modifier.fillMaxWidth(),
                    )
                }
                if (selected != null) {
                    item {
                        OutlinedTextField(
                            amount, { amount = it }, label = { Text("Количество, ${selected.unit.label}") },
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                            singleLine = true, modifier = Modifier.fillMaxWidth(),
                        )
                    }
                }
                items(ingredients.filter { it.name.contains(query.trim(), ignoreCase = true) }, key = { it.id }) { ingredient ->
                    Row(
                        Modifier.fillMaxWidth()
                            .selectable(id == ingredient.id, role = Role.RadioButton) {
                                if (id != ingredient.id) amount = ""
                                id = ingredient.id
                            }.heightIn(min = 48.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        RadioButton(selected = id == ingredient.id, onClick = null)
                        Text(ingredient.name, Modifier.padding(start = 8.dp))
                    }
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = { selected?.let { save(it, amount) } },
                enabled = line.copy(amount = amount, unit = selected?.unit).quantity(selected) != null,
            ) { Text("Сохранить") }
        },
        dismissButton = { TextButton(onClick = close) { Text("Отмена") } },
    )
}
