package com.example.esp_scanner

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity: FlutterActivity() {
    private var espPlugin: EspNetworkPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        espPlugin = EspNetworkPlugin(this, flutterEngine.dartExecutor.binaryMessenger)
    }
}