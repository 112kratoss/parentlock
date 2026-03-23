package com.example.parentlock_native

import android.content.Context
import android.content.Intent
import android.app.admin.DevicePolicyManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
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
        BlockOverlayService.updateBlockedApps(MonitoringStateStore.getBlockedApps(context))
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getUsageStats" -> {
                // Offload to background thread to prevent UI blocking
                Thread {
                    val stats = UsageStatsService.getUsageStats(context)
                    android.os.Handler(android.os.Looper.getMainLooper()).post {
                        try {
                            result.success(stats)
                        } catch (e: Exception) {
                            // Channel might be closed
                        }
                    }
                }.start()
            }
            "getPlatformStatus" -> {
                result.success(getPlatformStatus())
            }
            "startMonitoringService" -> {
                val blockedApps = call.argument<List<String>>("blockedApps") ?: emptyList()
                MonitoringStateStore.setManualStopRequested(context, false)
                MonitoringStateStore.setMonitoringEnabled(context, true)
                MonitoringStateStore.saveBlockedApps(context, blockedApps)
                MonitoringStateStore.setTamperStatus(context, "healthy", null)
                BlockOverlayService.updateBlockedApps(blockedApps)
                BlockOverlayService.hideOverlay(context)
                MonitoringService.start(context, blockedApps)
                result.success(true)
            }
            "stopMonitoringService" -> {
                MonitoringStateStore.setManualStopRequested(context, true)
                MonitoringStateStore.setMonitoringEnabled(context, false)
                MonitoringStateStore.setTamperStatus(context, "healthy", null)
                BlockOverlayService.hideOverlay(context)
                MonitoringService.stop(context)
                result.success(true)
            }
            "configureMonitoringSession" -> {
                val childId = call.argument<String>("childId")
                val accessToken = call.argument<String>("accessToken")
                val refreshToken = call.argument<String>("refreshToken")
                val supabaseUrl = call.argument<String>("supabaseUrl")
                val supabaseAnonKey = call.argument<String>("supabaseAnonKey")

                if (childId.isNullOrBlank() ||
                    accessToken.isNullOrBlank() ||
                    supabaseUrl.isNullOrBlank() ||
                    supabaseAnonKey.isNullOrBlank()
                ) {
                    result.error("INVALID_ARGUMENT", "Missing monitoring session configuration", null)
                } else {
                    MonitoringStateStore.configureSession(
                        context = context,
                        childId = childId,
                        accessToken = accessToken,
                        refreshToken = refreshToken,
                        supabaseUrl = supabaseUrl,
                        supabaseAnonKey = supabaseAnonKey,
                    )
                    result.success(true)
                }
            }
            "recordPolicySync" -> {
                MonitoringStateStore.recordPolicySync(context, NativeSecurityUtils.nowIsoString())
                result.success(true)
            }
            "syncDeviceHealthNow" -> {
                DeviceHealthReporter.reportNow(
                    context = context,
                    monitoringActiveOverride = MonitoringService.isRunning(),
                )
                result.success(true)
            }
            "isMonitoringActive" -> {
                result.success(MonitoringService.isRunning())
            }
            "checkPermissions" -> {
                val hasUsageStats = NativeSecurityUtils.hasUsageStatsPermission(context)
                val hasOverlay = NativeSecurityUtils.hasOverlayPermission(context)
                val isIgnoringBattery = NativeSecurityUtils.isIgnoringBatteryOptimizations(context)
                result.success(mapOf(
                    "usageStats" to hasUsageStats,
                    "overlay" to hasOverlay,
                    "batteryOptimization" to isIgnoringBattery,
                    "notification" to NativeSecurityUtils.areNotificationsGranted(context)
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
            "requestDeviceAdmin" -> {
                requestDeviceAdmin()
                result.success(true)
            }
            "applyManagedDevicePolicies" -> {
                result.success(ManagedDeviceController.applyManagedDevicePolicies(context))
            }
            "blockApp" -> {
                val packageName = call.argument<String>("packageName")
                if (packageName != null) {
                    BlockOverlayService.addBlockedApp(packageName)
                    MonitoringStateStore.saveBlockedApps(context, BlockOverlayService.getBlockedApps())
                    result.success(true)
                } else {
                    result.error("INVALID_ARGUMENT", "Package name is required", null)
                }
            }
            "unblockApp" -> {
                val packageName = call.argument<String>("packageName")
                if (packageName != null) {
                    BlockOverlayService.removeBlockedApp(packageName)
                    MonitoringStateStore.saveBlockedApps(context, BlockOverlayService.getBlockedApps())
                    result.success(true)
                } else {
                    result.error("INVALID_ARGUMENT", "Package name is required", null)
                }
            }
            "updateBlockedApps" -> {
                val blockedApps = call.argument<List<String>>("blockedApps") ?: emptyList()
                BlockOverlayService.updateBlockedApps(blockedApps)
                MonitoringStateStore.saveBlockedApps(context, blockedApps)
                MonitoringStateStore.recordPolicySync(context, NativeSecurityUtils.nowIsoString())
                result.success(true)
            }
            "getCurrentForegroundApp" -> {
                // Also offload this as it queries usage stats
                Thread {
                    val app = UsageStatsService.getCurrentForegroundApp(context)
                    android.os.Handler(android.os.Looper.getMainLooper()).post {
                         try {
                            result.success(app)
                        } catch (e: Exception) {
                        }
                    }
                }.start()
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    private fun requestNecessaryPermissions() {
        requestUsageStatsPermission()
        
        if (!NativeSecurityUtils.hasOverlayPermission(context) &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.M
        ) {
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
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            !NativeSecurityUtils.isIgnoringBatteryOptimizations(context)
        ) {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
            intent.data = Uri.parse("package:${context.packageName}")
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
        }
    }

    private fun requestDeviceAdmin() {
        val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
            putExtra(
                DevicePolicyManager.EXTRA_DEVICE_ADMIN,
                ManagedDeviceController.adminComponent(context),
            )
            putExtra(
                DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                "ParentLock uses device admin to harden protection on child devices.",
            )
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
    }

    private fun getPlatformStatus(): Map<String, Any?> {
        val snapshot = DeviceHealthReporter.buildSnapshot(
            context = context,
            monitoringActiveOverride = MonitoringService.isRunning(),
        )

        return mapOf(
            "platform" to "android",
            "monitoringSupported" to true,
            "monitoringActive" to snapshot.monitoringActive,
            "enrollmentMode" to snapshot.enrollmentMode,
            "deviceOwner" to snapshot.deviceOwner,
            "tamperState" to snapshot.tamperState,
            "tamperReason" to snapshot.tamperReason,
            "lastHeartbeatAt" to (MonitoringStateStore.getLastHeartbeatAt(context) ?: snapshot.lastHeartbeatAt),
            "criticalPermissionsOk" to snapshot.criticalPermissionsOk,
            "usageStatsSupported" to true,
            "usageStatsGranted" to NativeSecurityUtils.hasUsageStatsPermission(context),
            "appBlockingSupported" to true,
            "overlayPermissionRequired" to true,
            "overlayGranted" to NativeSecurityUtils.hasOverlayPermission(context),
            "batteryOptimizationSupported" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M),
            "batteryOptimizationExempt" to NativeSecurityUtils.isIgnoringBatteryOptimizations(context),
            "familyControlsSupported" to false,
            "familyControlsAuthorized" to false,
            "notificationsGranted" to NativeSecurityUtils.areNotificationsGranted(context),
            "backgroundLocationSupported" to true,
        )
    }
}
