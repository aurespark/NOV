package com.example.inkflow_reader

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.IBinder
import androidx.core.app.NotificationCompat

class DownloadForegroundService : Service() {
    override fun onCreate() {
        super.onCreate()
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel("web_download", "小說下載", NotificationManager.IMPORTANCE_LOW))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra("title") ?: "線上小說"
        val progress = intent?.getStringExtra("progress") ?: "準備下載"
        val notification = NotificationCompat.Builder(this, "web_download")
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(title)
            .setContentText(progress)
            .setOngoing(true)
            .build()
        startForeground(731, notification)
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
