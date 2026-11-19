package com.sarra.sarra_assistante

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import org.json.JSONArray
import org.json.JSONObject

/** Réveils et rappels programmés par Sarra, conservés sur le téléphone et réarmés après un redémarrage. */
object AlarmStore {
    private const val PREFS = "sarra_alarms"
    private const val KEY = "items"

    fun newId(): Int = (System.currentTimeMillis() % 1_000_000_000L).toInt()

    private fun read(ctx: Context): JSONArray =
        JSONArray(ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, "[]"))

    private fun write(ctx: Context, items: List<JSONObject>) {
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(KEY, JSONArray(items).toString()).apply()
    }

    fun all(ctx: Context): List<JSONObject> {
        val arr = read(ctx)
        return (0 until arr.length()).map { arr.getJSONObject(it) }
    }

    fun get(ctx: Context, id: Int): JSONObject? = all(ctx).firstOrNull { it.getInt("id") == id }

    fun remove(ctx: Context, id: Int) = write(ctx, all(ctx).filter { it.getInt("id") != id })

    fun schedule(ctx: Context, id: Int, time: Long, label: String, kind: String, payload: String?) {
        val item = JSONObject().put("id", id).put("time", time).put("label", label).put("kind", kind)
        if (!payload.isNullOrEmpty()) item.put("payload", payload)
        write(ctx, all(ctx).filter { it.getInt("id") != id } + item)
        arm(ctx, item)
    }

    /** Alarme exacte « de type réveil » : elle sort le téléphone du mode veille et ne demande pas d'autorisation spéciale. */
    fun arm(ctx: Context, item: JSONObject) {
        val id = item.getInt("id")
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val show = PendingIntent.getActivity(
            ctx, id + 1_000_000_000, Intent(ctx, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        am.setAlarmClock(AlarmManager.AlarmClockInfo(item.getLong("time"), show), trigger(ctx, id))
    }

    fun cancel(ctx: Context, id: Int) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.cancel(trigger(ctx, id))
        remove(ctx, id)
    }

    private fun trigger(ctx: Context, id: Int): PendingIntent = PendingIntent.getBroadcast(
        ctx, id, Intent(ctx, AlarmReceiver::class.java).putExtra("id", id),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )
}
