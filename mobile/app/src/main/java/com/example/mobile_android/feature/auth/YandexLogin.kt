package com.example.mobile_android.feature.auth

import android.content.Context
import android.content.Intent
import androidx.activity.result.contract.ActivityResultContract
import com.yandex.authsdk.YandexAuthLoginOptions
import com.yandex.authsdk.YandexAuthOptions
import com.yandex.authsdk.YandexAuthResult
import com.yandex.authsdk.YandexAuthSdk

sealed interface YandexLoginResult {
    class Success(val token: String) : YandexLoginResult
    data object Failure : YandexLoginResult
    data object Cancelled : YandexLoginResult
}

internal class YandexLogin(context: Context) : ActivityResultContract<Unit, YandexLoginResult>() {
    private val sdk = YandexAuthSdk.create(YandexAuthOptions(context.applicationContext)).contract

    override fun createIntent(context: Context, input: Unit): Intent =
        sdk.createIntent(context, YandexAuthLoginOptions())

    override fun parseResult(resultCode: Int, intent: Intent?): YandexLoginResult =
        when (val result = sdk.parseResult(resultCode, intent)) {
            is YandexAuthResult.Success -> YandexLoginResult.Success(result.token.value)
            is YandexAuthResult.Failure -> YandexLoginResult.Failure
            YandexAuthResult.Cancelled -> YandexLoginResult.Cancelled
        }
}
