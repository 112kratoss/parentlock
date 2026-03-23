package com.example.parentlock_native

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

class BootCompletedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        when (intent?.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_LOCKED_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                if (!MonitoringStateStore.isMonitoringEnabled(context)) {
                    return
                }

                ManagedDeviceController.applyManagedDevicePolicies(context)

                val blockedApps = MonitoringStateStore.getBlockedApps(context)
                BlockOverlayService.updateBlockedApps(blockedApps)

                val serviceIntent = Intent(context, MonitoringService::class.java).apply {
                    putStringArrayListExtra("blockedApps", ArrayList(blockedApps))
                }

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(serviceIntent)
                } else {
                    context.startService(serviceIntent)
                }
            }
        }
    }
}
