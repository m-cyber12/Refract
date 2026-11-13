package dev.refract

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.min

/** User-initiated, one-page Android platform rendering. Not a parser sandbox. */
class PdfPageRenderer(private val cacheDir: File, private val channel: MethodChannel) {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var busy = false // method calls and completion both run on main

    fun install() {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "render") { result.notImplemented(); return@setMethodCallHandler }
            val bytes = call.argument<ByteArray>("bytes")
            val index = call.argument<Int>("index")
            if (busy || bytes == null || bytes.isEmpty() || bytes.size > 10 * 1024 * 1024 || index == null || index !in 0..199) {
                result.error("invalid_request", "Invalid or busy PDF renderer", null)
                return@setMethodCallHandler
            }
            busy = true
            worker.execute {
                try {
                    val page = render(bytes, index)
                    main.post { busy = false; result.success(page) }
                } catch (_: Exception) {
                    main.post { busy = false; result.error("render_failed", "PDF page could not be rendered", null) }
                }
            }
        }
    }

    private fun render(bytes: ByteArray, index: Int): Map<String, Any> {
        val file = File.createTempFile("refract-pdf-view-", ".tmp", cacheDir)
        try {
            file.outputStream().use { it.write(bytes) }
            val fd = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
            // Unlink before invoking the parser; the descriptor remains open.
            // A process death between creation and unlink can leave a copy.
            if (!file.delete()) { fd.close(); throw IllegalStateException("Could not remove temporary file") }
            val renderer = try { PdfRenderer(fd) } catch (e: Exception) { fd.close(); throw e }
            renderer.use {
                val count = it.pageCount
                require(count in 1..200 && index < count)
                it.openPage(index).use { page ->
                    require(page.width > 0 && page.height > 0)
                    val scale = min(1200.0 / page.width, 1600.0 / page.height)
                    val width = max(1, (page.width * scale).toInt())
                    val height = max(1, (page.height * scale).toInt())
                    val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                    try {
                        bitmap.eraseColor(Color.WHITE)
                        page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                        val output = ByteArrayOutputStream()
                        check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, output))
                        val png = output.toByteArray()
                        require(png.size <= 8 * 1024 * 1024)
                        return mapOf("png" to png, "pages" to count, "index" to index)
                    } finally { bitmap.recycle() }
                }
            }
        } finally { file.delete() }
    }

    fun close() { channel.setMethodCallHandler(null); worker.shutdown() }
}
