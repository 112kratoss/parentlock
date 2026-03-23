package com.example.parentlock_native

import android.content.Context
import android.util.Log
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

object DeviceHealthReporter {
    data class Snapshot(
        val childId: String,
        val enrollmentMode: String,
        val tamperState: String,
        val tamperReason: String?,
        val lastHeartbeatAt: String,
        val lastServiceSeenAt: String?,
        val lastPolicySyncAt: String?,
        val lastPermissionSnapshot: JSONObject,
        val deviceOwner: Boolean,
        val criticalPermissionsOk: Boolean,
        val monitoringActive: Boolean,
        val appVersion: String,
    )

    fun reportNow(
        context: Context,
        monitoringActiveOverride: Boolean? = null,
        forcedTamperState: String? = null,
        forcedTamperReason: String? = null,
    ) {
        val snapshot = buildSnapshot(
            context = context,
            monitoringActiveOverride = monitoringActiveOverride,
            forcedTamperState = forcedTamperState,
            forcedTamperReason = forcedTamperReason,
        )

        MonitoringStateStore.setTamperStatus(
            context,
            snapshot.tamperState,
            snapshot.tamperReason,
        )

        val childId = MonitoringStateStore.getChildId(context)
        val accessToken = MonitoringStateStore.getAccessToken(context)
        val supabaseUrl = MonitoringStateStore.getSupabaseUrl(context)
        val supabaseAnonKey = MonitoringStateStore.getSupabaseAnonKey(context)

        if (childId.isNullOrBlank() ||
            accessToken.isNullOrBlank() ||
            supabaseUrl.isNullOrBlank() ||
            supabaseAnonKey.isNullOrBlank()
        ) {
            Log.w("DeviceHealthReporter", "Session config missing; skipping device health sync")
            return
        }

        Thread {
            try {
                val connection =
                    URL("$supabaseUrl/rest/v1/device_health?on_conflict=child_id")
                        .openConnection() as HttpURLConnection
                connection.requestMethod = "POST"
                connection.doOutput = true
                connection.setRequestProperty("Authorization", "Bearer $accessToken")
                connection.setRequestProperty("apikey", supabaseAnonKey)
                connection.setRequestProperty("Content-Type", "application/json")
                connection.setRequestProperty("Prefer", "resolution=merge-duplicates,return=minimal")

                val payload =
                    JSONObject()
                        .put("child_id", snapshot.childId)
                        .put("enrollment_mode", snapshot.enrollmentMode)
                        .put("tamper_state", snapshot.tamperState)
                        .put("tamper_reason", snapshot.tamperReason ?: JSONObject.NULL)
                        .put("last_heartbeat_at", snapshot.lastHeartbeatAt)
                        .put(
                            "last_service_seen_at",
                            snapshot.lastServiceSeenAt ?: JSONObject.NULL,
                        )
                        .put(
                            "last_policy_sync_at",
                            snapshot.lastPolicySyncAt ?: JSONObject.NULL,
                        )
                        .put("last_permission_snapshot", snapshot.lastPermissionSnapshot)
                        .put("device_owner", snapshot.deviceOwner)
                        .put("critical_permissions_ok", snapshot.criticalPermissionsOk)
                        .put("monitoring_active", snapshot.monitoringActive)
                        .put("app_version", snapshot.appVersion)

                OutputStreamWriter(connection.outputStream).use { writer ->
                    writer.write(payload.toString())
                }

                val responseCode = connection.responseCode
                if (responseCode in 200..299) {
                    MonitoringStateStore.setLastHeartbeatAt(context, snapshot.lastHeartbeatAt)
                } else {
                    Log.w(
                        "DeviceHealthReporter",
                        "Failed to sync device health. HTTP $responseCode",
                    )
                }
            } catch (error: Exception) {
                Log.e("DeviceHealthReporter", "Failed to sync device health", error)
            }
        }.start()
    }

    fun buildSnapshot(
        context: Context,
        monitoringActiveOverride: Boolean? = null,
        forcedTamperState: String? = null,
        forcedTamperReason: String? = null,
    ): Snapshot {
        val now = NativeSecurityUtils.nowIsoString()
        val deviceOwner = ManagedDeviceController.isDeviceOwner(context)
        val enrollmentMode = ManagedDeviceController.effectiveEnrollmentMode(context)
        val monitoringEnabled = MonitoringStateStore.isMonitoringEnabled(context)
        val monitoringActive = monitoringActiveOverride ?: MonitoringService.isRunning()
        val hasUsageStats = NativeSecurityUtils.hasUsageStatsPermission(context)
        val hasOverlay = NativeSecurityUtils.hasOverlayPermission(context)
        val batteryOptimizationExempt = NativeSecurityUtils.isIgnoringBatteryOptimizations(context)
        val notificationsGranted = NativeSecurityUtils.areNotificationsGranted(context)

        val criticalPermissionsOk =
            monitoringActive &&
                hasUsageStats &&
                hasOverlay &&
                batteryOptimizationExempt &&
                (enrollmentMode != "managed_device" || deviceOwner)

        val resolvedState =
            forcedTamperState
                ?: when {
                    !monitoringEnabled -> MonitoringStateStore.getTamperState(context)
                    enrollmentMode == "managed_device" && !deviceOwner ->
                        "tampered"

                    !monitoringActive -> "tampered"
                    !hasUsageStats -> "tampered"
                    !hasOverlay -> "tampered"
                    !batteryOptimizationExempt -> "tampered"
                    !notificationsGranted -> "degraded"
                    else -> "healthy"
                }

        val resolvedReason =
            forcedTamperReason
                ?: when (resolvedState) {
                    "tampered" ->
                        when {
                            enrollmentMode == "managed_device" && !deviceOwner ->
                                "Managed device control was removed."

                            !monitoringActive -> "Monitoring service was stopped."
                            !hasUsageStats -> "Usage access was revoked."
                            !hasOverlay -> "Overlay permission was revoked."
                            !batteryOptimizationExempt ->
                                "Battery optimization is stopping reliable monitoring."

                            else -> MonitoringStateStore.getTamperReason(context)
                        }

                    "degraded" ->
                        if (!notificationsGranted) {
                            "Notifications are disabled, so parent alerts may be delayed."
                        } else {
                            MonitoringStateStore.getTamperReason(context)
                        }

                    else -> null
                }

        val permissionSnapshot =
            JSONObject()
                .put("usageStatsGranted", hasUsageStats)
                .put("overlayGranted", hasOverlay)
                .put("batteryOptimizationExempt", batteryOptimizationExempt)
                .put("notificationsGranted", notificationsGranted)
                .put("deviceOwner", deviceOwner)
                .put("monitoringEnabled", monitoringEnabled)
                .put("monitoringActive", monitoringActive)
                .put("criticalPermissionsOk", criticalPermissionsOk)

        return Snapshot(
            childId = MonitoringStateStore.getChildId(context) ?: "",
            enrollmentMode = enrollmentMode,
            tamperState = resolvedState,
            tamperReason = resolvedReason,
            lastHeartbeatAt = now,
            lastServiceSeenAt = if (monitoringActive) now else null,
            lastPolicySyncAt = MonitoringStateStore.getLastPolicySyncAt(context),
            lastPermissionSnapshot = permissionSnapshot,
            deviceOwner = deviceOwner,
            criticalPermissionsOk = criticalPermissionsOk,
            monitoringActive = monitoringActive,
            appVersion = NativeSecurityUtils.appVersion(context),
        )
    }
}
