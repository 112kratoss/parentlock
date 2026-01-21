package com.parentlock.parentlock

import android.app.AppOpsManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.parentlock.parentlock/native"
    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getUsageStats" -> {
                    val stats = UsageStatsService.getUsageStats(this)
                    result.success(stats)
                }
                "startMonitoringService" -> {
                    val blockedApps = call.argument<List<String>>("blockedApps") ?: emptyList()
                    MonitoringService.start(this, blockedApps)
                    result.success(true)
                }
                "stopMonitoringService" -> {
                    MonitoringService.stop(this)
                    result.success(true)
                }
                "isMonitoringActive" -> {
                    result.success(MonitoringService.isRunning())
                }
                "checkPermissions" -> {
                    val hasUsageStats = hasUsageStatsPermission()
                    val hasOverlay = hasOverlayPermission()
                    result.success(mapOf(
                        "usageStats" to hasUsageStats,
                        "overlay" to hasOverlay,
                        "notification" to true // Auto-granted on runtime
                    ))
                }
                "requestPermissions" -> {
                    requestNecessaryPermissions()
                    result.success(true)
                }
                "blockApp" -> {
                    val packageName = call.argument<String>("packageName")
                    if (packageName != null) {
                        BlockOverlayService.addBlockedApp(packageName)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGUMENT", "Package name is required", null)
                    }
                }
                "unblockApp" -> {
                    val packageName = call.argument<String>("packageName")
                    if (packageName != null) {
                        BlockOverlayService.removeBlockedApp(packageName)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGUMENT", "Package name is required", null)
                    }
                }
                "updateBlockedApps" -> {
                    val blockedApps = call.argument<List<String>>("blockedApps") ?: emptyList()
                    BlockOverlayService.updateBlockedApps(blockedApps)
                    result.success(true)
                }
                "getCurrentForegroundApp" -> {
                    val app = UsageStatsService.getCurrentForegroundApp(this)
                    result.success(app)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun hasUsageStatsPermission(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                packageName
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                packageName
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun hasOverlayPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(this)
        } else {
            true
        }
    }

    private fun requestNecessaryPermissions() {
        // Request Usage Stats
        if (!hasUsageStatsPermission()) {
            val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
            intent.data = Uri.parse("package:$packageName")
            startActivity(intent)
        }
        
        // Request Overlay Permission
        if (!hasOverlayPermission() && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:$packageName")
            )
            startActivity(intent)
        }
    }
}
