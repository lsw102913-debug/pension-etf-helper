package com.antigravity.pension.pension_etf_helper

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import android.widget.Toast

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        // Wake up screen briefly if asleep
        try {
            val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            @Suppress("DEPRECATION")
            val wl = pm.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
                "pension_etf_helper:alarm_wakeup"
            )
            wl.acquire(10000L)
        } catch (_: Exception) {}

        Toast.makeText(
            context,
            "⏰ [연금모으기 예약 시간!] M-STOCK과 6종목 풀오토 리모컨을 실행합니다.",
            Toast.LENGTH_LONG
        ).show()

        val launchIntent = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            putExtra("auto_trigger", true)
        }

        try {
            context.startActivity(launchIntent)
        } catch (_: Exception) {
            // Post high-priority full-screen notification fallback
            showWakeupNotification(context, launchIntent)
        }
    }

    private fun showWakeupNotification(context: Context, launchIntent: Intent) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channelId = "pension_auto_alarm_ch"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "연금모으기 예약 자동실행",
                NotificationManager.IMPORTANCE_HIGH
            )
            nm.createNotificationChannel(channel)
        }
        val piFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pi = PendingIntent.getActivity(context, 777, launchIntent, piFlags)
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            android.app.Notification.Builder(context, channelId)
        } else {
            @Suppress("DEPRECATION")
            android.app.Notification.Builder(context)
        }
        builder.setSmallIcon(android.R.drawable.ic_popup_reminder)
            .setContentTitle("⏰ 연금모으기 6종목 주문 시간입니다!")
            .setContentText("터치하면 미니 리모컨과 미래에셋 M-STOCK이 즉시 실행됩니다.")
            .setContentIntent(pi)
            .setFullScreenIntent(pi, true)
            .setAutoCancel(true)
        nm.notify(777, builder.build())
    }
}
