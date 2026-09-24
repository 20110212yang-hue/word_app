package com.example.word_app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class WordWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.widget_layout).apply {
                val word = widgetData.getString("widget_word", "Hej")
                val meaning = widgetData.getString("widget_meaning", "안녕하세요")

                setTextViewText(R.id.widget_word, word)
                setTextViewText(R.id.widget_meaning, meaning)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
