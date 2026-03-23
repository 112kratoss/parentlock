import DeviceActivity
import FamilyControls
import Flutter
import ManagedSettings
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
    private let channelName = "com.parentlock.parentlock/native"

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        if let controller = window?.rootViewController as? FlutterViewController {
            let nativeChannel = FlutterMethodChannel(
                name: channelName,
                binaryMessenger: controller.binaryMessenger
            )

            nativeChannel.setMethodCallHandler { [weak self] call, result in
                self?.handleMethodCall(call: call, result: result)
            }
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    private func handleMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getPlatformStatus":
            getPlatformStatus(result: result)
        case "getUsageStats":
            result(unsupportedFeatureError(
                code: "UNSUPPORTED",
                message: "Usage stats require Device Activity extension targets, which are not configured in this iOS build."
            ))
        case "startMonitoringService":
            result(unsupportedFeatureError(
                code: "UNSUPPORTED",
                message: "App blocking is not enabled in this iOS build yet. Finish the Screen Time extension setup in Xcode."
            ))
        case "configureMonitoringSession", "recordPolicySync", "syncDeviceHealthNow":
            result(true)
        case "stopMonitoringService":
            result(false)
        case "isMonitoringActive":
            result(false)
        case "checkPermissions":
            checkFamilyControlsPermission(result: result)
        case "requestPermissions", "authorizeFamilyControls":
            requestFamilyControlsAuthorization(result: result)
        case "requestDeviceAdmin":
            result(unsupportedFeatureError(
                code: "UNSUPPORTED",
                message: "Device owner and device admin flows are only available on Android."
            ))
        case "applyManagedDevicePolicies":
            result(false)
        case "blockApp", "unblockApp", "updateBlockedApps":
            result(unsupportedFeatureError(
                code: "UNSUPPORTED",
                message: "Blocking apps on iOS requires Managed Settings and Screen Time extension targets that are not wired into this build yet."
            ))
        case "getCurrentForegroundApp":
            result(unsupportedFeatureError(
                code: "UNSUPPORTED",
                message: "Foreground app detection is not available in this iOS build yet."
            ))
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func unsupportedFeatureError(code: String, message: String) -> FlutterError {
        FlutterError(code: code, message: message, details: nil)
    }

    private func getPlatformStatus(result: @escaping FlutterResult) {
        if #available(iOS 15.0, *) {
            let authorizationStatus = AuthorizationCenter.shared.authorizationStatus

            UNUserNotificationCenter.current().getNotificationSettings { settings in
                let notificationsGranted = {
                    switch settings.authorizationStatus {
                    case .authorized, .provisional, .ephemeral:
                        return true
                    default:
                        return false
                    }
                }()

                DispatchQueue.main.async {
                    result([
                        "platform": "ios",
                        "monitoringSupported": false,
                        "monitoringActive": false,
                        "enrollmentMode": "limited",
                        "deviceOwner": false,
                        "tamperState": authorizationStatus == .approved ? "healthy" : "degraded",
                        "tamperReason": authorizationStatus == .approved
                            ? NSNull()
                            : "Screen Time authorization is still pending on this iOS build.",
                        "lastHeartbeatAt": NSNull(),
                        "criticalPermissionsOk": false,
                        "usageStatsSupported": false,
                        "usageStatsGranted": false,
                        "appBlockingSupported": false,
                        "overlayPermissionRequired": false,
                        "overlayGranted": true,
                        "batteryOptimizationSupported": false,
                        "batteryOptimizationExempt": true,
                        "familyControlsSupported": true,
                        "familyControlsAuthorized": authorizationStatus == .approved,
                        "notificationsGranted": notificationsGranted,
                        "backgroundLocationSupported": true,
                    ])
                }
            }
        } else {
            result([
                "platform": "ios",
                "monitoringSupported": false,
                "monitoringActive": false,
                "enrollmentMode": "limited",
                "deviceOwner": false,
                "tamperState": "degraded",
                "tamperReason": "Family Controls is unavailable on this iOS version.",
                "lastHeartbeatAt": NSNull(),
                "criticalPermissionsOk": false,
                "usageStatsSupported": false,
                "usageStatsGranted": false,
                "appBlockingSupported": false,
                "overlayPermissionRequired": false,
                "overlayGranted": true,
                "batteryOptimizationSupported": false,
                "batteryOptimizationExempt": true,
                "familyControlsSupported": false,
                "familyControlsAuthorized": false,
                "notificationsGranted": false,
                "backgroundLocationSupported": true,
            ])
        }
    }

    private func checkFamilyControlsPermission(result: @escaping FlutterResult) {
        if #available(iOS 15.0, *) {
            let center = AuthorizationCenter.shared
            let status = center.authorizationStatus

            result([
                "usageStats": false,
                "overlay": true,
                "batteryOptimization": true,
                "notification": true,
                "familyControls": status == .approved,
                "monitoringSupported": false,
            ])
        } else {
            result([
                "usageStats": false,
                "overlay": true,
                "batteryOptimization": true,
                "notification": true,
                "familyControls": false,
                "monitoringSupported": false,
            ])
        }
    }

    private func requestFamilyControlsAuthorization(result: @escaping FlutterResult) {
        guard #available(iOS 15.0, *) else {
            result(unsupportedFeatureError(
                code: "UNSUPPORTED",
                message: "Family Controls requires iOS 15 or newer."
            ))
            return
        }

        Task {
            do {
                try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
                result(true)
            } catch {
                result(
                    FlutterError(
                        code: "AUTHORIZATION_FAILED",
                        message: "Failed to authorize Family Controls",
                        details: error.localizedDescription
                    )
                )
            }
        }
    }
}
