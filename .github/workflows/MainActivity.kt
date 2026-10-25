package com.studyblocker.study_blocker

import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "guard")
            .setMethodCallHandler { call, result ->
                val prefs = getSharedPreferences("guard", MODE_PRIVATE)
                when (call.method) {
                    "start" -> {
                        val now = System.currentTimeMillis()
                        val requested = call.argument<Number>("sessionEnd")?.toLong() ?: 0L
                        // Safety: kabhi bhi 4 ghante se zyada lock nahi
                        val end = minOf(requested, now + 4 * 3600_000L)
                        val channels = call.argument<List<String>>("channels") ?: emptyList()
                        val allowed = call.argument<List<String>>("allowed") ?: emptyList()
                        prefs.edit()
                            .putLong("session_end", end)
                            .putString("channels", channels.joinToString("\n"))
                            .putString("allowed", allowed.joinToString("\n"))
                            .apply()
                        result.success(true)
                    }
                    "isEnabled" -> result.success(isServiceEnabled())
                    "openSettings" -> {
                        startActivity(
                            Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                        result.success(true)
                    }
                    "getApps" -> result.success(listApps())
                    "getDebug" -> result.success(prefs.getString("debug_ids", "") ?: "")
                    else -> result.notImplemented()
                }
            }
    }

    private fun listApps(): List<Map<String, String>> {
        val pm = packageManager
        val i = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return pm.queryIntentActivities(i, 0)
            .map {
                mapOf(
                    "label" to it.loadLabel(pm).toString(),
                    "pkg" to it.activityInfo.packageName
                )
            }
            .filter { it["pkg"] != packageName }
            .distinctBy { it["pkg"] }
            .sortedBy { it["label"]!!.lowercase() }
    }

    private fun isServiceEnabled(): Boolean {
        val enabled = Settings.Secure.getString(
            contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        return enabled.contains("$packageName/${GuardService::class.java.name}")
    }
}
