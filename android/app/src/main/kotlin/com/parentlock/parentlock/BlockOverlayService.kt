package com.parentlock.parentlock

import android.annotation.SuppressLint
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.TextView

class BlockOverlayService : Service() {
    
    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    
    companion object {
        private val blockedAppsSet = mutableSetOf<String>()
        private var isOverlayShowing = false
        
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
        }
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
        
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            },
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        )
        params.gravity = Gravity.CENTER
        
        // Create a simple blocking view
        // In production, you'd want to create a proper layout XML
        overlayView = createBlockView()
        
        try {
            windowManager?.addView(overlayView, params)
            isOverlayShowing = true
            
            // Auto-hide after 3 seconds to allow user to go back
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                hideBlockOverlay()
            }, 3000)
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
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
    
    @SuppressLint("SetTextI18n")
    private fun createBlockView(): View {
        // Create a simple LinearLayout programmatically
        val layout = android.widget.LinearLayout(this)
        layout.orientation = android.widget.LinearLayout.VERTICAL
        layout.gravity = Gravity.CENTER
        layout.setBackgroundColor(android.graphics.Color.parseColor("#EE000000"))
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
        title.textSize = 24f
        title.setTextColor(android.graphics.Color.WHITE)
        title.gravity = Gravity.CENTER
        title.setPadding(32, 32, 32, 16)
        layout.addView(title)
        
        // Add message
        val message = TextView(this)
        message.text = "You've reached your time limit for this app.\nPlease switch to another activity."
        message.textSize = 16f
        message.setTextColor(android.graphics.Color.parseColor("#CCFFFFFF"))
        message.gravity = Gravity.CENTER
        message.setPadding(32, 0, 32, 32)
        layout.addView(message)
        
        return layout
    }
    
    override fun onDestroy() {
        hideBlockOverlay()
        super.onDestroy()
    }
}
