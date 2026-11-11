package com.example.mobile_android.feature.receipt

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.FileProvider
import java.io.ByteArrayOutputStream
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

    /** Фото → JPEG не больше 1600 px по длинной стороне (меньше трафика, без HEIC). */
    suspend fun jpeg(uri: Uri): ByteArray = withContext(Dispatchers.IO) {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) throw IOException()
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= MAX_SIDE) sample *= 2
        val bitmap = context.contentResolver.openInputStream(uri)?.use {
            BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample })
        } ?: throw IOException()
        val longest = maxOf(bitmap.width, bitmap.height)
        val scaled = if (longest > MAX_SIDE)
            Bitmap.createScaledBitmap(bitmap, bitmap.width * MAX_SIDE / longest, bitmap.height * MAX_SIDE / longest, true)
        else bitmap
        ByteArrayOutputStream().use { out ->
            scaled.compress(Bitmap.CompressFormat.JPEG, 85, out)
            out.toByteArray()
        }
    }

    /** Снимок с камеры → JPEG; временный файл удаляется в любом случае. */
    suspend fun consumeCaptureJpeg(name: String): ByteArray =
        try {
            jpeg(uri(File(directory, name)))
        } finally {
            discard(name)
        }

    private companion object {
        const val MAX_SIDE = 1600
    }
}

internal class TakeReceiptPhoto : ActivityResultContracts.TakePicture() {
    override fun createIntent(context: Context, input: Uri): Intent =
        super.createIntent(context, input).apply {
            clipData = ClipData.newRawUri("", input)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        }
}
