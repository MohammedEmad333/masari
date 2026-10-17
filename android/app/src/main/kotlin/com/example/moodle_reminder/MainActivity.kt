package com.example.moodle_reminder

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingCourseLink: String? = null
    private var courseChannel: MethodChannel? = null

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleCourseLink(intent)
    }

    private fun handleCourseLink(intent: Intent?) {
        val uri = intent?.data
        if (intent?.action == Intent.ACTION_VIEW && uri?.scheme == "moodlereminder" && uri.host == "course") {
            pendingCourseLink = uri.toString()
            courseChannel?.invokeMethod("courseLink", pendingCourseLink)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        handleCourseLink(intent)
        courseChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "moodle_reminder/course_share")
        courseChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "consumeLink" -> {
                    result.success(pendingCourseLink)
                    pendingCourseLink = null
                }
                "shareLink" -> {
                    val link = call.argument<String>("url")
                    if (link == null || !link.startsWith("moodlereminder://course?")) {
                        result.error("INVALID_LINK", "Invalid course link", null)
                    } else {
                        val send = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_TEXT, link)
                        }
                        startActivity(Intent.createChooser(send, "Share course"))
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
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
