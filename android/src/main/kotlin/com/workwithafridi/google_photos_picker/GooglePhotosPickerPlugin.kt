package com.workwithafridi.google_photos_picker

import android.app.Activity
import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class GooglePhotosPickerPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler {
  private var channel: MethodChannel? = null
  private var activity: Activity? = null
  private var applicationContext: Context? = null

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    applicationContext = binding.applicationContext
    channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME).also {
      it.setMethodCallHandler(this)
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel?.setMethodCallHandler(null)
    channel = null
    applicationContext = null
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "returnToApp" -> returnToApp(result)
      "startSessionMonitor" -> startSessionMonitor(call, result)
      "stopSessionMonitor" -> stopSessionMonitor(result)
      else -> result.notImplemented()
    }
  }

  private fun returnToApp(result: MethodChannel.Result) {
    val currentActivity = activity
    if (currentActivity == null) {
      result.success(false)
      return
    }

    currentActivity.runOnUiThread {
      try {
        val activityManager =
            currentActivity.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        activityManager.moveTaskToFront(currentActivity.taskId, 0)

        val intent = Intent(currentActivity, currentActivity.javaClass).apply {
          addFlags(
              Intent.FLAG_ACTIVITY_CLEAR_TOP or
                  Intent.FLAG_ACTIVITY_SINGLE_TOP or
                  Intent.FLAG_ACTIVITY_REORDER_TO_FRONT,
          )
        }
        currentActivity.startActivity(intent)
        result.success(true)
      } catch (_: Exception) {
        result.success(false)
      }
    }
  }

  private fun startSessionMonitor(call: MethodCall, result: MethodChannel.Result) {
    val context = applicationContext
    val sessionId = call.argument<String>("sessionId")
    val headers = call.argument<Map<String, String>>("headers")
    if (context == null || sessionId == null || headers == null) {
      result.error("invalid_arguments", "Session monitor arguments are missing.", null)
      return
    }
    GooglePhotosSessionMonitorService.start(
        context,
        sessionId,
        headers,
        call.argument<Number>("pollIntervalMillis")?.toLong() ?: 2_000L,
        call.argument<Number>("timeoutMillis")?.toLong() ?: 600_000L,
    )
    result.success(null)
  }

  private fun stopSessionMonitor(result: MethodChannel.Result) {
    applicationContext?.let { GooglePhotosSessionMonitorService.stop(it) }
    result.success(null)
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = binding.activity
  }

  override fun onDetachedFromActivityForConfigChanges() {
    activity = null
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    activity = binding.activity
  }

  override fun onDetachedFromActivity() {
    activity = null
  }

  private companion object {
    const val CHANNEL_NAME = "google_photos_picker/android"
  }
}
