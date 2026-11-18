package com.lychnion.app

import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The Android version, so the app knows whether LiteRT-LM runs
        // (lib/llm/engines.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lychnion/device")
            .setMethodCallHandler { call, result ->
                if (call.method == "sdkInt") result.success(Build.VERSION.SDK_INT)
                else result.notImplemented()
            }
    }
}
