package com.gargun.btktimetable

import android.appwidget.AppWidgetManager
import android.app.PendingIntent
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin

import android.content.ComponentName

class ScheduleWidget : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateScheduleWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        startAlarm(context)
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        stopAlarm(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        
        if (intent.action == "ACTION_AUTO_UPDATE") {
             val appWidgetManager = AppWidgetManager.getInstance(context)
             val componentName = ComponentName(context, ScheduleWidget::class.java)
             val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)
             
             for (appWidgetId in appWidgetIds) {
                 updateScheduleWidget(context, appWidgetManager, appWidgetId)
             }
             appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetIds, R.id.widget_list)
        }
    }

    private fun startAlarm(context: Context) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager
        val intent = Intent(context, ScheduleWidget::class.java).apply {
            action = "ACTION_AUTO_UPDATE"
        }
        val pendingIntent = PendingIntent.getBroadcast(
            context, 2, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Update every 1 minute
        val intervalMillis = 60 * 1000L 
        val triggerAtMillis = System.currentTimeMillis() + intervalMillis

        alarmManager.setRepeating(
            android.app.AlarmManager.RTC,
            triggerAtMillis,
            intervalMillis,
            pendingIntent
        )
    }

    private fun stopAlarm(context: Context) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager
        val intent = Intent(context, ScheduleWidget::class.java).apply {
            action = "ACTION_AUTO_UPDATE"
        }
        val pendingIntent = PendingIntent.getBroadcast(
            context, 2, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        alarmManager.cancel(pendingIntent)
    }
}

internal fun updateScheduleWidget(
    context: Context,
    appWidgetManager: AppWidgetManager,
    appWidgetId: Int
) {
    val widgetData = HomeWidgetPlugin.getData(context)
    
    val date = widgetData.getString("schedule_date", "Загрузка...")
    val title = widgetData.getString("widget_title", "Мое расписание")
    
    // Настройки темы
    val isDark = widgetData.getBoolean("widget_theme_dark", true)
    val transparency = widgetData.getInt("widget_transparency", 0)
    
    android.util.Log.d("ScheduleWidget", "Date: $date, Title: $title, Dark: $isDark, Trans: $transparency")
    
    val views = RemoteViews(context.packageName, R.layout.btk_widget_schedule)
    views.setTextViewText(R.id.widget_date, date)
    views.setTextViewText(R.id.widget_title, title)
    
    // Применяем цвета текста
    val primaryTextColor = if (isDark) android.graphics.Color.WHITE else android.graphics.Color.BLACK
    val secondaryTextColor = if (isDark) android.graphics.Color.parseColor("#AAFFFFFF") else android.graphics.Color.parseColor("#80000000")
    
    views.setTextColor(R.id.widget_date, primaryTextColor)
    views.setTextColor(R.id.widget_title, secondaryTextColor)
    views.setTextColor(R.id.empty_view, primaryTextColor)
    
    // Вычисляем цвет фона с прозрачностью
    val alpha = ((100 - transparency) * 255 / 100).toInt()
    val baseColor = if (isDark) android.graphics.Color.BLACK else android.graphics.Color.WHITE
    val backgroundColor = android.graphics.Color.argb(
        alpha,
        android.graphics.Color.red(baseColor),
        android.graphics.Color.green(baseColor),
        android.graphics.Color.blue(baseColor)
    )
    
    views.setInt(R.id.widget_root, "setBackgroundColor", backgroundColor)
    

    

    
    // Set up the collection
    val intent = Intent(context, ScheduleWidgetService::class.java).apply {
        putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
        data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
    }
    views.setRemoteAdapter(R.id.widget_list, intent)
    views.setEmptyView(R.id.widget_list, R.id.empty_view)

    appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.widget_list)
    appWidgetManager.updateAppWidget(appWidgetId, views)
}
