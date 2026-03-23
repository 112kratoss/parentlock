package com.example.parentlock_native

import android.content.Context

object MonitoringStateStore {
    private const val PREFS_NAME = "parentlock_native_state"
    private const val KEY_BLOCKED_APPS = "blocked_apps"
    private const val KEY_MONITORING_ENABLED = "monitoring_enabled"
    private const val KEY_MANUAL_STOP_REQUESTED = "manual_stop_requested"
    private const val KEY_CHILD_ID = "child_id"
    private const val KEY_ACCESS_TOKEN = "access_token"
    private const val KEY_REFRESH_TOKEN = "refresh_token"
    private const val KEY_SUPABASE_URL = "supabase_url"
    private const val KEY_SUPABASE_ANON_KEY = "supabase_anon_key"
    private const val KEY_TAMPER_STATE = "tamper_state"
    private const val KEY_TAMPER_REASON = "tamper_reason"
    private const val KEY_LAST_HEARTBEAT_AT = "last_heartbeat_at"
    private const val KEY_LAST_POLICY_SYNC_AT = "last_policy_sync_at"
    private const val KEY_ENROLLMENT_MODE = "enrollment_mode"

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

    fun isManualStopRequested(context: Context): Boolean {
        return prefs(context).getBoolean(KEY_MANUAL_STOP_REQUESTED, false)
    }

    fun setManualStopRequested(context: Context, requested: Boolean) {
        prefs(context).edit().putBoolean(KEY_MANUAL_STOP_REQUESTED, requested).apply()
    }

    fun configureSession(
        context: Context,
        childId: String,
        accessToken: String,
        refreshToken: String?,
        supabaseUrl: String,
        supabaseAnonKey: String,
    ) {
        prefs(context)
            .edit()
            .putString(KEY_CHILD_ID, childId)
            .putString(KEY_ACCESS_TOKEN, accessToken)
            .putString(KEY_REFRESH_TOKEN, refreshToken)
            .putString(KEY_SUPABASE_URL, supabaseUrl)
            .putString(KEY_SUPABASE_ANON_KEY, supabaseAnonKey)
            .apply()
    }

    fun getChildId(context: Context): String? = prefs(context).getString(KEY_CHILD_ID, null)

    fun getAccessToken(context: Context): String? =
        prefs(context).getString(KEY_ACCESS_TOKEN, null)

    fun getRefreshToken(context: Context): String? =
        prefs(context).getString(KEY_REFRESH_TOKEN, null)

    fun getSupabaseUrl(context: Context): String? =
        prefs(context).getString(KEY_SUPABASE_URL, null)

    fun getSupabaseAnonKey(context: Context): String? =
        prefs(context).getString(KEY_SUPABASE_ANON_KEY, null)

    fun getTamperState(context: Context): String {
        return prefs(context).getString(KEY_TAMPER_STATE, "healthy") ?: "healthy"
    }

    fun getTamperReason(context: Context): String? =
        prefs(context).getString(KEY_TAMPER_REASON, null)

    fun setTamperStatus(context: Context, state: String, reason: String?) {
        prefs(context)
            .edit()
            .putString(KEY_TAMPER_STATE, state)
            .putString(KEY_TAMPER_REASON, reason)
            .apply()
    }

    fun getLastHeartbeatAt(context: Context): String? =
        prefs(context).getString(KEY_LAST_HEARTBEAT_AT, null)

    fun setLastHeartbeatAt(context: Context, isoTimestamp: String) {
        prefs(context).edit().putString(KEY_LAST_HEARTBEAT_AT, isoTimestamp).apply()
    }

    fun getLastPolicySyncAt(context: Context): String? =
        prefs(context).getString(KEY_LAST_POLICY_SYNC_AT, null)

    fun recordPolicySync(context: Context, isoTimestamp: String) {
        prefs(context).edit().putString(KEY_LAST_POLICY_SYNC_AT, isoTimestamp).apply()
    }

    fun getEnrollmentMode(context: Context): String {
        return prefs(context).getString(KEY_ENROLLMENT_MODE, "standard") ?: "standard"
    }

    fun setEnrollmentMode(context: Context, enrollmentMode: String) {
        prefs(context).edit().putString(KEY_ENROLLMENT_MODE, enrollmentMode).apply()
    }
}
