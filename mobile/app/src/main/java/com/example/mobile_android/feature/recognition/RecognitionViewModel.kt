package com.example.mobile_android.feature.recognition

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.mobile_android.data.remote.RecognitionKind
import com.example.mobile_android.data.remote.RecognizedLine
import com.example.mobile_android.data.remote.ServerConnection
import com.example.mobile_android.domain.HouseholdRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

sealed interface RecognitionPhase {
    data object Idle : RecognitionPhase

    data object Uploading : RecognitionPhase

    data class Results(val lines: List<RecognizedLine>) : RecognitionPhase

    data class Failed(val message: String) : RecognitionPhase

    data class Imported(val count: Int) : RecognitionPhase
}

data class RecognitionState(
    val kind: RecognitionKind = RecognitionKind.RECEIPT,
    val phase: RecognitionPhase = RecognitionPhase.Idle,
    /** line_id отмеченных строк; по умолчанию отмечены только уверенные (matched). */
    val selected: Set<String> = emptySet(),
)

class RecognitionViewModel(
    private val server: ServerConnection,
    private val household: HouseholdRepository,
) : ViewModel() {
    private val mutable = MutableStateFlow(RecognitionState())
    val state = mutable.asStateFlow()
    val status = server.status

    fun kind(value: RecognitionKind) = mutable.update { it.copy(kind = value) }

    fun connect(url: String) {
        viewModelScope.launch { server.connect(url) }
    }

    fun recognize(jpeg: ByteArray) {
        if (mutable.value.phase == RecognitionPhase.Uploading) return
        mutable.update { it.copy(phase = RecognitionPhase.Uploading, selected = emptySet()) }
        viewModelScope.launch {
            val phase =
                runCatching { server.recognize(mutable.value.kind, jpeg) }
                    .fold(
                        { lines -> RecognitionPhase.Results(lines.filter { it.rawName.isNotBlank() }) },
                        { RecognitionPhase.Failed(it.message ?: "Не удалось распознать фото") },
                    )
            val selected =
                (phase as? RecognitionPhase.Results)
                    ?.lines
                    ?.filter { it.status == "matched" && it.ingredientId != null }
                    ?.map { it.lineId }
                    ?.toSet()
                    .orEmpty()
            mutable.update { it.copy(phase = phase, selected = selected) }
        }
    }

    fun toggle(line: RecognizedLine) {
        if (line.ingredientId == null) return
        mutable.update {
            it.copy(selected = if (line.lineId in it.selected) it.selected - line.lineId else it.selected + line.lineId)
        }
    }

    fun failed(message: String) = mutable.update { it.copy(phase = RecognitionPhase.Failed(message)) }

    fun import() {
        val results = mutable.value.phase as? RecognitionPhase.Results ?: return
        val chosen = results.lines.filter { it.lineId in mutable.value.selected && it.ingredientId != null }
        viewModelScope.launch {
            chosen.forEach { household.addPantry(it.ingredientId!!, it.quantity) }
            mutable.update { it.copy(phase = RecognitionPhase.Imported(chosen.size), selected = emptySet()) }
        }
    }

    fun reset() = mutable.update { it.copy(phase = RecognitionPhase.Idle, selected = emptySet()) }
}
