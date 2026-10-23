package com.example.moodle_reminder

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.text.format.DateFormat
import java.util.Date
import android.content.Context
import android.content.res.Configuration
import java.util.Locale
import android.content.Intent
import android.widget.RemoteViews

class MoodleWidgetProvider : AppWidgetProvider() {
    companion object {
        fun updateDeadline(context: Context, title: String, due: Long, language: String) {
            context.getSharedPreferences("widget_data", Context.MODE_PRIVATE)
                .edit().putString("title", title).putLong("due", due)
                .putString("language", if (language == "ar") "ar" else "en").apply()
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, MoodleWidgetProvider::class.java))
            MoodleWidgetProvider().onUpdate(context, manager, ids)
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: return
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val pendingIntent = PendingIntent.getActivity(
            context,
            0,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.moodle_home_widget)
            val preferences = context.getSharedPreferences("widget_data", Context.MODE_PRIVATE)
            val title = preferences.getString("title", "") ?: ""
            val due = preferences.getLong("due", 0L)
            val language = preferences.getString("language", "en") ?: "en"
            val localizedConfiguration = Configuration(context.resources.configuration).apply {
                setLocale(Locale.forLanguageTag(if (language == "ar") "ar" else "en"))
            }
            val localizedContext = context.createConfigurationContext(localizedConfiguration)
            val summary = if (title.isNotEmpty() && due >= System.currentTimeMillis()) {
                "$title · ${DateFormat.getMediumDateFormat(localizedContext).format(Date(due))}"
            } else {
                localizedContext.getString(R.string.widget_no_upcoming)
            }
            views.setTextViewText(R.id.widget_summary, summary)
            views.setOnClickPendingIntent(R.id.widget_container, pendingIntent)
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
