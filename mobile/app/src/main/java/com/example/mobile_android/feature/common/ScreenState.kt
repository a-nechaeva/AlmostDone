package com.example.mobile_android.feature.common

import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

sealed interface ScreenState<out T> {
    data object Loading : ScreenState<Nothing>

    data class Ready<T>(val data: T) : ScreenState<T>

    data class Error(
        val message: String = "Не удалось прочитать сохранённые данные. Повторите попытку."
    ) : ScreenState<Nothing>
}

@OptIn(ExperimentalCoroutinesApi::class)
fun <T> loadingStates(refresh: Flow<Int>, source: () -> Flow<T>): Flow<ScreenState<T>> =
    refresh.flatMapLatest {
        source()
            .map<T, ScreenState<T>> { ScreenState.Ready(it) }
            .onStart { emit(ScreenState.Loading) }
            .catch { error ->
                if (error is CancellationException) throw error else emit(ScreenState.Error())
            }
    }

data class ActionState(
    val pending: Boolean = false,
    val message: String? = null,
    val failed: Boolean = false,
)

class ScreenActions(private val scope: CoroutineScope) {
    private val mutableState = MutableStateFlow(ActionState())
    val state = mutableState.asStateFlow()

    fun dismiss() {
        mutableState.update { it.copy(message = null) }
    }

    fun run(success: String? = null, action: suspend () -> Unit) {
        if (mutableState.value.pending) return
        mutableState.value = ActionState(pending = true)
        scope.launch {
            try {
                action()
                mutableState.value = ActionState(message = success)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                mutableState.value =
                    ActionState(
                        message =
                            if (error is IllegalArgumentException) error.message
                            else "Не удалось сохранить изменения. Повторите действие.",
                        failed = true,
                    )
            } finally {
                mutableState.update { it.copy(pending = false) }
            }
        }
    }
}
