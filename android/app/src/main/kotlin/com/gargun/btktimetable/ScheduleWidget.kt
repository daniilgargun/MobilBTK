package com.gargun.btktimetable

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin

class ScheduleWidget : AppWidgetProvider() {

    private companion object {
        const val ALARM_REQUEST_CODE = 2
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateScheduleWidget(context, appWidgetManager, appWidgetId)
        }
        // Перепланируем после системного обновления: будильники не переживают
        // перезагрузку устройства, а onUpdate после неё вызывается.
        WidgetUpdateScheduler.scheduleNext(
            context,
            ScheduleWidget::class.java,
            ALARM_REQUEST_CODE
        )
    }

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        WidgetUpdateScheduler.scheduleNext(
            context,
            ScheduleWidget::class.java,
            ALARM_REQUEST_CODE
        )
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        WidgetUpdateScheduler.cancel(
            context,
            ScheduleWidget::class.java,
            ALARM_REQUEST_CODE
        )
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)

        if (intent.action != WidgetUpdateScheduler.ACTION_AUTO_UPDATE) return

        val appWidgetManager = AppWidgetManager.getInstance(context)
        val componentName = ComponentName(context, ScheduleWidget::class.java)
        val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)

        for (appWidgetId in appWidgetIds) {
            updateScheduleWidget(context, appWidgetManager, appWidgetId)
        }
        appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetIds, R.id.widget_list)

        // Одноразовый будильник: сразу ставим следующий.
        WidgetUpdateScheduler.scheduleNext(
            context,
            ScheduleWidget::class.java,
            ALARM_REQUEST_CODE
        )
    }
}

internal fun updateScheduleWidget(
    context: Context,
    appWidgetManager: AppWidgetManager,
    appWidgetId: Int
) {
    val widgetData = HomeWidgetPlugin.getData(context)

    val date = widgetData.getString("schedule_date", "Загрузка…")
    val title = widgetData.getString("widget_title", "Мое расписание")

    val isDark = WidgetTheme.isDark(context)
    val transparency = WidgetTheme.transparency(context)

    val views = RemoteViews(context.packageName, R.layout.btk_widget_schedule)
    views.setTextViewText(R.id.widget_date, date)
    views.setTextViewText(R.id.widget_title, title)

    val primaryTextColor = WidgetTheme.primaryText(isDark)
    val secondaryTextColor = WidgetTheme.secondaryText(isDark)

    views.setTextColor(R.id.widget_title, primaryTextColor)
    views.setTextColor(R.id.widget_date, secondaryTextColor)
    views.setTextColor(R.id.empty_view, primaryTextColor)

    // Иконка обновления раньше никак не красилась и в светлой теме
    // сливалась с фоном.
    views.setInt(R.id.refresh_button, "setColorFilter", primaryTextColor)

    WidgetTheme.applyBackground(views, isDark, transparency)

    // Раньше виджет вообще не реагировал на нажатия: у кнопки обновления
    // не было обработчика, и открыть приложение с виджета было нельзя.
    val openApp = WidgetTheme.openAppIntent(context)
    views.setOnClickPendingIntent(R.id.refresh_button, openApp)
    views.setOnClickPendingIntent(R.id.widget_title, openApp)
    views.setOnClickPendingIntent(R.id.widget_date, openApp)
    views.setOnClickPendingIntent(R.id.empty_view, openApp)

    val intent = Intent(context, ScheduleWidgetService::class.java).apply {
        putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
        data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
    }
    views.setRemoteAdapter(R.id.widget_list, intent)
    views.setEmptyView(R.id.widget_list, R.id.empty_view)

    appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.widget_list)
    appWidgetManager.updateAppWidget(appWidgetId, views)
}
