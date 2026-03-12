package com.gargun.btktimetable

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import com.gargun.btktimetable.R
import java.util.Calendar
import org.json.JSONObject

class BellScheduleWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateBellScheduleWidget(context, appWidgetManager, appWidgetId)
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
        
        val action = intent.action
        
        if (action == "ACTION_AUTO_UPDATE") {
             val appWidgetManager = AppWidgetManager.getInstance(context)
             val componentName = ComponentName(context, BellScheduleWidgetProvider::class.java)
             val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)
             onUpdate(context, appWidgetManager, appWidgetIds)
             appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetIds, R.id.widget_grid)
        } else if (action == "ACTION_NEXT_PAGE" || action == "ACTION_PREV_PAGE") {
            val widgetData = HomeWidgetPlugin.getData(context)
            var pageIndex = widgetData.getInt("bell_schedule_page_index", 0)
            
            if (action == "ACTION_NEXT_PAGE") {
                pageIndex = (pageIndex + 1) % 4
            } else {
                pageIndex = (pageIndex - 1 + 4) % 4
            }
            
            val now = System.currentTimeMillis()
            widgetData.edit()
                .putInt("bell_schedule_page_index", pageIndex)
                .putLong("bell_schedule_last_manual_interaction", now)
                .apply()
            
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val componentName = ComponentName(context, BellScheduleWidgetProvider::class.java)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)
            
            onUpdate(context, appWidgetManager, appWidgetIds)
            appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetIds, R.id.widget_grid)
        }
    }

    private fun startAlarm(context: Context) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager
        val intent = Intent(context, BellScheduleWidgetProvider::class.java)
        intent.action = "ACTION_AUTO_UPDATE"
        val pendingIntent = PendingIntent.getBroadcast(context, 0, intent, PendingIntent.FLAG_IMMUTABLE)

        // Update every 1 minute to ensure accurate highlighting
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
        val intent = Intent(context, BellScheduleWidgetProvider::class.java)
        intent.action = "ACTION_AUTO_UPDATE"
        val pendingIntent = PendingIntent.getBroadcast(context, 0, intent, PendingIntent.FLAG_IMMUTABLE)
        alarmManager.cancel(pendingIntent)
    }
}

internal fun updateBellScheduleWidget(
    context: Context,
    appWidgetManager: AppWidgetManager,
    appWidgetId: Int
) {
    val widgetData = HomeWidgetPlugin.getData(context)
    
    // Theme settings
    val isDark = widgetData.getBoolean("widget_theme_dark", true)
    val transparency = widgetData.getInt("widget_transparency", 0)
    val pageIndex = widgetData.getInt("bell_schedule_page_index", 0)
    val views = RemoteViews(context.packageName, R.layout.bell_schedule_widget)
    
    // Auto-switch logic
    val lastManualTime = widgetData.getLong("bell_schedule_last_manual_interaction", 0L)
    val now = System.currentTimeMillis()
    
    // Check if manual interaction was on a different day
    val lastManualCalendar = Calendar.getInstance().apply { timeInMillis = lastManualTime }
    val currentCalendar = Calendar.getInstance().apply { timeInMillis = now }
    val isDifferentDay = lastManualCalendar.get(Calendar.DAY_OF_YEAR) != currentCalendar.get(Calendar.DAY_OF_YEAR) ||
                        lastManualCalendar.get(Calendar.YEAR) != currentCalendar.get(Calendar.YEAR)
    
    var effectivePageIndex = pageIndex
    if (lastManualTime == 0L || isDifferentDay) {
        effectivePageIndex = getAutoPageIndex(context)
        // Update stored index to match auto if it was reset
        if (effectivePageIndex != pageIndex) {
            widgetData.edit().putInt("bell_schedule_page_index", effectivePageIndex).apply()
        }
    }

    // Set Title based on Page Index
    val title = when (effectivePageIndex) {
        0 -> "Пн, Ср, Пт"
        1 -> "Вторник"
        2 -> "Четверг"
        3 -> "Суббота"
        else -> "Расписание"
    }
    
    views.setTextViewText(R.id.widget_title, title)
    
    // Theme
    val backgroundColor = if (isDark) android.graphics.Color.BLACK else android.graphics.Color.WHITE
    val textColor = if (isDark) android.graphics.Color.WHITE else android.graphics.Color.BLACK
    
    // Apply background transparency
    val alpha = ((100 - transparency) * 255 / 100).coerceIn(0, 255)
    val finalColor = android.graphics.Color.argb(
        alpha,
        android.graphics.Color.red(backgroundColor),
        android.graphics.Color.green(backgroundColor),
        android.graphics.Color.blue(backgroundColor)
    )
    
    views.setInt(R.id.widget_root, "setBackgroundColor", finalColor)
    views.setTextColor(R.id.widget_title, textColor)
    
    // Navigation Buttons
    val nextIntent = Intent(context, BellScheduleWidgetProvider::class.java).apply {
        action = "ACTION_NEXT_PAGE"
    }
    val nextPendingIntent = PendingIntent.getBroadcast(
        context, 0, nextIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )
    views.setOnClickPendingIntent(R.id.btn_next, nextPendingIntent)
    
    val prevIntent = Intent(context, BellScheduleWidgetProvider::class.java).apply {
        action = "ACTION_PREV_PAGE"
    }
    val prevPendingIntent = PendingIntent.getBroadcast(
        context, 1, prevIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )
    views.setOnClickPendingIntent(R.id.btn_prev, prevPendingIntent)
    

    

    
    // Grid Adapter
    val intent = Intent(context, BellScheduleWidgetService::class.java).apply {
        putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
        data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
    }
    views.setRemoteAdapter(R.id.widget_grid, intent)
    views.setEmptyView(R.id.widget_grid, R.id.empty_view)
    
    // Calculate scroll position
    val scrollPos = calculateScrollPosition(context, effectivePageIndex)
    if (scrollPos != -1) {
         // Try to scroll (API 31+)
         if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
             views.setScrollPosition(R.id.widget_grid, scrollPos)
         }
    }
    
    
    appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.widget_grid)
    appWidgetManager.updateAppWidget(appWidgetId, views)
}

private fun calculateScrollPosition(context: Context, pageIndex: Int): Int {
    try {
        val widgetData = HomeWidgetPlugin.getData(context)
        val templatesString = widgetData.getString("bell_schedule_templates", "{}")
        val templates = if (templatesString != null) JSONObject(templatesString) else JSONObject()
        
        val dayType = when (pageIndex) {
            0 -> "normal"
            1 -> "tuesday"
            2 -> "thursday"
            3 -> "saturday"
            else -> "normal"
        }
        
        val items = templates.optJSONArray(dayType) ?: return -1
        
        val now = Calendar.getInstance()
        val currentHour = now.get(Calendar.HOUR_OF_DAY)
        val currentMinute = now.get(Calendar.MINUTE)
        val currentTime = currentHour * 60 + currentMinute
        
        for (i in 0 until items.length()) {
            val item = items.getJSONObject(i)
            val start = item.getString("start")
            val end = item.getString("end")
            
            val startParts = start.split(":")
            val startHour = startParts[0].toInt()
            val startMinute = startParts[1].toInt()
            val startTime = startHour * 60 + startMinute
            
            val endParts = end.split(":")
            val endHour = endParts[0].toInt()
            val endMinute = endParts[1].toInt()
            val endTime = endHour * 60 + endMinute
            
            if (currentTime >= startTime && currentTime < endTime) {
                return i
            }
             if (currentTime < startTime) {
                return i
            }
        }
        return -1
    } catch (e: Exception) {
        return -1
    }
}

private fun getAutoPageIndex(context: Context): Int {
    val calendar = Calendar.getInstance()
    val dayOfWeek = calendar.get(Calendar.DAY_OF_WEEK)
    
    // Default mapping for today
    var (pageIndex, dayType) = when (dayOfWeek) {
        Calendar.MONDAY -> Pair(0, "normal")
        Calendar.TUESDAY -> Pair(1, "tuesday")
        Calendar.WEDNESDAY -> Pair(0, "normal")
        Calendar.THURSDAY -> Pair(2, "thursday")
        Calendar.FRIDAY -> Pair(0, "normal")
        Calendar.SATURDAY -> Pair(3, "saturday")
        else -> Pair(0, "normal") // Sunday/default
    }
    
    // If it's Sunday, just show Monday
    if (dayOfWeek == Calendar.SUNDAY) return 0
    
    // Check if classes for current day are over
    if (isDayFinished(context, dayType)) {
        // Flip to next academic day
        pageIndex = when (dayOfWeek) {
            Calendar.MONDAY -> 1 // Tuesday
            Calendar.TUESDAY -> 0 // Wednesday (normal)
            Calendar.WEDNESDAY -> 2 // Thursday
            Calendar.THURSDAY -> 0 // Friday (normal)
            Calendar.FRIDAY -> 3 // Saturday
            Calendar.SATURDAY -> 0 // Monday next week
            else -> 0
        }
    }
    
    return pageIndex
}

private fun isDayFinished(context: Context, dayType: String): Boolean {
    try {
        val widgetData = HomeWidgetPlugin.getData(context)
        val templatesString = widgetData.getString("bell_schedule_templates", "{}") ?: "{}"
        val templates = JSONObject(templatesString)
        val items = templates.optJSONArray(dayType) ?: return false
        
        if (items.length() == 0) return false
        
        val lastItem = items.getJSONObject(items.length() - 1)
        val end = lastItem.getString("end")
        val endParts = end.split(":")
        val endHour = endParts[0].trim().toInt()
        val endMinute = endParts[1].trim().toInt()
        val endTime = endHour * 60 + endMinute
        
        val now = Calendar.getInstance()
        val currentTime = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
        
        // Add 5 minutes buffer after classes end
        return currentTime >= (endTime + 5)
    } catch (e: Exception) {
        return false
    }
}
