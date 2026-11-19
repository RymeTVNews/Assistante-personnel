package com.sarra.sarra_assistante

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Après un redémarrage du téléphone, Sarra réarme les réveils qui n'étaient pas encore passés. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        val now = System.currentTimeMillis()
        for (item in AlarmStore.all(ctx)) {
            if (item.getLong("time") > now) AlarmStore.arm(ctx, item) else AlarmStore.remove(ctx, item.getInt("id"))
        }
    }
}
