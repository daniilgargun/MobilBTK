package com.gargun.btktimetable

import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray
import java.util.Calendar

class ScheduleWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return ScheduleRemoteViewsFactory(this.applicationContext)
    }
}

class ScheduleRemoteViewsFactory(private val context: Context) : RemoteViewsService.RemoteViewsFactory {
    private var scheduleItems: JSONArray = JSONArray()
    private var widgetColor: Int = android.graphics.Color.BLUE // Default fallback

    override fun onCreate() {}

    override fun onDataSetChanged() {
        val widgetData = HomeWidgetPlugin.getData(context)
        val jsonString = widgetData.getString("schedule_data", "[]")
        // Read widget color, default to Blue if not found (though Flutter sends int value)
        // Flutter Colors.blue.value is usually a large negative int (ARGB).
        try {
            widgetColor = widgetData.getInt("widget_color", android.graphics.Color.parseColor("#2196F3"))
        } catch (e: Exception) {
            widgetColor = widgetData.getLong("widget_color", android.graphics.Color.parseColor("#2196F3").toLong()).toInt()
        }

        android.util.Log.d("ScheduleWidgetService", "JSON Data: $jsonString")
        scheduleItems = try {
            JSONArray(jsonString)
        } catch (e: Exception) {
            android.util.Log.e("ScheduleWidgetService", "Error parsing JSON", e)
            JSONArray()
        }
        android.util.Log.d("ScheduleWidgetService", "Items count: ${scheduleItems.length()}")
    }

    override fun onDestroy() {}

    override fun getCount(): Int = scheduleItems.length()

    override fun getViewAt(position: Int): RemoteViews {
        android.util.Log.d("ScheduleWidgetService", "getViewAt: $position")
        val views = RemoteViews(context.packageName, R.layout.btk_widget_item)
        
        // Читаем настройки темы
        val widgetData = HomeWidgetPlugin.getData(context)
        val isDark = widgetData.getBoolean("widget_theme_dark", true)
        
        val primaryTextColor = if (isDark) android.graphics.Color.WHITE else android.graphics.Color.BLACK
        val secondaryTextColor = if (isDark) android.graphics.Color.parseColor("#CCFFFFFF") else android.graphics.Color.parseColor("#99000000")
        
        try {
            val item = scheduleItems.getJSONObject(position)
            
            val lessonNumber = item.optInt("lessonNumber")
            // Use time from JSON if available, otherwise fallback (though JSON should always have it now)
            var timeString = item.optString("time")
            if (timeString.isEmpty()) {
                timeString = getLessonTime(lessonNumber)
            }
            
            views.setTextViewText(R.id.lesson_number, lessonNumber.toString())
            views.setTextColor(R.id.lesson_number, primaryTextColor)
            
            views.setTextViewText(R.id.lesson_time, timeString)
            views.setTextColor(R.id.lesson_time, secondaryTextColor)
            
            views.setTextViewText(R.id.lesson_subject, item.optString("subject"))
            views.setTextColor(R.id.lesson_subject, primaryTextColor)
            
            val teacher = item.optString("teacher")
            val classroom = item.optString("classroom")
            val group = item.optString("group")
            val subgroup = item.optString("subgroup")
            
            views.setTextViewText(R.id.lesson_teacher, teacher)
            views.setTextColor(R.id.lesson_teacher, secondaryTextColor)
            
            // Group View
            if (group.isNotEmpty()) {
                views.setTextViewText(R.id.lesson_group, "Гр. $group")
                views.setTextColor(R.id.lesson_group, secondaryTextColor)
                views.setViewVisibility(R.id.lesson_group, android.view.View.VISIBLE)
            } else {
                 views.setViewVisibility(R.id.lesson_group, android.view.View.GONE)
            }

            // Subgroup View
            if (subgroup.isNotEmpty() && subgroup != "0") { // 0 usually means common group
                views.setTextViewText(R.id.lesson_subgroup, "($subgroup)")
                views.setTextColor(R.id.lesson_subgroup, secondaryTextColor)
                views.setViewVisibility(R.id.lesson_subgroup, android.view.View.VISIBLE)
            } else {
                 views.setViewVisibility(R.id.lesson_subgroup, android.view.View.GONE)
            }
            
            if (classroom.isNotEmpty()) {
                views.setTextViewText(R.id.lesson_room, "Каб. $classroom")
                views.setTextColor(R.id.lesson_room, secondaryTextColor)
                views.setViewVisibility(R.id.lesson_room, android.view.View.VISIBLE)
            } else {
                views.setViewVisibility(R.id.lesson_room, android.view.View.GONE)
            }
            
            // Highlight logic
            if (isCurrentLesson(timeString)) {
                // Apply transparency to widgetColor (e.g., 50% opacity)
                val alpha = 128 // 50% of 255
                val highlightColor = android.graphics.Color.argb(
                    alpha,
                    android.graphics.Color.red(widgetColor),
                    android.graphics.Color.green(widgetColor),
                    android.graphics.Color.blue(widgetColor)
                )
                views.setInt(R.id.item_background, "setColorFilter", highlightColor)
                views.setViewVisibility(R.id.item_background, android.view.View.VISIBLE)
                
                // Set text color to black for better contrast on highlight
                views.setTextColor(R.id.lesson_number, android.graphics.Color.BLACK)
                views.setTextColor(R.id.lesson_time, android.graphics.Color.BLACK)
                views.setTextColor(R.id.lesson_subject, android.graphics.Color.BLACK)
                views.setTextColor(R.id.lesson_teacher, android.graphics.Color.BLACK)
                views.setTextColor(R.id.lesson_group, android.graphics.Color.BLACK)
                views.setTextColor(R.id.lesson_subgroup, android.graphics.Color.BLACK)
                views.setTextColor(R.id.lesson_room, android.graphics.Color.BLACK)
            } else {
                views.setViewVisibility(R.id.item_background, android.view.View.INVISIBLE)
                
                // Revert text colors
                views.setTextColor(R.id.lesson_number, primaryTextColor)
                views.setTextColor(R.id.lesson_time, secondaryTextColor)
                views.setTextColor(R.id.lesson_subject, primaryTextColor)
                views.setTextColor(R.id.lesson_teacher, secondaryTextColor)
                views.setTextColor(R.id.lesson_group, secondaryTextColor)
                views.setTextColor(R.id.lesson_subgroup, secondaryTextColor)
                views.setTextColor(R.id.lesson_room, secondaryTextColor)
            }
            
        } catch (e: Exception) {
            android.util.Log.e("ScheduleWidgetService", "Error binding view at $position", e)
            e.printStackTrace()
        }
        return views
    }

    private fun getLessonTime(number: Int): String {
        return when (number) {
            1 -> "08:30 - 10:05"
            2 -> "10:25 - 12:00"
            3 -> "12:20 - 13:55"
            4 -> "14:15 - 15:50"
            5 -> "16:10 - 17:45"
            6 -> "18:00 - 19:35"
            else -> ""
        }
    }
    
    private fun isCurrentLesson(timeString: String): Boolean {
        if (timeString.isEmpty()) return false
        try {
            val parts = timeString.split(" - ")
            if (parts.size != 2) return false
            
            val startParts = parts[0].split(":")
            val endParts = parts[1].split(":")
            
            val startHour = startParts[0].toInt()
            val startMinute = startParts[1].toInt()
            
            val endHour = endParts[0].toInt()
            val endMinute = endParts[1].toInt()
            
            val now = Calendar.getInstance()
            val currentHour = now.get(Calendar.HOUR_OF_DAY)
            val currentMinute = now.get(Calendar.MINUTE)
            
            val currentTime = currentHour * 60 + currentMinute
            val startTime = startHour * 60 + startMinute
            val endTime = endHour * 60 + endMinute
            
            return currentTime >= startTime && currentTime < endTime
        } catch (e: Exception) {
            return false
        }
    }

    override fun getLoadingView(): RemoteViews? {
        // Return the same layout as the item, but with placeholders or empty
        return RemoteViews(context.packageName, R.layout.btk_widget_item)
    }
    override fun getViewTypeCount(): Int = 1
    override fun getItemId(position: Int): Long = position.toLong()
    override fun hasStableIds(): Boolean = true
}
