package com.example.parentlock_native

import android.content.Context

object MonitoringStateStore {
    private const val PREFS_NAME = "parentlock_native_state"
    private const val KEY_BLOCKED_APPS = "blocked_apps"
    private const val KEY_MONITORING_ENABLED = "monitoring_enabled"

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun getBlockedApps(context: Context): List<String> {
        val storedApps = prefs(context).getStringSet(KEY_BLOCKED_APPS, emptySet()) ?: emptySet()
        return storedApps.filter { it.isNotBlank() }.sorted()
    }

    fun saveBlockedApps(context: Context, blockedApps: Collection<String>) {
        prefs(context)
            .edit()
            .putStringSet(KEY_BLOCKED_APPS, blockedApps.filter { it.isNotBlank() }.toSet())
            .apply()
    }

    fun isMonitoringEnabled(context: Context): Boolean {
        return prefs(context).getBoolean(KEY_MONITORING_ENABLED, false)
    }

    fun setMonitoringEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_MONITORING_ENABLED, enabled).apply()
    }
}
