package com.example.mobile_android.feature.receipt

import androidx.lifecycle.SavedStateHandle
import com.example.mobile_android.data.DemoCatalog
import com.example.mobile_android.data.DemoCatalogRepository
import com.example.mobile_android.domain.Quantity
import com.example.mobile_android.domain.QuantityUnit
import java.io.IOException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class ReceiptViewModelTest {
    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    @Test
    fun onlyTheActivePhotoRequestCanComplete() = runTest(dispatcher) {
        val vm = model()
        assertTrue(vm.beginPhotoRequest(ReceiptPhotoRequest.CAMERA))
        vm.cameraFile = "first.jpg"
        assertFalse(vm.beginPhotoRequest(ReceiptPhotoRequest.CAMERA))
        assertFalse(vm.beginPhotoRequest(ReceiptPhotoRequest.PICKER))
        assertFalse(vm.finishPhotoRequest(ReceiptPhotoRequest.PICKER))
        assertEquals("first.jpg", vm.cameraFile)
        assertTrue(vm.finishPhotoRequest(ReceiptPhotoRequest.CAMERA))
        assertEquals("first.jpg", vm.cameraFinished())
        assertNull(vm.cameraFile)
        assertTrue(vm.beginPhotoRequest(ReceiptPhotoRequest.PICKER))
    }

    @Test
    fun cancellationAccessEmptyAndUnreadablePhotoCanBeRetried() = runTest(dispatcher) {
        var recognizeCalls = 0
        val vm = model(recognizer = ReceiptRecognizer {
            if (++recognizeCalls == 1) emptyList() else DemoReceiptRecognizer.recognize()
        })
        val pending = CompletableDeferred<Unit>()
        vm.readPhoto { pending.await() }
        runCurrent()
        assertEquals(ReceiptState.Reading, vm.state.value)
        vm.reset()
        pending.complete(Unit)
        runCurrent()
        assertEquals(ReceiptState.Capture(), vm.state.value)
        vm.readPhoto { throw SecurityException() }
        runCurrent()
        assertEquals(ReceiptState.Capture(ReceiptPhotoIssue.ACCESS), vm.state.value)
        vm.readPhoto { throw IOException() }
        runCurrent()
        assertEquals(ReceiptState.Capture(ReceiptPhotoIssue.UNREADABLE), vm.state.value)
        vm.readPhoto {}
        runCurrent()
        assertEquals(ReceiptState.Capture(ReceiptPhotoIssue.EMPTY), vm.state.value)
        vm.readPhoto {}
        runCurrent()
        assertTrue(vm.state.value is ReceiptState.Review)
    }

    @Test
    fun selectedCanonicalLinesAggregateAndOnlyOneConfirmedWriteSucceeds() = runTest(dispatcher) {
        val firstWrite = CompletableDeferred<Unit>()
        val writes = mutableListOf<Map<String, Quantity>>()
        val vm = model(ReceiptImporter {
            writes += it
            if (writes.size == 1) {
                firstWrite.await()
                throw IOException()
            }
        })
        vm.readPhoto {}
        runCurrent()
        val initial = vm.state.value as ReceiptState.Review
        vm.toggle(4, true)
        assertEquals(initial, vm.state.value)
        val cheese = DemoCatalog.catalog.ingredient("hard-cheese")!!
        vm.edit(4, cheese, "0")
        assertFalse((vm.state.value as ReceiptState.Review).lines.last().selected)
        vm.edit(4, cheese, "25,5")
        assertFalse((vm.state.value as ReceiptState.Review).lines.last().selected)
        vm.toggle(4, true)
        assertTrue(writes.isEmpty())
        vm.confirm()
        vm.confirm()
        runCurrent()
        assertTrue((vm.state.value as ReceiptState.Review).saving)
        assertEquals(listOf(mapOf(cheese.id to Quantity(225.5, QuantityUnit.GRAM))), writes)
        firstWrite.complete(Unit)
        runCurrent()
        val failed = vm.state.value as ReceiptState.Review
        assertNotNull(failed.error)
        assertEquals(2, failed.lines.count { it.selected })
        vm.confirm()
        runCurrent()
        vm.confirm()
        runCurrent()
        assertEquals(2, writes.size)
        assertEquals(writes.first(), writes.last())
        assertEquals(ReceiptState.Added(listOf(cheese.name)), vm.state.value)
    }

    @Test
    fun photoGoesToServerRecognizerAndServerFailureIsNotUnreadablePhoto() = runTest(dispatcher) {
        val sent = mutableListOf<ByteArray>()
        var fail = true
        val kinds = mutableListOf<ReceiptPhotoKind>()
        val vm = model(photoRecognizer = { jpeg, kind ->
            sent += jpeg
            kinds += kind
            if (fail) throw ReceiptServerException("offline")
            RecognizedReceipt(
                "rec-1",
                listOf(ReceiptLine(1, "СЫР 200Г", "hard-cheese", "200", QuantityUnit.GRAM, true,
                    serverLineId = "line-1")),
            )
        })
        vm.readImage { byteArrayOf(1, 2, 3) }
        runCurrent()
        assertEquals(ReceiptState.Capture(ReceiptPhotoIssue.SERVER), vm.state.value)
        fail = false
        assertTrue(vm.canChooseKind)
        vm.chooseKind(ReceiptPhotoKind.PRODUCTS)
        vm.readImage { byteArrayOf(4) }
        runCurrent()
        val review = vm.state.value as ReceiptState.Review
        assertEquals(listOf("СЫР 200Г"), review.lines.map { it.text })
        assertTrue(review.lines.single().selected)
        assertFalse(review.demo)
        assertEquals("rec-1", review.recognitionId)
        assertEquals(listOf(ReceiptPhotoKind.RECEIPT, ReceiptPhotoKind.PRODUCTS), kinds)
        vm.chooseKind(ReceiptPhotoKind.RECEIPT) // на экране проверки вид фото уже не меняется
        assertEquals(ReceiptPhotoKind.PRODUCTS, vm.kind.value)
        assertEquals(listOf(listOf<Byte>(1, 2, 3), listOf<Byte>(4)), sent.map { it.toList() })
    }

    @Test
    fun serverRecognitionConfirmsThroughRecognitionImportsAndKeepsSelectionOnFailure() = runTest(dispatcher) {
        val imports = mutableListOf<Triple<String, String, List<ReceiptImportLine>>>()
        var fail = true
        val serverImporter = object : ServerReceiptImporter {
            override suspend fun importReceipt(
                recognitionId: String,
                kind: String,
                lines: List<ReceiptImportLine>,
            ) {
                imports += Triple(recognitionId, kind, lines)
                if (fail) throw IOException("offline")
            }
        }
        val vm = model(
            photoRecognizer = { _, _ ->
                RecognizedReceipt(
                    "rec-9",
                    listOf(
                        ReceiptLine(1, "СЫР 200Г", "hard-cheese", "200", QuantityUnit.GRAM, true,
                            serverLineId = "line-1"),
                        ReceiptLine(2, "ПАКЕТ", null, serverLineId = "line-2"),
                    ),
                )
            },
            serverImporter = serverImporter,
        )
        vm.readImage { byteArrayOf(1) }
        runCurrent()
        val review = vm.state.value as ReceiptState.Review
        vm.confirm()
        vm.confirm()
        runCurrent()
        assertTrue((vm.state.value as ReceiptState.Review).saving.not())
        // Первая попытка упала: выбор сохранён, ошибка видна, импорт не подтверждён локально.
        val failed = vm.state.value as ReceiptState.Review
        assertNotNull(failed.error)
        assertEquals(1, failed.lines.count { it.selected })
        assertEquals(1, imports.size)
        assertEquals(Triple("rec-9", "receipt", listOf(
            ReceiptImportLine("line-1", "hard-cheese", Quantity(200.0, QuantityUnit.GRAM)),
        )), imports.single())
        fail = false
        vm.confirm()
        runCurrent()
        assertEquals(ReceiptState.Added(listOf("Твёрдый сыр")), vm.state.value)
        assertEquals(2, imports.size)
        assertEquals(imports.first(), imports.last())
    }

    private fun model(
        writer: ReceiptImporter? = null,
        recognizer: ReceiptRecognizer = DemoReceiptRecognizer,
        photoRecognizer: (suspend (ByteArray, ReceiptPhotoKind) -> RecognizedReceipt)? = null,
        serverImporter: ServerReceiptImporter? = null,
    ) = ReceiptViewModel(
        DemoCatalogRepository(), writer, SavedStateHandle(), {}, recognizer, photoRecognizer,
        serverImporter,
    )
}
