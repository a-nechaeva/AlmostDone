package com.example.mobile_android.ui.components

import android.graphics.BitmapFactory
import android.util.Log
import android.util.LruCache
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import java.net.HttpURLConnection
import java.net.URL
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext

/**
 * Фото рецептов по ссылке (photo_url из каталога сервера) без сторонних библиотек.
 *
 * Картинка уменьшается до [MAX_SIDE] px по длинной стороне и хранится в памяти (до 1/8 памяти
 * приложения): список блюд прокручивается без повторных загрузок. Ошибка сети — null, вместо фото
 * остаётся заглушка; повторная попытка будет при следующем показе.
 */
internal object RemoteImages {
    private const val MAX_SIDE = 800
    private const val MAX_BYTES = 8 * 1024 * 1024
    private const val TAG = "RemoteImages"

    private val cache =
        object : LruCache<String, ImageBitmap>((Runtime.getRuntime().maxMemory() / 8).toInt()) {
            override fun sizeOf(key: String, value: ImageBitmap) = value.width * value.height * 4
        }
    private val loading = mutableMapOf<String, Deferred<ImageBitmap?>>()

    fun isRemote(photo: String) = photo.startsWith("https://") || photo.startsWith("http://")

    fun cached(url: String): ImageBitmap? = cache.get(url)

    suspend fun load(url: String): ImageBitmap? {
        cache.get(url)?.let { return it }
        val job = synchronized(loading) {
            loading.getOrPut(url) {
                @OptIn(kotlinx.coroutines.DelicateCoroutinesApi::class)
                kotlinx.coroutines.GlobalScope.async(Dispatchers.IO) {
                    try {
                        download(url)?.also { cache.put(url, it) }
                    } finally {
                        synchronized(loading) { loading.remove(url) }
                    }
                }
            }
        }
        return try {
            job.await()
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            null
        }
    }

    private suspend fun download(url: String): ImageBitmap? = withContext(Dispatchers.IO) {
        val bytes = runCatching {
            val connection = URL(url).openConnection() as HttpURLConnection
            connection.connectTimeout = 10_000
            connection.readTimeout = 15_000
            try {
                if (connection.responseCode !in 200..299) {
                    Log.w(TAG, "HTTP ${connection.responseCode} для $url")
                    return@runCatching null
                }
                connection.inputStream.use { input ->
                    val out = java.io.ByteArrayOutputStream()
                    val buffer = ByteArray(16 * 1024)
                    while (true) {
                        val n = input.read(buffer)
                        if (n < 0) break
                        out.write(buffer, 0, n)
                        if (out.size() > MAX_BYTES) return@runCatching null
                    }
                    out.toByteArray()
                }
            } finally {
                connection.disconnect()
            }
        }.onFailure { Log.w(TAG, "Не удалось загрузить $url", it) }.getOrNull() ?: return@withContext null
        decode(bytes).also { if (it == null) Log.w(TAG, "Не удалось декодировать $url") }
    }

    private fun decode(bytes: ByteArray): ImageBitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= MAX_SIDE) sample *= 2
        val options = BitmapFactory.Options().apply { inSampleSize = sample }
        return BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)?.asImageBitmap()
    }
}
