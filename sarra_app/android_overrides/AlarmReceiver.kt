package com.sarra.sarra_assistante

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build

/** Se déclenche à l'heure du réveil : sonnerie + ouverture de Sarra par-dessus l'écran verrouillé. */
class AlarmReceiver : BroadcastReceiver() {
    companion object {
        const val NOTIF_ID = 4242
        const val CHANNEL = "sarra_reveil"
    }

    override fun onReceive(ctx: Context, intent: Intent) {
        val id = intent.getIntExtra("id", -1)
        val item = AlarmStore.get(ctx, id) ?: return
        AlarmStore.remove(ctx, id)
        val label = item.optString("label", "")
        val kind = item.optString("kind", "reveil")
        val payload = item.optString("payload", "")

        val open = Intent(ctx, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            putExtra("sarra_wake", true)
            putExtra("id", id)
            putExtra("label", label)
            putExtra("kind", kind)
            putExtra("payload", payload)
        }
        val pi = PendingIntent.getActivity(ctx, id, open, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val alarmSound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= 26) {
            val ch = NotificationChannel(CHANNEL, "Réveils et rappels de Sarra", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Sarra vous réveille ou vous rappelle quelque chose à l'heure demandée"
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 600, 400, 600)
                setSound(
                    alarmSound,
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
            }
            nm.createNotificationChannel(ch)
        }

        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(ctx, CHANNEL) else Notification.Builder(ctx)
        builder
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(if (kind == "reveil") "Réveil — Sarra" else "Rappel — Sarra")
            .setContentText(if (label.isNotEmpty()) label else "Touchez pour parler à Sarra")
            .setCategory(Notification.CATEGORY_ALARM)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setContentIntent(pi)
            .setFullScreenIntent(pi, true)
            .setAutoCancel(true)
        if (Build.VERSION.SDK_INT < 26) {
            @Suppress("DEPRECATION")
            builder.setSound(alarmSound, android.media.AudioManager.STREAM_ALARM).setPriority(Notification.PRIORITY_MAX)
        }
        val n = builder.build()
        n.flags = n.flags or Notification.FLAG_INSISTENT
        try {
            nm.notify(NOTIF_ID, n)
        } catch (_: SecurityException) {
        }
        // Si l'autorisation des notifications manque, on tente quand même d'ouvrir Sarra directement.
        try {
            ctx.startActivity(open)
        } catch (_: Exception) {
        }
    }
}
