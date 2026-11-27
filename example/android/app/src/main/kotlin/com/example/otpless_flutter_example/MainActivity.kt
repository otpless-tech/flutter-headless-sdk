package com.example.otpless_flutter_example

import android.os.Bundle
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterFragmentActivity() {

    // Extra engines spawned from the debug button; held so they stay alive.
    private val secondaryEngines = mutableListOf<FlutterEngine>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
    }

    // Reproduces the multi-engine setup (e.g. BigBasket): a second engine
    // registers every plugin, including OTPLESS, but its Dart side never sets
    // the OTPLESS callback handler. Responses must still reach the main engine.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "otpless_example/debug")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "spawnSecondaryEngine" -> {
                        // FlutterEngine auto-registers all plugins on construction.
                        val engine = FlutterEngine(applicationContext)
                        engine.dartExecutor.executeDartEntrypoint(
                            DartExecutor.DartEntrypoint(
                                FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                                "secondaryEngineMain"
                            )
                        )
                        secondaryEngines.add(engine)
                        Log.d("OtplessExample", "spawned secondary engine #${secondaryEngines.size}")
                        result.success(secondaryEngines.size)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        secondaryEngines.forEach { it.destroy() }
        secondaryEngines.clear()
        super.onDestroy()
    }
}
