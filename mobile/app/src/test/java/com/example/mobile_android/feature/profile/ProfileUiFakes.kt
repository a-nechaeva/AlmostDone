package com.example.mobile_android.feature.profile

import com.example.mobile_android.domain.*
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.*

internal class ProfileUiPreferences(initial: FoodPreferences = FoodPreferences()) :
    PreferencesRepository {
    val values = MutableStateFlow(initial)
    var readFailure = false
    var writeFailure = false
    var writes = 0
    var gate: CompletableDeferred<Unit>? = null
    override val preferences: Flow<FoodPreferences>
        get() = flow {
            if (readFailure) error("Fake read failure")
            emitAll(values)
        }

    override suspend fun update(transform: (FoodPreferences) -> FoodPreferences) {
        writes++
        gate?.await()
        if (writeFailure) error("Fake write failure")
        values.value = transform(values.value)
    }
}
