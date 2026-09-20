package com.rtlsdrmobile.rtlsdr_mobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * Foreground service mínimo: existe só pra manter o processo do app vivo e
 * priorizado enquanto o streaming está ativo. O driver nativo
 * (rtlsdr_shim.c) já roda em threads POSIX próprias dentro do mesmo
 * processo — sem isso, o Android tende a congelar/matar o processo em
 * segundo plano (tela apagada, app fora de foco) e cortar o áudio no meio,
 * especialmente em fabricantes com gerenciamento agressivo de bateria.
 *
 * Iniciado/parado via MethodChannel (`rtlsdr/usb`) a partir dos hooks
 * onStreamingStarted/onStreamingStopped do RadioController do pacote
 * driver_rtlsdr (ver lib/app.dart) — ver MainActivity.kt.
 */
class StreamingService : Service() {

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, buildNotification())
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun buildNotification(): Notification {
        createNotificationChannelIfNeeded()

        val contentIntent = packageManager.getLaunchIntentForPackage(packageName)?.let {
            PendingIntent.getActivity(this, 0, it, PendingIntent.FLAG_IMMUTABLE)
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("RTL-SDR Mobile")
            .setContentText("Streaming ativo")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .build()
    }

    private fun createNotificationChannelIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Streaming de rádio",
            NotificationManager.IMPORTANCE_LOW,
        )
        manager.createNotificationChannel(channel)
    }

    companion object {
        private const val CHANNEL_ID = "rtlsdr_streaming"
        private const val NOTIFICATION_ID = 1
    }
}
