package com.example.parentlock_native

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.os.UserManager

object ManagedDeviceController {
    private fun devicePolicyManager(context: Context): DevicePolicyManager =
        context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager

    fun adminComponent(context: Context): ComponentName =
        ComponentName(context, ParentLockDeviceAdminReceiver::class.java)

    fun isDeviceOwner(context: Context): Boolean {
        return devicePolicyManager(context).isDeviceOwnerApp(context.packageName)
    }

    fun isAdminActive(context: Context): Boolean {
        return devicePolicyManager(context).isAdminActive(adminComponent(context))
    }

    fun effectiveEnrollmentMode(context: Context): String {
        val deviceOwner = isDeviceOwner(context)
        val storedMode = MonitoringStateStore.getEnrollmentMode(context)

        return when {
            deviceOwner -> {
                MonitoringStateStore.setEnrollmentMode(context, "managed_device")
                "managed_device"
            }

            storedMode == "managed_device" -> "managed_device"
            else -> "standard"
        }
    }

    fun applyManagedDevicePolicies(context: Context): Boolean {
        if (!isDeviceOwner(context)) {
            return false
        }

        val dpm = devicePolicyManager(context)
        val admin = adminComponent(context)

        dpm.setLockTaskPackages(admin, arrayOf(context.packageName))
        dpm.addUserRestriction(admin, UserManager.DISALLOW_SAFE_BOOT)
        dpm.addUserRestriction(admin, UserManager.DISALLOW_ADD_USER)
        dpm.addUserRestriction(admin, UserManager.DISALLOW_APPS_CONTROL)
        dpm.addUserRestriction(admin, UserManager.DISALLOW_UNINSTALL_APPS)
        dpm.addUserRestriction(admin, UserManager.DISALLOW_DEBUGGING_FEATURES)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            dpm.addUserRestriction(
                admin,
                UserManager.DISALLOW_INSTALL_UNKNOWN_SOURCES_GLOBALLY
            )
        } else {
            @Suppress("DEPRECATION")
            dpm.addUserRestriction(admin, UserManager.DISALLOW_INSTALL_UNKNOWN_SOURCES)
        }

        return true
    }
}
