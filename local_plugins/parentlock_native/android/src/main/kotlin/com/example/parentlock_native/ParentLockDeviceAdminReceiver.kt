package com.example.parentlock_native

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent

class ParentLockDeviceAdminReceiver : DeviceAdminReceiver() {
    override fun onEnabled(context: Context, intent: Intent) {
        ManagedDeviceController.applyManagedDevicePolicies(context)
    }

    override fun onProfileProvisioningComplete(context: Context, intent: Intent) {
        ManagedDeviceController.applyManagedDevicePolicies(context)

        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        launchIntent?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (launchIntent != null) {
            context.startActivity(launchIntent)
        }
    }
}
