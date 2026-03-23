package com.example.parentlock_native

import android.app.*
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat

class MonitoringService : Service() {
    
    private var serviceHandler: Handler? = null
    private var serviceLooper: Looper? = null
    private val checkInterval = 2000L // Check every 2 seconds
    private var blockedApps = mutableListOf<String>()
    
    companion object {
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "parentlock_monitoring"
        private var isServiceRunning = false
        
        fun start(context: Context, blockedApps: List<String>) {
            val intent = Intent(context, MonitoringService::class.java)
            intent.putStringArrayListExtra("blockedApps", ArrayList(blockedApps))
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
        
        fun stop(context: Context) {
            val intent = Intent(context, MonitoringService::class.java)
            context.stopService(intent)
        }
        
        fun isRunning(): Boolean = isServiceRunning
    }
    
    override fun onCreate() {
        super.onCreate()
        
        // Start up the thread running the service. Note that we create a
        // separate thread because the service normally runs in the process's
        // main thread, which we don't want to block. We also want it to run in
        // the background so priority doesn't impact the UI.
        val thread = android.os.HandlerThread("ServiceStartArguments",
                android.os.Process.THREAD_PRIORITY_BACKGROUND)
        thread.start()
        
        // Get the HandlerThread's Looper and use it for our Handler
        serviceLooper = thread.looper
        serviceHandler = Handler(serviceLooper!!)
        
        createNotificationChannel()
        isServiceRunning = true
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Get blocked apps list
        val restoredBlockedApps = MonitoringStateStore.getBlockedApps(this)
        blockedApps =
            intent?.getStringArrayListExtra("blockedApps")?.toMutableList()
                ?: restoredBlockedApps.toMutableList()
        MonitoringStateStore.setMonitoringEnabled(this, true)
        MonitoringStateStore.saveBlockedApps(this, blockedApps)
        BlockOverlayService.updateBlockedApps(blockedApps)
        
        // Start foreground
        val notification = createNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) { // Android 10+
            startForeground(
                NOTIFICATION_ID, 
                notification,
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        
        // Start monitoring loop on background thread
        startMonitoring()
        
        return START_STICKY
    }
    
    override fun onBind(intent: Intent?): IBinder? = null
    
    override fun onDestroy() {
        stopMonitoring()
        isServiceRunning = false
        serviceLooper?.quit()
        super.onDestroy()
    }
    
    private val monitoringRunnable = object : Runnable {
        override fun run() {
            try {
                val currentApp = UsageStatsService.getCurrentForegroundApp(this@MonitoringService)
            
                // Use BlockOverlayService's blocked apps set (updated dynamically from Flutter)
                if (currentApp != null && BlockOverlayService.isBlocked(currentApp)) {
                    // Blocked app detected, show overlay
                    android.util.Log.d("MonitoringService", "Blocked app detected: $currentApp")
                    
                    // Post UI update to Main Thread
                    Handler(Looper.getMainLooper()).post {
                         BlockOverlayService.showOverlay(this@MonitoringService)
                    }
                }
            } catch (e: Exception) {
                android.util.Log.e("MonitoringService", "Error in monitoring loop", e)
            }
            
            serviceHandler?.postDelayed(this, checkInterval)
        }
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        if (!MonitoringStateStore.isMonitoringEnabled(this)) {
            return
        }
        android.util.Log.d("MonitoringService", "Task removed, restarting service")
        
        val restartServiceIntent = Intent(applicationContext, MonitoringService::class.java).also {
            it.setPackage(packageName)
            // Re-pass the list of blocked apps if possible, though they might be lost in this context specifically.
            // Ideally should persist blocked apps to SharedPreferences for full resilience.
            // For now, restarting the service is the priority.
             it.putStringArrayListExtra("blockedApps", ArrayList(blockedApps))
        }

        val restartServicePendingIntent = PendingIntent.getService(
            applicationContext, 1, restartServiceIntent, PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
        )

        val alarmService = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmService.set(
            AlarmManager.ELAPSED_REALTIME,
            android.os.SystemClock.elapsedRealtime() + 1000,
            restartServicePendingIntent
        )
    }
    
    private fun startMonitoring() {
        serviceHandler?.removeCallbacks(monitoringRunnable)
        serviceHandler?.post(monitoringRunnable)
    }
    
    private fun stopMonitoring() {
        serviceHandler?.removeCallbacks(monitoringRunnable)
    }
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = "ParentLock Monitoring"
            val descriptionText = "Monitoring app usage and enforcing limits"
            val importance = NotificationManager.IMPORTANCE_LOW
            val channel = NotificationChannel(CHANNEL_ID, name, importance).apply {
                description = descriptionText
            }
            
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }
    
    private fun createNotification(): Notification {
        // Use getLaunchIntentForPackage to avoid hardcoding MainActivity
        val notificationIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = if (notificationIntent != null) {
            PendingIntent.getActivity(
                this, 0, notificationIntent,
                PendingIntent.FLAG_IMMUTABLE
            )
        } else {
            null
        }
        
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("ParentLock Active")
            .setContentText("Monitoring app usage")
            .setSmallIcon(android.R.drawable.ic_lock_idle_lock)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }
}
