package com.parentlock.parentlock

import android.app.usage.UsageStats
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.pm.PackageManager
import java.util.Calendar

object UsageStatsService {
    
    /**
     * Get app usage statistics for today
     * Returns a list of maps with app_package_name, app_display_name, and minutes_used
     */
    fun getUsageStats(context: Context): List<Map<String, Any>> {
        val usageStatsManager = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val packageManager = context.packageManager
        
        // Get stats for today (from midnight to now)
        val calendar = Calendar.getInstance()
        calendar.set(Calendar.HOUR_OF_DAY, 0)
        calendar.set(Calendar.MINUTE, 0)
        calendar.set(Calendar.SECOND, 0)
        calendar.set(Calendar.MILLISECOND, 0)
        val startTime = calendar.timeInMillis
        val endTime = System.currentTimeMillis()
        
        val usageStats = usageStatsManager.queryUsageStats(
            UsageStatsManager.INTERVAL_DAILY,
            startTime,
            endTime
        )
        
        val result = mutableListOf<Map<String, Any>>()
        
        usageStats?.forEach { stats ->
            if (stats.totalTimeInForeground > 0) {
                val packageName = stats.packageName
                val appName = try {
                    val appInfo = packageManager.getApplicationInfo(packageName, 0)
                    packageManager.getApplicationLabel(appInfo).toString()
                } catch (e: PackageManager.NameNotFoundException) {
                    packageName
                }
                
                val minutesUsed = (stats.totalTimeInForeground / 60000).toInt()
                
                result.add(
                    mapOf(
                        "app_package_name" to packageName,
                        "app_display_name" to appName,
                        "minutes_used" to minutesUsed
                    )
                )
            }
        }
        
        return result.sortedByDescending { it["minutes_used"] as Int }
    }
    
    /**
     * Get the currently running foreground app
     */
    fun getCurrentForegroundApp(context: Context): String? {
        val usageStatsManager = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val endTime = System.currentTimeMillis()
        val startTime = endTime - 1000 // Last 1 second
        
        val usageStats = usageStatsManager.queryUsageStats(
            UsageStatsManager.INTERVAL_DAILY,
            startTime,
            endTime
        )
        
        // Find the app most recently in foreground
        var currentApp: String? = null
        var latestTime = 0L
        
        usageStats?.forEach { stats ->
            if (stats.lastTimeUsed > latestTime) {
                latestTime = stats.lastTimeUsed
                currentApp = stats.packageName
            }
        }
        
        return currentApp
    }
}
