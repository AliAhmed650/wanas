package com.aliahmed.wanas

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannels()
    }

    // قنوات الإشعارات: "messages" للرسائل، و"calls" للمكالمات (برنجتون واهتزاز).
    // اسم القناة لازم يتطابق مع channelId اللي السيرفر بيبعته (server/api/notify.js)
    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(NotificationManager::class.java) ?: return

        val messages = NotificationChannel(
            "messages", "الرسائل", NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "إشعارات الرسائل الجديدة"
        }

        val ringtone = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIC)
            .build()
        val calls = NotificationChannel(
            "calls", "المكالمات", NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "إشعارات المكالمات الواردة"
            setSound(ringtone, attrs)
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 800, 500, 800, 500, 800)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }

        nm.createNotificationChannels(listOf(messages, calls))
    }
}
