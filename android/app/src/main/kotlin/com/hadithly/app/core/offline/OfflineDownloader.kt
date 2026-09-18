package com.hadithly.app.core.offline

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.atomic.AtomicBoolean

class OfflineDownloadException(message: String) : IllegalStateException(message)

/**
 * Injectable download transport. Production streams bytes with HTTP `Range`
 * resume; tests substitute a fake. Signed Convex storage URLs are
 * short-lived, so the store re-fetches a fresh manifest URL before every run
 * and resumes from the persisted `.tmp` length where the server honors it.
 */
interface OfflineDownloadTransport {
    /**
     * Streams the response into [tmpFile]. When [offset] > 0 a
     * `bytes=<offset>-` header is sent: a 206 response appends, anything else
     * restarts the file from zero. Suspends the worker; cancellation throws.
     */
    suspend fun downloadToFile(
        url: String,
        tmpFile: File,
        offset: Long,
        progress: (Double) -> Unit,
    )

    fun cancel()
}

/**
 * Foreground HttpURLConnection transport. Android may suspend work in the
 * background: the run reports interruption, the store keeps the partial
 * `.tmp` plus its length, and the download resumes on the next run. Nothing
 * partial is ever verified or activated.
 */
class HttpOfflineTransport : OfflineDownloadTransport {
    private val cancelled = AtomicBoolean(false)
    @Volatile private var connection: HttpURLConnection? = null

    override suspend fun downloadToFile(
        url: String,
        tmpFile: File,
        offset: Long,
        progress: (Double) -> Unit,
    ) {
        cancelled.set(false)
        withContext(Dispatchers.IO) {
            val conn = (URL(url).openConnection() as HttpURLConnection).also { connection = it }
            try {
                conn.connectTimeout = 30_000
                conn.readTimeout = 60_000
                conn.instanceFollowRedirects = true
                if (offset > 0) conn.setRequestProperty("Range", "bytes=$offset-")
                conn.connect()
                val code = conn.responseCode
                if (code != HttpURLConnection.HTTP_OK && code != HttpURLConnection.HTTP_PARTIAL) {
                    throw OfflineDownloadException("Download failed (HTTP $code).")
                }
                val contentLength = conn.getHeaderField("Content-Length")?.toLongOrNull() ?: -1L
                val total =
                    if (code == HttpURLConnection.HTTP_PARTIAL && offset > 0 && contentLength >= 0) {
                        contentLength + offset
                    } else {
                        contentLength
                    }
                val append = code == HttpURLConnection.HTTP_PARTIAL && offset > 0
                var written = if (append) offset else 0L
                conn.inputStream.use { input ->
                    java.io.FileOutputStream(tmpFile, append).use { out ->
                        val buffer = ByteArray(64 * 1024)
                        while (true) {
                            ensureActive()
                            if (cancelled.get()) throw OfflineDownloadException("Cancelled.")
                            val read = input.read(buffer)
                            if (read < 0) break
                            out.write(buffer, 0, read)
                            written += read
                            if (total > 0) progress(written.toDouble() / total.toDouble())
                        }
                    }
                }
                progress(1.0)
            } finally {
                conn.disconnect()
                if (connection === conn) connection = null
            }
        }
    }

    override fun cancel() {
        cancelled.set(true)
        connection?.disconnect()
    }
}
