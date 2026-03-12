package com.gargun.btktimetable

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.gargun.btktimetable/widget"
    private var appWidgetId = AppWidgetManager.INVALID_APPWIDGET_ID
    private var shouldOpenWidgetSettings = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "finishConfigure") {
                if (appWidgetId != AppWidgetManager.INVALID_APPWIDGET_ID) {
                    val resultValue = Intent().apply {
                        putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                    }
                    setResult(Activity.RESULT_OK, resultValue)
                    finish()
                    result.success(true)
                } else {
                    // If no ID, just finish (maybe re-configuring without ID, or testing)
                    finish()
                    result.success(false)
                }
            } else if (call.method == "getAppWidgetId") {
                 result.success(appWidgetId)
            } else if (call.method == "checkWidgetSettingsAction") {
                 result.success(shouldOpenWidgetSettings)
                 shouldOpenWidgetSettings = false
            } else if (call.method == "getWallpaper") {
                try {
                    val wallpaperManager = android.app.WallpaperManager.getInstance(context)
                    val drawable = wallpaperManager.drawable
                    if (drawable is android.graphics.drawable.BitmapDrawable) {
                        val bitmap = drawable.bitmap
                        val stream = java.io.ByteArrayOutputStream()
                        // Compress to JPEG with lower quality to save memory/bandwidth
                        bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, 50, stream)
                        result.success(stream.toByteArray())
                    } else {
                        result.error("UNAVAILABLE", "Wallpaper is not a bitmap", null)
                    }
                } catch (e: Exception) {
                    result.error("ERROR", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent) {
        if (AppWidgetManager.ACTION_APPWIDGET_CONFIGURE == intent.action) {
            val extras = intent.extras
            if (extras != null) {
                appWidgetId = extras.getInt(
                    AppWidgetManager.EXTRA_APPWIDGET_ID,
                    AppWidgetManager.INVALID_APPWIDGET_ID
                )
                android.util.Log.d("MainActivity", "Configuration started for widget ID: $appWidgetId")
                
                // Set RESULT_OK immediately so the widget is added even if the user backs out
                val resultValue = Intent().apply {
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                }
                setResult(Activity.RESULT_OK, resultValue)
                shouldOpenWidgetSettings = true
            }
        } else if ("com.gargun.btktimetable.ACTION_WIDGET_SETTINGS" == intent.action) {
             shouldOpenWidgetSettings = true
        }
    }
}
