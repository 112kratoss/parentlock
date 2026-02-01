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
    
    private val handler = Handler(Looper.getMainLooper())
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
        createNotificationChannel()
        isServiceRunning = true
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Get blocked apps list
        blockedApps = intent?.getStringArrayListExtra("blockedApps")?.toMutableList() ?: mutableListOf()
        
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
        
        // Start monitoring loop
        startMonitoring()
        
        return START_STICKY
    }
    
    override fun onBind(intent: Intent?): IBinder? = null
    
    override fun onDestroy() {
        stopMonitoring()
        isServiceRunning = false
        super.onDestroy()
    }
    
    private val monitoringRunnable = object : Runnable {
        override fun run() {
            val currentApp = UsageStatsService.getCurrentForegroundApp(this@MonitoringService)
            
            // Use BlockOverlayService's blocked apps set (updated dynamically from Flutter)
            if (currentApp != null && BlockOverlayService.isBlocked(currentApp)) {
                // Blocked app detected, show overlay
                android.util.Log.d("MonitoringService", "Blocked app detected: $currentApp")
                BlockOverlayService.showOverlay(this@MonitoringService)
            }
            
            handler.postDelayed(this, checkInterval)
        }
    }
    
    private fun startMonitoring() {
        handler.post(monitoringRunnable)
    }
    
    private fun stopMonitoring() {
        handler.removeCallbacks(monitoringRunnable)
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
