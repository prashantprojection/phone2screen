package com.example.phone2screen

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * Foreground service keeping Android's MediaProjection screen-capture session
 * alive while Phone2Screen streams the device display over WebRTC.
 *
 * Android 14+ (API 34+) enforces strict ordering for `mediaProjection`
 * foreground services: [startForeground] with
 * [ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION] MUST ONLY be called
 * AFTER the user grants screen-capture consent via
 * `MediaProjectionManager.createScreenCaptureIntent()` (triggered from Dart
 * via `Helper.requestCapturePermission()`). Starting this service before
 * user consent causes Android 14+ to throw `SecurityException` or
 * `MissingForegroundServiceTypeException`.
 */
class MediaProjectionService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP || intent?.action == ACTION_STOP_SCOPED) {
            stopForegroundCompat()
            stopSelf()
            return START_NOT_STICKY
        }

        ensureNotificationChannel()
        val notification = buildNotification()

        try {
            // API 29+ requires passing the mediaProjection foreground service type
            // explicitly to startForeground; older APIs use the 2-arg overload.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: SecurityException) {
            // Happens on Android 14+ if consent was not yet granted, revoked,
            // or the service was restarted unexpectedly without a valid token.
            Log.w(TAG, "Cannot start mediaProjection foreground service", e)
            stopForegroundCompat()
            stopSelf()
        } catch (e: IllegalStateException) {
            Log.w(TAG, "Foreground service start not allowed in current state", e)
            stopSelf()
        }

        // Do not auto-restart via START_STICKY: an OS restart with a null intent
        // has no active MediaProjection consent token and would fail on Android 14+.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        stopForegroundCompat()
        super.onDestroy()
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return

        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Persistent notification shown during screen sharing"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Phone2Screen")
            .setContentText("Phone2Screen is sharing your screen")
            .setSmallIcon(android.R.drawable.ic_menu_share)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()

    private fun stopForegroundCompat() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (e: SecurityException) {
            Log.w(TAG, "Ignored SecurityException while stopping foreground service", e)
        }
    }

    companion object {
        private const val TAG = "MediaProjectionService"
        const val CHANNEL_ID = "phone2screen_projection"
        private const val CHANNEL_NAME = "Screen Sharing"
        private const val NOTIFICATION_ID = 4102
        const val ACTION_STOP = "ACTION_STOP"
        private const val ACTION_STOP_SCOPED = "com.example.phone2screen.ACTION_STOP"
    }
}
