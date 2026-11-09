package dev.refract

import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.UUID
import java.util.concurrent.Executors

/** OS-authorized intake only. Unreviewed input is bounded process memory, not disk.
 * Pull + acknowledgement avoids a cold-start push before Dart has a listener.
 * No URI/path is sent to Dart, no broad storage grant and no persisted URI grant.
 */
class MainActivity : FlutterActivity() {
    companion object {
        private const val TEXT_LIMIT = 2 * 1024 * 1024
        private const val PDF_LIMIT = 10 * 1024 * 1024
        private const val TOTAL_LIMIT = 24 * 1024 * 1024
        private const val COUNT_LIMIT = 16
        private val executor = Executors.newSingleThreadExecutor()
        private val main = Handler(Looper.getMainLooper())
        private val pending = ArrayDeque<Map<String, Any>>() // accessed on main only
        private var bytesHeld = 0
        private var channel: MethodChannel? = null
        private var notice: String? = null
        private var inFlight = 0
    }
    private var ownChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val c = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.refract/shared")
        ownChannel = c
        channel = c
        c.setMethodCallHandler { call, result ->
            when (call.method) {
                "peekShare" -> result.success(mapOf("draft" to pending.firstOrNull(), "notice" to notice))
                "ackShare" -> {
                    val id = call.arguments as? String
                    if (pending.firstOrNull()?.get("id") == id) {
                        val removed = pending.removeFirst()
                        bytesHeld -= (removed["bytes"] as? ByteArray)?.size ?: 0
                    }
                    result.success(null)
                }
                "clearShareNotice" -> { notice = null; result.success(null) }
                else -> result.notImplemented()
            }
        }
        receive(intent)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        ownChannel?.setMethodCallHandler(null)
        if (channel === ownChannel) channel = null
        ownChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        receive(intent)
    }

    private fun receive(source: Intent?) {
        if (source?.action != Intent.ACTION_SEND && source?.action != Intent.ACTION_SEND_MULTIPLE) return
        // Snapshot before clearing the activity's intent, so recreation cannot replay it.
        val incoming = Intent(source)
        source?.action = null
        source?.removeExtra(Intent.EXTRA_TEXT)
        source?.removeExtra(Intent.EXTRA_STREAM)
        source?.clipData = null
        // Reserve work on the main thread BEFORE submission. Never grow an unbounded
        // executor backlog of intents/grants while Dart is unavailable.
        if (pending.size + inFlight >= COUNT_LIMIT) { rejectCapacity(); return }
        inFlight++
        val resolver = applicationContext.contentResolver
        executor.execute {
            val entries = mutableListOf<Map<String, Any>>()
            try {
                @Suppress("DEPRECATION")
                val uris: List<Uri> = if (incoming.action == Intent.ACTION_SEND_MULTIPLE) {
                    incoming.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.toList() ?: emptyList()
                } else listOfNotNull(incoming.getParcelableExtra<Uri>(Intent.EXTRA_STREAM))
                val clips = incoming.clipData
                val streams = if (uris.isNotEmpty()) uris else (0 until (clips?.itemCount ?: 0)).mapNotNull { clips?.getItemAt(it)?.uri }.filter { it.scheme != "http" && it.scheme != "https" }
                if (streams.isNotEmpty()) {
                    for (uri in streams.take(COUNT_LIMIT)) {
                        try {
                            require(uri.scheme == "content")
                            var name = "Shared file"
                            resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                                if (cursor.moveToFirst() && !cursor.isNull(0)) name = cursor.getString(0)
                            }
                            val safeName = name.filter { !it.isISOControl() }.take(120).ifBlank { "Shared file" }
                            val ext = safeName.substringAfterLast('.', "").lowercase()
                            val mime = resolver.getType(uri)?.substringBefore(';')?.lowercase() ?: incoming.type
                            val format = when (ext) {
                                "pdf" -> "pdf"
                                "md", "markdown" -> "markdown"
                                "html", "htm" -> "html"
                                "txt" -> "text"
                                else -> when (mime) {
                                    "application/pdf" -> "pdf"
                                    "text/plain" -> "text"
                                    "text/markdown" -> "markdown"
                                    "text/html" -> "html"
                                    else -> throw IllegalArgumentException()
                                }
                            }
                            val limit = if (format == "pdf") PDF_LIMIT else TEXT_LIMIT
                            val bytes = resolver.openInputStream(uri)?.use { input ->
                                val out = ByteArrayOutputStream()
                                val buffer = ByteArray(16 * 1024)
                                while (true) {
                                    val n = input.read(buffer)
                                    if (n < 0) break
                                    require(out.size() + n <= limit)
                                    out.write(buffer, 0, n)
                                }
                                out.toByteArray()
                            } ?: throw IllegalArgumentException()
                            require(bytes.isNotEmpty())
                            // Bound this batch as well as the pending queue.
                            if (entries.sumOf { (it["bytes"] as? ByteArray)?.size ?: 0 } + bytes.size > TOTAL_LIMIT) {
                                entries.add(failure("Share batch exceeds 24 MiB. Share fewer files.")); break
                            }
                            entries.add(mapOf("id" to UUID.randomUUID().toString(), "name" to safeName, "format" to format, "bytes" to bytes))
                        } catch (_: Exception) {
                            entries.add(failure("Shared file could not be read: unsupported type, empty/oversized input, or expired provider access. Share it again or use Import."))
                        }
                    }
                    if (streams.size > COUNT_LIMIT) entries.add(failure("Only the first 16 shared files were read. Share the remaining files separately."))
                    val caption = incoming.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
                    if (!caption.isNullOrEmpty()) entries.add(textEntry(caption))
                    else for (n in 0 until (clips?.itemCount ?: 0).coerceAtMost(COUNT_LIMIT)) {
                        clipText(clips?.getItemAt(n))?.let { entries.add(textEntry(it)) }
                    }
                } else {
                    val text = incoming.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
                    if (text != null) entries.add(textEntry(text))
                    else {
                        val count = clips?.itemCount ?: 0
                        require(count > 0)
                        for (n in 0 until count.coerceAtMost(COUNT_LIMIT)) {
                            val item = clips?.getItemAt(n)
                            entries.add(textEntry(clipText(item)))
                        }
                        if (count > COUNT_LIMIT) entries.add(failure("Only the first 16 text entries were accepted. Share fewer items."))
                    }
                }
            } catch (_: Exception) {
                entries.add(failure("No supported shared text or readable file was supplied. Nothing was saved."))
            }
            val delivered = java.util.concurrent.CountDownLatch(1)
            main.post {
                inFlight--
                for (entry in entries) {
                    val size = (entry["bytes"] as? ByteArray)?.size ?: 0
                    if (pending.size >= COUNT_LIMIT || bytesHeld + size > TOTAL_LIMIT) rejectCapacity()
                    else { pending.addLast(entry); bytesHeld += size }
                }
                channel?.invokeMethod("sharesAvailable", null)
                delivered.countDown()
            }
            delivered.await()
        }
    }

    private fun rejectCapacity() {
        notice = "Shared draft inbox is full (16 entries / 24 MiB). Some new input was not accepted. Review or discard drafts, then share it again."
        channel?.invokeMethod("sharesAvailable", null)
    }
    private fun failure(message: String): Map<String, Any> = mapOf("id" to UUID.randomUUID().toString(), "error" to message)
    private fun clipText(item: android.content.ClipData.Item?): String? {
        val uri = item?.uri
        return item?.text?.toString() ?: uri?.takeIf { it.scheme == "http" || it.scheme == "https" }?.toString()
    }
    private fun textEntry(text: String?): Map<String, Any> {
        if (text == null || text.isEmpty()) return failure("No shared text was supplied. Nothing was saved.")
        val bytes = text.toByteArray(Charsets.UTF_8)
        if (bytes.size > TEXT_LIMIT) return failure("Shared text exceeds 2 MiB. Nothing was saved.")
        return mapOf("id" to UUID.randomUUID().toString(), "name" to "Shared text or address", "format" to "text", "bytes" to bytes)
    }
}
