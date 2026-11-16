package com.workwithafridi.google_photos_picker

import android.app.ActivityManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import java.net.HttpURLConnection
import java.net.URLEncoder
import java.net.URL
import java.nio.charset.StandardCharsets
import java.util.concurrent.Executors
import org.json.JSONObject

class GooglePhotosSessionMonitorService : Service() {
  private val executor = Executors.newSingleThreadExecutor()

  @Volatile private var activeSessionId: String? = null

  override fun onCreate() {
    super.onCreate()
    createNotificationChannel()
  }

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    val sessionId = intent?.getStringExtra(EXTRA_SESSION_ID) ?: return START_NOT_STICKY
    val headers = readHeaders(intent)
    val pollIntervalMillis = intent.getLongExtra(EXTRA_POLL_INTERVAL, 2_000L).coerceAtLeast(500L)
    val timeoutMillis = intent.getLongExtra(EXTRA_TIMEOUT, 600_000L).coerceAtLeast(1_000L)

    activeSessionId = sessionId
    startForeground(NOTIFICATION_ID, buildNotification())
    executor.execute {
      monitor(sessionId, headers, pollIntervalMillis, timeoutMillis)
    }
    return START_NOT_STICKY
  }

  override fun onDestroy() {
    activeSessionId = null
    executor.shutdownNow()
    super.onDestroy()
  }

  override fun onBind(intent: Intent?): IBinder? = null

  private fun monitor(
      sessionId: String,
      headers: Map<String, String>,
      pollIntervalMillis: Long,
      timeoutMillis: Long,
  ) {
    val deadline = System.currentTimeMillis() + timeoutMillis
    while (activeSessionId == sessionId && System.currentTimeMillis() < deadline) {
      try {
        Thread.sleep(pollIntervalMillis)
        if (activeSessionId != sessionId) return
        if (isSelectionComplete(sessionId, headers)) {
          activeSessionId = null
          restoreHostApp()
          stopForeground(STOP_FOREGROUND_REMOVE)
          stopSelf()
          return
        }
      } catch (_: InterruptedException) {
        Thread.currentThread().interrupt()
        return
      } catch (_: Exception) {
        // The Dart flow remains the source of errors. This native monitor is a
        // best-effort wake-up path and retries transient failures until timeout.
      }
    }
    if (activeSessionId == sessionId) {
      activeSessionId = null
      stopForeground(STOP_FOREGROUND_REMOVE)
      stopSelf()
    }
  }

  private fun isSelectionComplete(
      sessionId: String,
      headers: Map<String, String>,
  ): Boolean {
    val encodedSessionId =
        URLEncoder.encode(sessionId, StandardCharsets.UTF_8.name()).replace("+", "%20")
    val connection =
        URL("https://photospicker.googleapis.com/v1/sessions/$encodedSessionId")
            .openConnection() as HttpURLConnection
    try {
      connection.requestMethod = "GET"
      connection.connectTimeout = 8_000
      connection.readTimeout = 8_000
      headers.forEach { (name, value) -> connection.setRequestProperty(name, value) }
      if (connection.responseCode !in 200..299) return false
      val response = connection.inputStream.bufferedReader().use { it.readText() }
      return JSONObject(response).optBoolean("mediaItemsSet", false)
    } finally {
      connection.disconnect()
    }
  }

  private fun restoreHostApp() {
    val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
    activityManager.appTasks.firstOrNull {
      it.taskInfo.baseActivity?.packageName == packageName
    }?.moveToFront()

    packageManager.getLaunchIntentForPackage(packageName)?.apply {
      addFlags(
          Intent.FLAG_ACTIVITY_NEW_TASK or
              Intent.FLAG_ACTIVITY_CLEAR_TOP or
              Intent.FLAG_ACTIVITY_SINGLE_TOP or
              Intent.FLAG_ACTIVITY_REORDER_TO_FRONT,
      )
      startActivity(this)
    }
  }

  private fun createNotificationChannel() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    val manager = getSystemService(NotificationManager::class.java)
    manager.createNotificationChannel(
        NotificationChannel(
            NOTIFICATION_CHANNEL_ID,
            "Google Photos selection",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
          description = "Keeps the app ready while you select Google Photos"
          setShowBadge(false)
        },
    )
  }

  private fun buildNotification() =
      NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
          .setSmallIcon(
              applicationInfo.icon.takeIf { it != 0 } ?: android.R.drawable.ic_menu_gallery,
          )
          .setContentTitle("Selecting from Google Photos")
          .setContentText("The app will return when your selection is ready")
          .setCategory(NotificationCompat.CATEGORY_PROGRESS)
          .setOngoing(true)
          .setSilent(true)
          .build()

  private fun readHeaders(intent: Intent): Map<String, String> {
    val names = intent.getStringArrayExtra(EXTRA_HEADER_NAMES) ?: return emptyMap()
    val values = intent.getStringArrayExtra(EXTRA_HEADER_VALUES) ?: return emptyMap()
    return names.indices.associate { index -> names[index] to values.getOrElse(index) { "" } }
  }

  companion object {
    private const val EXTRA_SESSION_ID = "sessionId"
    private const val EXTRA_HEADER_NAMES = "headerNames"
    private const val EXTRA_HEADER_VALUES = "headerValues"
    private const val EXTRA_POLL_INTERVAL = "pollIntervalMillis"
    private const val EXTRA_TIMEOUT = "timeoutMillis"
    private const val NOTIFICATION_CHANNEL_ID = "google_photos_picker_session"
    private const val NOTIFICATION_ID = 734_681

    fun start(
        context: Context,
        sessionId: String,
        headers: Map<String, String>,
        pollIntervalMillis: Long,
        timeoutMillis: Long,
    ) {
      val intent = Intent(context, GooglePhotosSessionMonitorService::class.java).apply {
        putExtra(EXTRA_SESSION_ID, sessionId)
        putExtra(EXTRA_HEADER_NAMES, headers.keys.toTypedArray())
        putExtra(EXTRA_HEADER_VALUES, headers.values.toTypedArray())
        putExtra(EXTRA_POLL_INTERVAL, pollIntervalMillis)
        putExtra(EXTRA_TIMEOUT, timeoutMillis)
      }
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        context.startForegroundService(intent)
      } else {
        context.startService(intent)
      }
    }

    fun stop(context: Context) {
      context.stopService(Intent(context, GooglePhotosSessionMonitorService::class.java))
    }
  }
}
