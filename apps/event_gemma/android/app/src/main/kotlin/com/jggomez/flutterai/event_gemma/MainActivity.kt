package com.jggomez.flutterai.event_gemma

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.jggomez.flutterai.event_gemma/connectivity"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isWifiConnected" -> {
                    val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                    val activeNetwork = cm?.activeNetwork
                    val capabilities = if (activeNetwork != null) {
                        cm.getNetworkCapabilities(activeNetwork)
                    } else {
                        null
                    }
                    val hasWifi = capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
                    result.success(hasWifi)
                }
                else -> result.notImplemented()
            }
        }
    }
}
