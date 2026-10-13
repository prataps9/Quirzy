package com.ps9labs.quirzy

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews

class QuirzyWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        // There may be multiple widgets active, so update all of them
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
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

        val views = RemoteViews(context.packageName, R.layout.quirzy_widget)

        // The button and the header both open Practice.
        views.setOnClickPendingIntent(R.id.practice_button, pendingIntent)
        views.setOnClickPendingIntent(R.id.header_row, pendingIntent)

        appWidgetManager.updateAppWidget(appWidgetId, views)
    }
}
