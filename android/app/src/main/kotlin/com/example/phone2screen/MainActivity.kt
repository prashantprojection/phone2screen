package com.example.phone2screen

import android.content.Intent
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Main Flutter activity registering the native MethodChannel used to start and
 * stop [MediaProjectionService] around Android screen-capture sessions.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startService" -> startProjectionService(result)
                "stopService" -> {
                    stopService(Intent(this, MediaProjectionService::class.java))
                    result.success(true)
                }
                "getFilesDir" -> result.success(filesDir.absolutePath)
                else -> result.notImplemented()
            }
        }
    }

    private fun startProjectionService(result: MethodChannel.Result) {
        val intent = Intent(this, MediaProjectionService::class.java)
        try {
            // Must be called only after MediaProjection user consent on Android 14+.
            ContextCompat.startForegroundService(this, intent)
            result.success(true)
        } catch (e: SecurityException) {
            result.error("SECURITY_ERROR", e.message, null)
        } catch (e: IllegalStateException) {
            result.error("START_NOT_ALLOWED", e.message, null)
        }
    }

    companion object {
        private const val CHANNEL_NAME = "phone2screen/projection_service"
    }
}
