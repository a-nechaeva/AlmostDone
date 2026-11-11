package com.example.mobile_android.feature.receipt

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.FileProvider
import java.io.File
import java.io.IOException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class ReceiptFileProvider : FileProvider()

internal class ReceiptPhotos(private val context: Context) {
    private val directory = File(context.cacheDir, "receipt-photos")

    fun create(): File {
        if (!directory.isDirectory && !directory.mkdirs()) throw IOException()
        val expired = System.currentTimeMillis() - 24 * 60 * 60 * 1000L
        directory.listFiles()?.filter { it.lastModified() < expired }?.forEach { it.delete() }
        return File.createTempFile("receipt-", ".jpg", directory)
    }

    fun uri(file: File): Uri =
        FileProvider.getUriForFile(context, "${context.packageName}.receipt", file)

    fun discard(name: String) {
        File(directory, name).delete()
    }

    suspend fun validate(uri: Uri) = withContext(Dispatchers.IO) {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) throw IOException()
    }

    suspend fun consumeCapture(name: String) {
        try {
            validate(uri(File(directory, name)))
        } finally {
            discard(name)
        }
    }
}

internal class TakeReceiptPhoto : ActivityResultContracts.TakePicture() {
    override fun createIntent(context: Context, input: Uri): Intent =
        super.createIntent(context, input).apply {
            clipData = ClipData.newRawUri("", input)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        }
}
