package dev.refract

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Entry point. Forwards content shared into REFRACT (ACTION_SEND, text/plain)
 * to the Flutter layer over the `dev.refract/shared` channel, where it enters
 * the Reality Compiler pipeline. No AccessibilityService, no VPN tricks —
 * only the OS-sanctioned share intent (spec §12).
 */
class MainActivity : FlutterActivity() {

    private val channelName = "dev.refract/shared"
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent?.action == Intent.ACTION_SEND && intent.type?.startsWith("text/") == true) {
            val text = intent.getStringExtra(Intent.EXTRA_TEXT)
            if (!text.isNullOrBlank()) {
                channel?.invokeMethod("sharedText", text)
            }
        }
    }
}
