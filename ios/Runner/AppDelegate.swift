import Flutter
import UIKit
import FamilyControls

@main
@objc class AppDelegate: FlutterAppDelegate {
    private let CHANNEL = "com.parentlock.parentlock/native"
    
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)
        
        let controller = window?.rootViewController as! FlutterViewController
        let nativeChannel = FlutterMethodChannel(name: CHANNEL,
                                                  binaryMessenger: controller.binaryMessenger)
        
        nativeChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
            self?.handleMethodCall(call: call, result: result)
        }
        
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    private func handleMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getUsageStats":
            // iOS doesn't provide direct usage stats API like Android
            // This would require Device Activity framework with extensions
            result([[String: Any]]())
            
        case "startMonitoringService":
            // On iOS, monitoring is handled differently via Device Activity
            result(true)
            
        case "stopMonitoringService":
            result(true)
            
        case "isMonitoringActive":
            result(false)
            
        case "checkPermissions":
            checkFamilyControlsPermission(result: result)
            
        case "requestPermissions":
            requestFamilyControlsAuthorization(result: result)
            
        case "authorizeFamilyControls":
            requestFamilyControlsAuthorization(result: result)
            
        case "blockApp":
            // Blocking handled via ManagedSettings and DeviceActivityMonitor
            result(true)
            
        case "unblockApp":
            result(true)
            
        case "updateBlockedApps":
            // Would update ManagedSettings shield configuration
            result(true)
            
        case "getCurrentForegroundApp":
            // Not available on iOS
            result(nil)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    @available(iOS 15.0, *)
    private func checkFamilyControlsPermission(result: @escaping FlutterResult) {
        let center = AuthorizationCenter.shared
        let status = center.authorizationStatus
        
        result([
            "familyControls": status == .approved,
            "usageStats": status == .approved,
            "overlay": true,  // Not needed on iOS
            "notification": true
        ])
    }
    
    @available(iOS 15.0, *)
    private func requestFamilyControlsAuthorization(result: @escaping FlutterResult) {
        Task {
            do {
                try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
                result(true)
            } catch {
                result(FlutterError(code: "AUTHORIZATION_FAILED",
                                  message: "Failed to authorize Family Controls",
                                  details: error.localizedDescription))
            }
        }
    }
}
