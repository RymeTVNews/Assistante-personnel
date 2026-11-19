package com.sarra.sarra_assistante

import android.app.NotificationManager
import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.CalendarContract
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone

/** Passerelles vers le téléphone : calendrier, et réveils/rappels qui ouvrent Sarra écran verrouillé. */
class MainActivity : FlutterActivity() {
    private var alarmChannel: MethodChannel? = null
    private var pendingWake: Map<String, Any?>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }
        readWake(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        readWake(intent)
        pendingWake?.let {
            alarmChannel?.invokeMethod("wake", it)
            pendingWake = null
        }
    }

    private fun readWake(i: Intent?) {
        if (i != null && i.getBooleanExtra("sarra_wake", false)) {
            pendingWake = mapOf(
                "id" to i.getIntExtra("id", 0),
                "label" to (i.getStringExtra("label") ?: ""),
                "kind" to (i.getStringExtra("kind") ?: "reveil"),
                "payload" to (i.getStringExtra("payload") ?: ""),
            )
            i.removeExtra("sarra_wake")
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, "sarra/calendar").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "query" -> {
                        val start = (call.argument<Number>("start") ?: 0).toLong()
                        val end = (call.argument<Number>("end") ?: 0).toLong()
                        result.success(queryEvents(start, end))
                    }
                    "insert" -> {
                        val id = insertEvent(
                            call.argument<String>("title") ?: "Sans titre",
                            (call.argument<Number>("start") ?: 0).toLong(),
                            (call.argument<Number>("end") ?: 0).toLong(),
                            call.argument<String>("location"),
                            call.argument<String>("notes"),
                        )
                        result.success(id)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: SecurityException) {
                result.error("permission", e.message, null)
            } catch (e: Exception) {
                result.error("error", e.message, null)
            }
        }

        val ch = MethodChannel(messenger, "sarra/alarm")
        alarmChannel = ch
        ch.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "schedule" -> {
                        val id = AlarmStore.newId()
                        AlarmStore.schedule(
                            this, id,
                            (call.argument<Number>("time") ?: 0).toLong(),
                            call.argument<String>("label") ?: "",
                            call.argument<String>("kind") ?: "reveil",
                            call.argument<String>("payload"),
                        )
                        result.success(id)
                    }
                    "cancel" -> {
                        AlarmStore.cancel(this, (call.argument<Number>("id") ?: 0).toInt())
                        result.success(true)
                    }
                    "list" -> result.success(
                        AlarmStore.all(this).map {
                            mapOf(
                                "id" to it.getInt("id"),
                                "time" to it.getLong("time"),
                                "label" to it.optString("label"),
                                "kind" to it.optString("kind"),
                            )
                        },
                    )
                    "takeWake" -> {
                        val w = pendingWake
                        pendingWake = null
                        result.success(w)
                    }
                    "stopSound" -> {
                        (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).cancel(AlarmReceiver.NOTIF_ID)
                        result.success(true)
                    }
                    "fullScreenOk" -> {
                        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
                        result.success(if (Build.VERSION.SDK_INT >= 34) nm.canUseFullScreenIntent() else true)
                    }
                    "openFullScreenSettings" -> {
                        if (Build.VERSION.SDK_INT >= 34) {
                            startActivity(
                                Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, Uri.parse("package:$packageName")),
                            )
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("error", e.message, null)
            }
        }
    }

    private fun queryEvents(start: Long, end: Long): List<Map<String, Any?>> {
        val builder = CalendarContract.Instances.CONTENT_URI.buildUpon()
        ContentUris.appendId(builder, start)
        ContentUris.appendId(builder, end)
        val projection = arrayOf(
            CalendarContract.Instances.TITLE,
            CalendarContract.Instances.BEGIN,
            CalendarContract.Instances.END,
            CalendarContract.Instances.EVENT_LOCATION,
            CalendarContract.Instances.ALL_DAY,
        )
        val out = mutableListOf<Map<String, Any?>>()
        contentResolver.query(
            builder.build(), projection, null, null,
            "${CalendarContract.Instances.BEGIN} ASC",
        )?.use { c ->
            while (c.moveToNext() && out.size < 50) {
                out.add(
                    mapOf(
                        "title" to c.getString(0),
                        "begin" to c.getLong(1),
                        "end" to c.getLong(2),
                        "location" to c.getString(3),
                        "allDay" to (c.getInt(4) == 1),
                    ),
                )
            }
        }
        return out
    }

    private fun insertEvent(title: String, start: Long, end: Long, location: String?, notes: String?): Long {
        var calendarId: Long? = null
        contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            arrayOf(CalendarContract.Calendars._ID),
            "${CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL} >= ? AND ${CalendarContract.Calendars.VISIBLE} = 1",
            arrayOf(CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR.toString()),
            "${CalendarContract.Calendars.IS_PRIMARY} DESC",
        )?.use { c -> if (c.moveToFirst()) calendarId = c.getLong(0) }
        val calId = calendarId ?: throw IllegalStateException("Aucun calendrier modifiable trouvé sur le téléphone")

        val values = ContentValues().apply {
            put(CalendarContract.Events.CALENDAR_ID, calId)
            put(CalendarContract.Events.TITLE, title)
            put(CalendarContract.Events.DTSTART, start)
            put(CalendarContract.Events.DTEND, end)
            put(CalendarContract.Events.EVENT_TIMEZONE, TimeZone.getDefault().id)
            put(CalendarContract.Events.HAS_ALARM, 1)
            if (!location.isNullOrBlank()) put(CalendarContract.Events.EVENT_LOCATION, location)
            if (!notes.isNullOrBlank()) put(CalendarContract.Events.DESCRIPTION, notes)
        }
        val uri = contentResolver.insert(CalendarContract.Events.CONTENT_URI, values)
            ?: throw IllegalStateException("Impossible d'ajouter l'événement")
        val eventId = uri.lastPathSegment!!.toLong()

        val reminder = ContentValues().apply {
            put(CalendarContract.Reminders.EVENT_ID, eventId)
            put(CalendarContract.Reminders.MINUTES, 10)
            put(CalendarContract.Reminders.METHOD, CalendarContract.Reminders.METHOD_ALERT)
        }
        contentResolver.insert(CalendarContract.Reminders.CONTENT_URI, reminder)
        return eventId
    }
}
