package com.example.parentlock_native

import android.app.usage.UsageStats
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.pm.PackageManager
import java.util.Calendar

object UsageStatsService {
    
    /**
     * Get app usage statistics for today
     * Returns a list of maps with app_package_name, app_display_name, and minutes_used
     * Uses UsageEvents for accurate calculation from midnight
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
        val midnight = calendar.timeInMillis
        val endTime = System.currentTimeMillis()
        
        // Query from 2 hours BEFORE midnight to capture sessions that bridged across midnight
        val queryStartTime = midnight - (2 * 60 * 60 * 1000) 
        
        android.util.Log.d("UsageStatsService", "Querying events from ${java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.getDefault()).format(java.util.Date(queryStartTime))} tonow")
        
        // Use queryEvents for precise calculation
        val events = usageStatsManager.queryEvents(queryStartTime, endTime)
        val event = android.app.usage.UsageEvents.Event()
        
        // Map to store total blocking duration per package (in millis)
        val appUsageMap = mutableMapOf<String, Long>()
        // Map to track start times of currently foreground apps
        val startTimes = mutableMapOf<String, Long>()
        
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            val packageName = event.packageName
            val timeStamp = event.timeStamp
            
            if (event.eventType == android.app.usage.UsageEvents.Event.MOVE_TO_FOREGROUND) {
                startTimes[packageName] = timeStamp
            } else if (event.eventType == android.app.usage.UsageEvents.Event.MOVE_TO_BACKGROUND) {
                val startTimeForApp = startTimes[packageName]
                if (startTimeForApp != null) {
                    startTimes.remove(packageName)
                    
                    // Only count usage that happens AFTER midnight
                    // Use max(startTimeForApp, midnight) to clamp the start time
                    val clampedStart = kotlin.math.max(startTimeForApp, midnight)
                    val clampedEnd = timeStamp
                    
                    val duration = clampedEnd - clampedStart
                    if (duration > 0) {
                        val currentTotal = appUsageMap.getOrDefault(packageName, 0L)
                        appUsageMap[packageName] = currentTotal + duration
                    }
                }
            }
        }
        
        // Handle apps properly still in foreground (counting time until 'now')
        startTimes.forEach { (packageName, startTimeForApp) ->
             // Only count usage that happens AFTER midnight
             val clampedStart = kotlin.math.max(startTimeForApp, midnight)
             val clampedEnd = endTime
             
             val duration = clampedEnd - clampedStart
             if (duration > 0) {
                 val currentTotal = appUsageMap.getOrDefault(packageName, 0L)
                 appUsageMap[packageName] = currentTotal + duration
             }
        }
        
        val result = mutableListOf<Map<String, Any>>()
        
        appUsageMap.forEach { (packageName, totalMillis) ->
            // Include anything with > 0 millis
            if (totalMillis > 0) {
                val appInfo = try {
                    packageManager.getApplicationInfo(packageName, 0)
                } catch (e: PackageManager.NameNotFoundException) {
                    null
                }
                
                val appName = if (appInfo != null) {
                    packageManager.getApplicationLabel(appInfo).toString()
                } else {
                    packageName
                }

                // Extract category
                var category = "other"
                
                // 1. Check System Category (API 26+)
                if (appInfo != null && android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                    val cat = when (appInfo.category) {
                        android.content.pm.ApplicationInfo.CATEGORY_GAME -> "game"
                        android.content.pm.ApplicationInfo.CATEGORY_AUDIO -> "audio"
                        android.content.pm.ApplicationInfo.CATEGORY_VIDEO -> "video"
                        android.content.pm.ApplicationInfo.CATEGORY_IMAGE -> "image"
                        android.content.pm.ApplicationInfo.CATEGORY_SOCIAL -> "social"
                        android.content.pm.ApplicationInfo.CATEGORY_NEWS -> "news"
                        android.content.pm.ApplicationInfo.CATEGORY_MAPS -> "maps"
                        android.content.pm.ApplicationInfo.CATEGORY_PRODUCTIVITY -> "productivity"
                        else -> "other"
                    }
                    if (cat != "other") category = cat
                }

                // 2. Check Legacy Flags (fallback)
                if (category == "other" && appInfo != null) {
                    val flags = appInfo.flags
                    // FLAG_IS_GAME is bit 25
                    val isGame = (flags and android.content.pm.ApplicationInfo.FLAG_IS_GAME) == android.content.pm.ApplicationInfo.FLAG_IS_GAME
                    if (isGame) category = "game"
                }

                // Convert to minutes
                val minutesUsed = (totalMillis / 60000).toInt()
                
                result.add(
                    mapOf(
                        "app_package_name" to packageName,
                        "app_display_name" to appName,
                        "minutes_used" to minutesUsed,
                        "app_category" to category
                    )
                )
            }
        }
        
        android.util.Log.d("UsageStatsService", "Found ${result.size} apps with usage today using Events (with overlap support)")
        
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
