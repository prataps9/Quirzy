package com.ps9labs.quirzy

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews

/**
 * Home-screen widget: today's streak, answers and Daily 5 progress, with a
 * button into Practice. The app writes the numbers to its shared
 * preferences (keys `widget_*`) and asks for a refresh over the
 * `quirzy/widget` channel.
 */
class QuirzyWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    companion object {
        // Flutter's shared_preferences stores values here, keys prefixed
        // with "flutter." and ints as longs.
        private const val PREFS = "FlutterSharedPreferences"

        /** Redraws every Quirzy widget on the home screen. */
        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, QuirzyWidgetProvider::class.java))
            for (id in ids) {
                updateAppWidget(context, manager, id)
            }
        }

        private fun readInt(context: Context, key: String): Int {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            return try {
                prefs.getLong("flutter.$key", 0L).toInt()
            } catch (e: ClassCastException) {
                0
            }
        }

        private fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            // Open the app on the Practice tab: DeepLinkService handles quirzy://practice.
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse("quirzy://practice")).apply {
                setPackage(context.packageName)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
            val pendingIntent = PendingIntent.getActivity(
                context,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val streak = readInt(context, "widget_streak")
            val today = readInt(context, "widget_today")
            val goal = readInt(context, "widget_goal").takeIf { it > 0 } ?: 50
            val dailyDone = readInt(context, "widget_daily_done")
            val dailyTotal = readInt(context, "widget_daily_total")

            val views = RemoteViews(context.packageName, R.layout.quirzy_widget)
            views.setTextViewText(
                R.id.widget_subtitle,
                if (streak > 0) "$streak-day streak" else "Start your streak today"
            )
            val daily = when {
                dailyTotal <= 0 -> ""
                dailyDone >= dailyTotal -> " · Daily $dailyTotal done"
                else -> " · Daily $dailyTotal: $dailyDone of $dailyTotal"
            }
            views.setTextViewText(R.id.widget_stats, "$today/$goal today$daily")

            // The button and the header both open Practice.
            views.setOnClickPendingIntent(R.id.practice_button, pendingIntent)
            views.setOnClickPendingIntent(R.id.header_row, pendingIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
