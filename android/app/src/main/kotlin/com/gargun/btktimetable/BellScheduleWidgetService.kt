package com.gargun.btktimetable

import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray
import org.json.JSONObject
import com.gargun.btktimetable.R
import java.util.*

class BellScheduleWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return BellScheduleRemoteViewsFactory(this.applicationContext)
    }
}

class BellScheduleRemoteViewsFactory(private val context: Context) : RemoteViewsService.RemoteViewsFactory {
    private var scheduleItems = ArrayList<BellScheduleItem>()
    private var isDark = true
    private var pageIndex = 0
    private var templates = JSONObject()
    private var widgetColor: Int = android.graphics.Color.BLUE

    data class BellScheduleItem(
        val type: String,
        val start: String,
        val end: String,
        val title: String,
        val number: String
    )

    override fun onCreate() {}

    override fun onDataSetChanged() {
        val widgetData = HomeWidgetPlugin.getData(context)
        isDark = widgetData.getBoolean("widget_theme_dark", true)
        pageIndex = widgetData.getInt("bell_schedule_page_index", 0)
        try {
            widgetColor = widgetData.getInt("widget_color", android.graphics.Color.parseColor("#2196F3"))
        } catch (e: Exception) {
            widgetColor = widgetData.getLong("widget_color", android.graphics.Color.parseColor("#2196F3").toLong()).toInt()
        }
        
        val templatesString = widgetData.getString("bell_schedule_templates", "{}")
        try {
            templates = if (templatesString != null) {
                JSONObject(templatesString)
            } else {
                JSONObject()
            }
        } catch (e: Exception) {
            templates = JSONObject()
        }
        
        val dayType = when (pageIndex) {
            0 -> "normal"
            1 -> "tuesday"
            2 -> "thursday"
            3 -> "saturday"
            else -> "normal"
        }
        
        val rawItems = templates.optJSONArray(dayType) ?: JSONArray()
        val newItems = ArrayList<BellScheduleItem>()
        
        for (i in 0 until rawItems.length()) {
            val item = rawItems.getJSONObject(i)
            val type = item.optString("type", "")
            // Filter out breaks, keep only lessons, special hours and dummy items
            if (type == "lesson" || type == "special" || type == "dummy") {
                newItems.add(BellScheduleItem(
                    type = type,
                    start = item.optString("start", ""),
                    end = item.optString("end", ""),
                    title = item.optString("title", ""),
                    number = item.optString("number", "")
                ))
            }
        }
        
        // Only update if we have data, or if it's explicitly empty (which shouldn't happen for valid days)
        // But to be safe, we just swap.
        scheduleItems = newItems
    }

    override fun onDestroy() {
        scheduleItems.clear()
    }

    override fun getCount(): Int {
        return scheduleItems.size
    }

    override fun getViewAt(position: Int): RemoteViews {
        if (position >= scheduleItems.size) return RemoteViews(context.packageName, R.layout.item_bell_schedule)

        val item = scheduleItems[position]

        if (item.type == "dummy") {
            // Use the dummy layout which is invisible but takes up space
            return RemoteViews(context.packageName, R.layout.item_bell_schedule_dummy)
        }

        val views = RemoteViews(context.packageName, R.layout.item_bell_schedule)
        
        try {
            views.setViewVisibility(R.id.item_root, View.VISIBLE)
            
            views.setTextViewText(R.id.lesson_number, item.number)
            views.setTextViewText(R.id.lesson_time, "${item.start} - ${item.end}")
            
            // Hide "Перемена" text or empty title
            if (item.title.isEmpty() || item.title.equals("Перемена", ignoreCase = true)) {
                views.setTextViewText(R.id.lesson_type, "")
                views.setViewVisibility(R.id.lesson_type, View.GONE)
            } else {
                views.setTextViewText(R.id.lesson_type, item.title)
                views.setViewVisibility(R.id.lesson_type, View.VISIBLE)
            }
            
            // Colors
            val primaryTextColor = if (isDark) android.graphics.Color.WHITE else android.graphics.Color.BLACK
            val secondaryTextColor = if (isDark) android.graphics.Color.parseColor("#AAFFFFFF") else android.graphics.Color.parseColor("#80000000")
            
            views.setTextColor(R.id.lesson_number, primaryTextColor)
            views.setTextColor(R.id.lesson_time, primaryTextColor)
            views.setTextColor(R.id.lesson_type, secondaryTextColor)
            
            // Highlight active item
            val calendar = Calendar.getInstance()
            val dayOfWeek = calendar.get(Calendar.DAY_OF_WEEK)
            
            val currentDayPageIndex = when (dayOfWeek) {
                Calendar.MONDAY, Calendar.WEDNESDAY, Calendar.FRIDAY -> 0
                Calendar.TUESDAY -> 1
                Calendar.THURSDAY -> 2
                Calendar.SATURDAY -> 3
                else -> 0 
            }
            
            var isActive = false
            if (pageIndex == currentDayPageIndex) {
                isActive = isTimeInRange(item.start, item.end)
            }
            
            if (isActive) {
                // Show rounded background
                views.setViewVisibility(R.id.item_background, View.VISIBLE)
                
                // Apply color to the background image
                // Use 50% opacity for highlight to make it more visible
                val alpha = 128 // 50% of 255
                val highlightColor = android.graphics.Color.argb(
                    alpha,
                    android.graphics.Color.red(widgetColor),
                    android.graphics.Color.green(widgetColor),
                    android.graphics.Color.blue(widgetColor)
                )
                
                views.setInt(R.id.item_background, "setColorFilter", highlightColor)
                
                // Set text color to BLACK for better contrast on colored background
                views.setTextColor(R.id.lesson_number, android.graphics.Color.BLACK)
                views.setTextColor(R.id.lesson_time, android.graphics.Color.BLACK)
                views.setTextColor(R.id.lesson_type, android.graphics.Color.BLACK)
            } else {
                views.setViewVisibility(R.id.item_background, View.INVISIBLE)
                
                // Revert to theme colors
                views.setTextColor(R.id.lesson_number, primaryTextColor)
                views.setTextColor(R.id.lesson_time, primaryTextColor)
                views.setTextColor(R.id.lesson_type, secondaryTextColor)
            }
            
        } catch (e: Exception) {
            e.printStackTrace()
        }
        
        return views
    }
    
    private fun isTimeInRange(start: String, end: String): Boolean {
        try {
            val now = Calendar.getInstance()
            val currentHour = now.get(Calendar.HOUR_OF_DAY)
            val currentMinute = now.get(Calendar.MINUTE)
            val currentTime = currentHour * 60 + currentMinute
            
            val startParts = start.split(":")
            val startHour = startParts[0].toInt()
            val startMinute = startParts[1].toInt()
            val startTime = startHour * 60 + startMinute
            
            val endParts = end.split(":")
            val endHour = endParts[0].toInt()
            val endMinute = endParts[1].toInt()
            val endTime = endHour * 60 + endMinute
            
            return currentTime >= startTime && currentTime < endTime
        } catch (e: Exception) {
            return false
        }
    }

    override fun getLoadingView(): RemoteViews? = null
    override fun getViewTypeCount(): Int = 2 // Normal and Dummy
    override fun getItemId(position: Int): Long = position.toLong()
    override fun hasStableIds(): Boolean = true
}
