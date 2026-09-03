package com.gargun.btktimetable

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import java.util.Calendar
import org.json.JSONObject

/**
 * Общие для обоих виджетов вещи: тема, фон и планирование обновлений.
 */
object WidgetTheme {

    fun isDark(context: Context): Boolean =
        HomeWidgetPlugin.getData(context).getBoolean("widget_theme_dark", true)

    fun transparency(context: Context): Int =
        HomeWidgetPlugin.getData(context).getInt("widget_transparency", 0)

    fun primaryText(isDark: Boolean): Int = if (isDark) Color.WHITE else Color.BLACK

    fun secondaryText(isDark: Boolean): Int =
        if (isDark) Color.parseColor("#CCFFFFFF") else Color.parseColor("#99000000")

    /**
     * Цвет акцента, выбранный пользователем в приложении.
     *
     * Flutter присылает ARGB как int; значения больше Int.MAX приходят как
     * Long, поэтому нужны обе ветки.
     */
    fun accentColor(context: Context): Int {
        val data = HomeWidgetPlugin.getData(context)
        val fallback = Color.parseColor("#2196F3")
        return try {
            data.getInt("widget_color", fallback)
        } catch (e: ClassCastException) {
            data.getLong("widget_color", fallback.toLong()).toInt()
        }
    }

    /**
     * Красит подложку виджета.
     *
     * Важно: цвет накладывается фильтром на ImageView, а не через
     * setBackgroundColor у корневого контейнера. setBackgroundColor заменяет
     * drawable сплошной заливкой и стирает скругление углов.
     */
    fun applyBackground(views: RemoteViews, isDark: Boolean, transparency: Int) {
        val base = if (isDark) Color.parseColor("#1E1E1E") else Color.WHITE
        val alpha = ((100 - transparency) * 255 / 100).coerceIn(0, 255)

        views.setInt(R.id.widget_background, "setColorFilter", base)
        views.setInt(R.id.widget_background, "setImageAlpha", alpha)
    }

    /** Открывает приложение по нажатию на виджет. */
    fun openAppIntent(context: Context, requestCode: Int = 0): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
}

/**
 * Планировщик обновлений виджетов.
 *
 * Раньше оба виджета держали повторяющийся будильник раз в минуту — 1440
 * пробуждений в сутки на виджет только ради подсветки текущей пары.
 * Подсветка меняется лишь на границах пар и перемен, поэтому теперь
 * ставится одноразовый будильник ровно на ближайшую такую границу,
 * который после срабатывания планирует следующий. Это и точнее
 * (подсветка переключается вовремя, а не с задержкой до интервала),
 * и в разы экономнее: около 25 срабатываний за учебный день вместо 1440.
 *
 * Используется неточный AlarmManager.set: точные будильники на Android 12+
 * требуют разрешения SCHEDULE_EXACT_ALARM, которое Google Play разрешает
 * только будильникам и календарям. Система может сдвинуть срабатывание,
 * но пока экран активен сдвиг незначителен.
 */
object WidgetUpdateScheduler {

    const val ACTION_AUTO_UPDATE = "ACTION_AUTO_UPDATE"

    /** Запасной интервал, если расписание звонков ещё не пришло из Flutter. */
    private const val FALLBACK_DELAY_MILLIS = 15 * 60 * 1000L

    fun scheduleNext(context: Context, provider: Class<*>, requestCode: Int) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE)
            as android.app.AlarmManager

        val triggerAt = nextBoundaryMillis(context)

        alarmManager.set(
            android.app.AlarmManager.RTC,
            triggerAt,
            pendingIntent(context, provider, requestCode)
        )
    }

    fun cancel(context: Context, provider: Class<*>, requestCode: Int) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE)
            as android.app.AlarmManager
        alarmManager.cancel(pendingIntent(context, provider, requestCode))
    }

    private fun pendingIntent(
        context: Context,
        provider: Class<*>,
        requestCode: Int
    ): PendingIntent {
        val intent = Intent(context, provider).apply { action = ACTION_AUTO_UPDATE }
        return PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    /**
     * Момент ближайшей границы пары или перемены. Если границ на сегодня
     * больше нет — начало следующего дня.
     */
    private fun nextBoundaryMillis(context: Context): Long {
        val now = Calendar.getInstance()
        val nowMinutes = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)

        val boundaries = todayBoundaries(context)
        val next = boundaries.firstOrNull { it > nowMinutes }

        if (next == null) {
            // Границ на сегодня не осталось: просыпаемся в начале следующего дня.
            val tomorrow = Calendar.getInstance().apply {
                add(Calendar.DAY_OF_YEAR, 1)
                set(Calendar.HOUR_OF_DAY, 7)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            return tomorrow.timeInMillis
        }

        val target = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, next / 60)
            set(Calendar.MINUTE, next % 60)
            set(Calendar.SECOND, 5)
            set(Calendar.MILLISECOND, 0)
        }

        // Защита от вырожденного случая, когда цель оказалась в прошлом.
        if (target.timeInMillis <= System.currentTimeMillis()) {
            return System.currentTimeMillis() + FALLBACK_DELAY_MILLIS
        }
        return target.timeInMillis
    }

    /** Все моменты начала и конца пар на сегодня, по возрастанию. */
    private fun todayBoundaries(context: Context): List<Int> {
        return try {
            val raw = HomeWidgetPlugin.getData(context)
                .getString("bell_schedule_templates", "{}") ?: "{}"
            val templates = JSONObject(raw)
            val items = templates.optJSONArray(todayDayType()) ?: return emptyList()

            val result = sortedSetOf<Int>()
            for (i in 0 until items.length()) {
                val item = items.getJSONObject(i)
                parseMinutesOfDay(item.optString("start"))?.let { result.add(it) }
                parseMinutesOfDay(item.optString("end"))?.let { result.add(it) }
            }
            result.toList()
        } catch (e: Exception) {
            emptyList()
        }
    }

    private fun todayDayType(): String = when (Calendar.getInstance()
        .get(Calendar.DAY_OF_WEEK)) {
        Calendar.TUESDAY -> "tuesday"
        Calendar.THURSDAY -> "thursday"
        Calendar.SATURDAY -> "saturday"
        else -> "normal"
    }
}

/**
 * Разбирает "14:10" в количество минут от полуночи.
 * Возвращает null, если строка пустая или не является временем
 * (например, у элементов-распорок сетки).
 */
fun parseMinutesOfDay(value: String?): Int? {
    if (value.isNullOrBlank()) return null
    val parts = value.split(":")
    if (parts.size != 2) return null
    val hour = parts[0].trim().toIntOrNull() ?: return null
    val minute = parts[1].trim().toIntOrNull() ?: return null
    if (hour !in 0..23 || minute !in 0..59) return null
    return hour * 60 + minute
}
