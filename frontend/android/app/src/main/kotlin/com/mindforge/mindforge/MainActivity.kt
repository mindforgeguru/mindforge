package com.mindforge.mindforge

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the Flutter app and exposes screen-capture control to it.
 *
 * FLAG_SECURE blocks screenshots, screen recording, and the thumbnail Android
 * renders in the recents switcher. It is a *window* flag, not a view flag, so
 * there is no way to secure one widget — the Dart side turns it on when a
 * sensitive screen mounts and off when it leaves. See ScreenSecurity.
 *
 * Applied to the fee and grade screens only. Blanket-securing the app would
 * also stop a parent screenshotting a timetable to send to their partner,
 * which is ordinary use of a school app and not a threat.
 */
class MainActivity : FlutterActivity() {

    private val channel = "com.mindforge.mindforge/screen_security"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setSecure" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        // Window flags must be touched on the UI thread; the
                        // channel already delivers here, but runOnUiThread makes
                        // that explicit and is free if we are already on it.
                        runOnUiThread {
                            if (enabled) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            }
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
