package com.example.moodle_reminder

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "moodle_reminder/home_widget")
            .setMethodCallHandler { call, result ->
                if (call.method == "updateDeadline") {
                    val title = call.argument<String>("title") ?: ""
                    val due = call.argument<Number>("due")?.toLong() ?: 0L
                    MoodleWidgetProvider.updateDeadline(applicationContext, title, due)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }
}
