package com.example.inkflow_reader

import android.content.Intent
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "inkflow/download_service")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        val intent = Intent(this, DownloadForegroundService::class.java)
                            .putExtra("title", call.argument<String>("title"))
                            .putExtra("progress", call.argument<String>("progress"))
                        ContextCompat.startForegroundService(this, intent)
                        result.success(null)
                    }
                    "stop" -> { stopService(Intent(this, DownloadForegroundService::class.java)); result.success(null) }
                    else -> result.notImplemented()
                }
            }
    }
}
