package com.example.mobile_android.ui

import android.content.Context
import android.content.Intent
import androidx.activity.result.contract.ActivityResultContract
import com.example.mobile_android.feature.auth.YandexLoginResult

internal class FakeYandexLogin(
    private val result: YandexLoginResult = YandexLoginResult.Success("fake-yandex-token"),
) : ActivityResultContract<Unit, YandexLoginResult>() {
    override fun getSynchronousResult(context: Context, input: Unit) = SynchronousResult(result)

    override fun createIntent(context: Context, input: Unit): Intent = error("SDK must be faked")

    override fun parseResult(resultCode: Int, intent: Intent?): YandexLoginResult = error("SDK must be faked")
}
