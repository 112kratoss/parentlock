package com.example.parentlock_native

import android.annotation.SuppressLint
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

class BlockOverlayService : Service() {
    
    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    
    companion object {
        private val blockedAppsSet = mutableSetOf<String>()
        private var isOverlayShowing = false
        private var serviceInstance: BlockOverlayService? = null
        
        fun showOverlay(context: Context) {
            if (!isOverlayShowing) {
                val intent = Intent(context, BlockOverlayService::class.java)
                intent.action = "SHOW"
                context.startService(intent)
            }
        }
        
        fun hideOverlay(context: Context) {
            val intent = Intent(context, BlockOverlayService::class.java)
            intent.action = "HIDE"
            context.startService(intent)
        }
        
        fun addBlockedApp(packageName: String) {
            blockedAppsSet.add(packageName)
        }
        
        fun removeBlockedApp(packageName: String) {
            blockedAppsSet.remove(packageName)
        }
        
        fun updateBlockedApps(blockedApps: List<String>) {
            blockedAppsSet.clear()
            blockedAppsSet.addAll(blockedApps)
            android.util.Log.d("BlockOverlayService", "Updated blocked apps: $blockedApps")
        }
        
        fun isBlocked(packageName: String): Boolean = blockedAppsSet.contains(packageName)
        
        fun getBlockedApps(): Set<String> = blockedAppsSet.toSet()
    }
    
    override fun onCreate() {
        super.onCreate()
        serviceInstance = this
    }
    
    override fun onBind(intent: Intent?): IBinder? = null
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            "SHOW" -> showBlockOverlay()
            "HIDE" -> hideBlockOverlay()
        }
        return START_NOT_STICKY
    }
    
    @SuppressLint("InflateParams")
    private fun showBlockOverlay() {
        if (isOverlayShowing) return
        
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        
        // Make overlay focusable so button can be clicked
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            },
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH,
            PixelFormat.TRANSLUCENT
        )
        params.gravity = Gravity.CENTER
        
        // Create blocking view with Go Back button
        overlayView = createBlockView()
        
        try {
            windowManager?.addView(overlayView, params)
            isOverlayShowing = true
            android.util.Log.d("BlockOverlayService", "Overlay shown - persistent until user presses Go Back")
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
    
    private fun hideBlockOverlay() {
        if (!isOverlayShowing) return
        
        try {
            overlayView?.let {
                windowManager?.removeView(it)
            }
            overlayView = null
            isOverlayShowing = false
            android.util.Log.d("BlockOverlayService", "Overlay hidden")
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
    
    private fun goToHomeScreen() {
        // Hide the overlay first
        hideBlockOverlay()
        
        // Send user to home screen
        val homeIntent = Intent(Intent.ACTION_MAIN)
        homeIntent.addCategory(Intent.CATEGORY_HOME)
        homeIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
        startActivity(homeIntent)
        
        android.util.Log.d("BlockOverlayService", "User sent to home screen")
    }
    
    @SuppressLint("SetTextI18n")
    private fun createBlockView(): View {
        // Create a simple LinearLayout programmatically
        val layout = LinearLayout(this)
        layout.orientation = LinearLayout.VERTICAL
        layout.gravity = Gravity.CENTER
        layout.setBackgroundColor(android.graphics.Color.parseColor("#F0000000"))
        layout.layoutParams = android.view.ViewGroup.LayoutParams(
            android.view.ViewGroup.LayoutParams.MATCH_PARENT,
            android.view.ViewGroup.LayoutParams.MATCH_PARENT
        )
        
        // Add icon
        val icon = TextView(this)
        icon.text = "🔒"
        icon.textSize = 72f
        icon.gravity = Gravity.CENTER
        layout.addView(icon)
        
        // Add title
        val title = TextView(this)
        title.text = "App Limit Reached"
        title.textSize = 28f
        title.setTextColor(android.graphics.Color.WHITE)
        title.gravity = Gravity.CENTER
        title.setPadding(32, 32, 32, 16)
        layout.addView(title)
        
        // Add message
        val message = TextView(this)
        message.text = "You've reached your daily time limit for this app.\nAsk your parent to extend the limit."
        message.textSize = 16f
        message.setTextColor(android.graphics.Color.parseColor("#CCFFFFFF"))
        message.gravity = Gravity.CENTER
        message.setPadding(48, 0, 48, 48)
        layout.addView(message)
        
        // Add Go Back button
        val goBackButton = Button(this)
        goBackButton.text = "Go Back Home"
        goBackButton.textSize = 18f
        goBackButton.setTextColor(android.graphics.Color.WHITE)
        goBackButton.setBackgroundColor(android.graphics.Color.parseColor("#FF5722"))
        goBackButton.setPadding(64, 32, 64, 32)
        
        val buttonParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        )
        buttonParams.topMargin = 32
        goBackButton.layoutParams = buttonParams
        
        goBackButton.setOnClickListener {
            goToHomeScreen()
        }
        
        layout.addView(goBackButton)
        
        return layout
    }
    
    override fun onDestroy() {
        hideBlockOverlay()
        serviceInstance = null
        super.onDestroy()
    }
}

