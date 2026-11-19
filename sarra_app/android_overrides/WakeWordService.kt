package com.sarra.sarra_assistante

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import java.text.Normalizer

/**
 * Écoute en arrière-plan le mot d'éveil « Dis Sarra » (notification visible tant qu'elle est active).
 * Quand il est reconnu, Sarra s'ouvre, même téléphone verrouillé, et écoute Nathalie.
 * Reconnaissance sur l'appareil quand Android le permet (Android 12+ avec le pack de langue).
 */
class WakeWordService : Service() {
    companion object {
        const val NOTIF_ID = 4343
        const val CALL_NOTIF_ID = 4344
        const val CHANNEL = "sarra_ecoute"
        const val CHANNEL_CALL = "sarra_appel"
        private const val PREFS = "sarra_wake"

        @Volatile var instance: WakeWordService? = null
        @Volatile var running = false
        @Volatile var activityVisible = false

        fun isEnabled(ctx: Context): Boolean =
            ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean("enabled", false)

        fun setEnabled(ctx: Context, on: Boolean) {
            ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean("enabled", on).apply()
        }

        fun start(ctx: Context) {
            setEnabled(ctx, true)
            val i = Intent(ctx, WakeWordService::class.java)
            if (Build.VERSION.SDK_INT >= 26) ctx.startForegroundService(i) else ctx.startService(i)
        }

        fun stop(ctx: Context) {
            setEnabled(ctx, false)
            ctx.stopService(Intent(ctx, WakeWordService::class.java))
        }

        private val phrase = Regex("(^|\\s)(dis|dit|di|hey|he|ok|okay|salut|allo)\\s+(sarra|sara|sarah|sarrah|sarha|sahra)(\\s|$)")
        private val solo = Regex("^sarra(\\s|$)")

        fun matches(raw: String): Boolean {
            val t = Normalizer.normalize(raw.lowercase(), Normalizer.Form.NFD)
                .replace(Regex("\\p{Mn}+"), "").trim()
            return phrase.containsMatchIn(t) || solo.containsMatchIn(t)
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private var recognizer: SpeechRecognizer? = null
    private var paused = false
    private var onDevice = Build.VERSION.SDK_INT >= 31

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        running = true
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "STOP") {
            setEnabled(this, false)
            stopSelf()
            return START_NOT_STICKY
        }
        try {
            startAsForeground()
        } catch (e: Exception) {
            stopSelf()
            return START_NOT_STICKY
        }
        paused = activityVisible
        if (!paused) listen()
        return START_STICKY
    }

    override fun onDestroy() {
        instance = null
        running = false
        handler.removeCallbacksAndMessages(null)
        recognizer?.destroy()
        recognizer = null
        super.onDestroy()
    }

    /** Appelé par l'application quand elle passe au premier plan : le micro lui est laissé. */
    fun pause() {
        paused = true
        handler.removeCallbacksAndMessages(null)
        recognizer?.cancel()
        recognizer?.destroy()
        recognizer = null
    }

    /** Appelé quand l'application quitte l'écran : l'écoute du mot d'éveil reprend. */
    fun resume() {
        if (!paused) return
        paused = false
        handler.postDelayed({ if (!paused) listen() }, 800)
    }

    private fun startAsForeground() {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL, "Écoute de Sarra", NotificationManager.IMPORTANCE_LOW),
            )
        }
        val open = PendingIntent.getActivity(
            this, 1, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val stop = PendingIntent.getService(
            this, 2, Intent(this, WakeWordService::class.java).setAction("STOP"),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        @Suppress("DEPRECATION")
        val b = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else Notification.Builder(this)
        @Suppress("DEPRECATION")
        b.setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle("Sarra vous écoute")
            .setContentText("Dites « Dis Sarra » pour m'appeler")
            .setContentIntent(open)
            .setOngoing(true)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Arrêter", stop)
        val n = b.build()
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(NOTIF_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        } else {
            startForeground(NOTIF_ID, n)
        }
    }

    private fun again(ms: Long) {
        handler.postDelayed({ if (!paused) listen() }, ms)
    }

    private fun listen() {
        if (paused) return
        handler.removeCallbacksAndMessages(null)
        recognizer?.destroy()
        recognizer = null
        val r = try {
            if (onDevice && Build.VERSION.SDK_INT >= 31 && SpeechRecognizer.isOnDeviceRecognitionAvailable(this)) {
                SpeechRecognizer.createOnDeviceSpeechRecognizer(this)
            } else {
                onDevice = false
                SpeechRecognizer.createSpeechRecognizer(this)
            }
        } catch (e: Exception) {
            again(5000)
            return
        }
        recognizer = r
        r.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) {}
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB: Float) {}
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() {}
            override fun onEvent(eventType: Int, params: Bundle?) {}

            override fun onPartialResults(partialResults: Bundle?) = check(partialResults)

            override fun onResults(results: Bundle?) {
                if (!check(results) && !paused) again(300)
            }

            override fun onError(error: Int) {
                if (paused) return
                when (error) {
                    12, 13 -> { onDevice = false; again(300) } // pack de langue hors ligne absent : reconnaissance standard
                    9 -> { setEnabled(this@WakeWordService, false); stopSelf() } // micro refusé
                    8 -> again(1500)
                    1, 2, 4, 5 -> again(6000) // réseau, serveur ou client : on ralentit pour ménager la batterie
                    else -> again(300)
                }
            }
        })
        val i = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "fr-CA")
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, packageName)
        }
        try {
            r.startListening(i)
        } catch (e: Exception) {
            again(5000)
        }
    }

    /** Renvoie vrai si le mot d'éveil a été reconnu (et que Sarra a été appelée). */
    private fun check(b: Bundle?): Boolean {
        val list = b?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION) ?: return false
        if (list.any { matches(it) }) {
            trigger()
            return true
        }
        return false
    }

    private fun trigger() {
        pause()
        paused = true
        launchSarra()
    }

    private fun launchSarra() {
        val open = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            putExtra("sarra_wake", true)
            putExtra("id", 0)
            putExtra("label", "")
            putExtra("kind", "ecoute")
            putExtra("payload", "")
        }
        var started = false
        if (Settings.canDrawOverlays(this)) {
            try {
                startActivity(open)
                started = true
            } catch (_: Exception) {
            }
        }
        if (!started) postCallNotification(open)
        // Sécurité : si l'application ne s'est pas ouverte, l'écoute reprend.
        handler.postDelayed({
            if (!activityVisible) {
                paused = false
                listen()
            }
        }, 20000)
    }

    private fun postCallNotification(open: Intent) {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            val ch = NotificationChannel(CHANNEL_CALL, "Appel de Sarra", NotificationManager.IMPORTANCE_HIGH)
            ch.setSound(null, null)
            ch.lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            nm.createNotificationChannel(ch)
        }
        val pi = PendingIntent.getActivity(
            this, 3, open, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        @Suppress("DEPRECATION")
        val b = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL_CALL) else Notification.Builder(this)
        b.setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle("Sarra")
            .setContentText("Touchez pour parler à Sarra")
            .setCategory(Notification.CATEGORY_CALL)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setContentIntent(pi)
            .setFullScreenIntent(pi, true)
            .setAutoCancel(true)
        try {
            nm.notify(CALL_NOTIF_ID, b.build())
        } catch (_: SecurityException) {
        }
    }
}
