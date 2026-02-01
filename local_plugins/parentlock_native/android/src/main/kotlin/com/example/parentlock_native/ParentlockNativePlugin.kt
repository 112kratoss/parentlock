package com.example.parentlock_native

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.app.AppOpsManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/** ParentlockNativePlugin */
class ParentlockNativePlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "com.parentlock.parentlock/native")
        channel.setMethodCallHandler(this)
        context = flutterPluginBinding.applicationContext
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getUsageStats" -> {
                val stats = UsageStatsService.getUsageStats(context)
                result.success(stats)
            }
            "startMonitoringService" -> {
                val blockedApps = call.argument<List<String>>("blockedApps") ?: emptyList()
                MonitoringService.start(context, blockedApps)
                result.success(true)
            }
            "stopMonitoringService" -> {
                MonitoringService.stop(context)
                result.success(true)
            }
            "isMonitoringActive" -> {
                result.success(MonitoringService.isRunning())
            }
            "checkPermissions" -> {
                val hasUsageStats = hasUsageStatsPermission()
                val hasOverlay = hasOverlayPermission()
                val isIgnoringBattery = isIgnoringBatteryOptimizations()
                result.success(mapOf(
                    "usageStats" to hasUsageStats,
                    "overlay" to hasOverlay,
                    "batteryOptimization" to isIgnoringBattery,
                    "notification" to true 
                ))
            }
            "requestPermissions" -> {
                requestNecessaryPermissions()
                result.success(true)
            }
            "requestUsageStatsPermission" -> {
                requestUsageStatsPermission()
                result.success(true)
            }
            "requestOverlayPermission" -> {
                requestOverlayPermission()
                result.success(true)
            }
            "requestIgnoreBatteryOptimizations" -> {
                requestIgnoreBatteryOptimizations()
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
                val app = UsageStatsService.getCurrentForegroundApp(context)
                result.success(app)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    private fun hasUsageStatsPermission(): Boolean {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                context.packageName
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                context.packageName
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun hasOverlayPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(context)
        } else {
            true
        }
    }
    
    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
            return powerManager.isIgnoringBatteryOptimizations(context.packageName)
        }
        return true
    }

    private fun requestNecessaryPermissions() {
        requestUsageStatsPermission()
        
        if (!hasOverlayPermission() && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            requestOverlayPermission()
        }
    }

    private fun requestUsageStatsPermission() {
        val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }

    private fun requestOverlayPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val overlayIntent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:${context.packageName}")
            )
            overlayIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(overlayIntent)
        }
    }

    private fun requestIgnoreBatteryOptimizations() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !isIgnoringBatteryOptimizations()) {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
            intent.data = Uri.parse("package:${context.packageName}")
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
        }
    }
}
