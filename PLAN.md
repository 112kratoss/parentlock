# ParentLock - Flutter Parental Control Application

## 📋 Implementation Plan

> A cross-platform Parental Control app with **Parent Mode** (dashboard, set limits, notifications) and **Child Mode** (background tracking, app blocking).

---

## 🗂️ Project Folder Structure

```
parentlock/
├── android/
│   ├── app/
│   │   ├── src/
│   │   │   └── main/
│   │   │       ├── kotlin/com/example/parentlock/
│   │   │       │   ├── MainActivity.kt              # MethodChannel handler
│   │   │       │   ├── UsageStatsService.kt         # UsageStatsManager logic
│   │   │       │   ├── MonitoringService.kt         # Foreground Service
│   │   │       │   └── BlockOverlayService.kt       # Full-screen overlay blocker
│   │   │       └── AndroidManifest.xml              # Permissions declared here
│   │   └── build.gradle
│   └── build.gradle
├── ios/
│   ├── Runner/
│   │   ├── AppDelegate.swift                        # MethodChannel handler
│   │   └── Info.plist
│   ├── DeviceActivityMonitorExtension/              # [REQUIRED EXTENSION]
│   │   ├── DeviceActivityMonitorExtension.swift
│   │   └── Info.plist
│   └── Runner.xcworkspace
├── lib/
│   ├── main.dart                                    # App entry point
│   ├── app.dart                                     # MaterialApp with routing
│   ├── config/
│   │   ├── supabase_config.dart                     # Supabase URL & Anon Key
│   │   └── firebase_options.dart                    # Firebase config (auto-generated)
│   ├── models/
│   │   ├── user_profile.dart                        # Profile model (id, role, fcm_token)
│   │   └── child_activity.dart                      # Activity model (app usage, limits)
│   ├── services/
│   │   ├── auth_service.dart                        # Supabase Auth wrapper
│   │   ├── database_service.dart                    # Supabase CRUD operations
│   │   ├── notification_service.dart                # FCM initialization & handling
│   │   └── native_service.dart                      # ⭐ MethodChannel bridge (Dart side)
│   ├── screens/
│   │   ├── splash_screen.dart                       # Initial loading screen
│   │   ├── auth/
│   │   │   ├── login_screen.dart                    # Email/Password login
│   │   │   ├── register_screen.dart                 # Registration
│   │   │   └── role_selection_screen.dart           # Parent/Child role picker
│   │   ├── parent/
│   │   │   ├── parent_dashboard_screen.dart         # Live stats dashboard
│   │   │   ├── add_child_screen.dart                # Link child device
│   │   │   └── set_limits_screen.dart               # Configure app time limits
│   │   └── child/
│   │       └── child_active_screen.dart             # Shows "Monitoring Active"
│   └── widgets/
│       ├── usage_stat_card.dart                     # Usage display widget
│       └── app_limit_tile.dart                      # App limit list tile
├── supabase/
│   ├── migrations/
│   │   └── 001_initial_schema.sql                   # Database schema
│   └── functions/
│       └── send-block-notification/
│           └── index.ts                             # Edge Function for FCM
├── pubspec.yaml
└── PLAN.md                                          # This file
```

---

## 📊 Database Schema (Supabase)

### Table: `profiles`
| Column      | Type      | Description                          |
|-------------|-----------|--------------------------------------|
| `id`        | UUID (PK) | References `auth.users.id`           |
| `role`      | TEXT      | `'parent'` or `'child'`              |
| `fcm_token` | TEXT      | Firebase Cloud Messaging token       |
| `linked_to` | UUID      | For child: links to parent's profile |
| `created_at`| TIMESTAMP | Auto-generated                       |

### Table: `child_activity`
| Column               | Type      | Description                           |
|----------------------|-----------|---------------------------------------|
| `id`                 | UUID (PK) | Primary key                           |
| `child_id`           | UUID (FK) | References `profiles.id`              |
| `app_package_name`   | TEXT      | e.g., `com.instagram.android`         |
| `app_display_name`   | TEXT      | e.g., `Instagram`                     |
| `daily_limit_minutes`| INTEGER   | Max allowed minutes per day           |
| `minutes_used`       | INTEGER   | Actual usage today                    |
| `is_blocked`         | BOOLEAN   | TRUE when limit exceeded              |
| `last_updated`       | TIMESTAMP | Last activity sync time               |

### Trigger Logic
```sql
-- When is_blocked changes from FALSE to TRUE, trigger Edge Function
CREATE OR REPLACE FUNCTION notify_parent_on_block()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.is_blocked = TRUE AND OLD.is_blocked = FALSE THEN
    -- Call Edge Function via pg_net or webhook
    PERFORM net.http_post(
      url := 'YOUR_SUPABASE_URL/functions/v1/send-block-notification',
      body := json_build_object('child_id', NEW.child_id, 'app_name', NEW.app_display_name)
    );
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER on_app_blocked
  AFTER UPDATE ON child_activity
  FOR EACH ROW
  EXECUTE FUNCTION notify_parent_on_block();
```

---

## ⚡ Implementation Order (Step-by-Step)

### 🔷 Phase 1: Project Setup & Authentication (Days 1-2)

| Step | Task | File(s) Affected |
|------|------|------------------|
| 1.1 | Initialize Flutter project | `flutter create parentlock` |
| 1.2 | Add dependencies to `pubspec.yaml` | `supabase_flutter`, `firebase_messaging`, `flutter_local_notifications` |
| 1.3 | Create Firebase project & download `google-services.json` (Android) and `GoogleService-Info.plist` (iOS) | `android/app/` and `ios/Runner/` |
| 1.4 | Configure Supabase project & get credentials | `lib/config/supabase_config.dart` |
| 1.5 | Implement `AuthService` with login/register/logout | `lib/services/auth_service.dart` |
| 1.6 | Implement `NotificationService` for FCM | `lib/services/notification_service.dart` |
| 1.7 | Build Login & Register screens | `lib/screens/auth/` |
| 1.8 | Build Role Selection screen | `lib/screens/auth/role_selection_screen.dart` |

---

### 🔷 Phase 2: The Method Channel Bridge (Day 3)

| Step | Task | File(s) Affected |
|------|------|------------------|
| 2.1 | Create `NativeService` Dart class | `lib/services/native_service.dart` |
| 2.2 | Define method channel name: `com.parentlock/native` | Same file |
| 2.3 | Add methods: `getUsageStats()`, `startMonitoringService()`, `checkPermissions()`, `requestPermissions()` | Same file |

**Dart Code Preview:**
```dart
class NativeService {
  static const _channel = MethodChannel('com.parentlock/native');
  
  Future<Map<String, int>> getUsageStats() async {
    final result = await _channel.invokeMethod('getUsageStats');
    return Map<String, int>.from(result);
  }
  
  Future<void> startMonitoringService(List<String> blockedApps) async {
    await _channel.invokeMethod('startMonitoring', {'blockedApps': blockedApps});
  }
}
```

---

### 🔷 Phase 3: Android Native Implementation (Days 4-6)

| Step | Task | File(s) Affected |
|------|------|------------------|
| 3.1 | Add permissions to `AndroidManifest.xml` | `android/app/src/main/AndroidManifest.xml` |
| 3.2 | Modify `MainActivity.kt` to handle MethodChannel | `MainActivity.kt` |
| 3.3 | Create `UsageStatsService.kt` for fetching usage data | New file |
| 3.4 | Create `MonitoringService.kt` (Foreground Service) | New file |
| 3.5 | Create `BlockOverlayService.kt` for overlay blocking | New file |

**Required Android Permissions:**
```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<uses-permission android:name="android.permission.PACKAGE_USAGE_STATS" 
    tools:ignore="ProtectedPermissions"/>
<uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE"/>
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
```

> [!IMPORTANT]  
> **Manual Permission Steps (Android)**
> 1. **Usage Access**: Settings → Apps → Special Access → Usage Access → Enable for ParentLock
> 2. **Display Over Other Apps**: Settings → Apps → Special Access → Display Over Other Apps → Allow
> 3. **Disable Battery Optimization**: Settings → Apps → ParentLock → Battery → Unrestricted

---

### 🔷 Phase 4: iOS Native Implementation (Days 7-9)

| Step | Task | File(s) Affected |
|------|------|------------------|
| 4.1 | Enable "Screen Time API" entitlement in Xcode | Signing & Capabilities |
| 4.2 | Modify `AppDelegate.swift` for MethodChannel | `ios/Runner/AppDelegate.swift` |
| 4.3 | Add Device Activity Monitor Extension target | Xcode: File → New → Target |
| 4.4 | Implement `DeviceActivityMonitorExtension.swift` | New extension target |
| 4.5 | Configure App Groups for data sharing | Both targets |

**Required iOS Frameworks:**
- `FamilyControls` - Authorization for parental controls
- `DeviceActivity` - Monitoring device activity
- `ManagedSettings` - Applying shields (blocking apps)

> [!WARNING]  
> **iOS Limitations**
> - Screen Time API is only available on **iOS 15+**
> - Requires **Apple Developer Program** membership
> - The Device Activity Monitor extension runs in a **separate process**
> - Must use **App Groups** to share data between app and extension

**Add Extension Target (Xcode Steps):**
1. Open `ios/Runner.xcworkspace` in Xcode
2. File → New → Target → "Device Activity Monitor Extension"
3. Name it: `DeviceActivityMonitorExtension`
4. Add to both targets: Signing & Capabilities → App Groups → `group.com.parentlock.shared`

---

### 🔷 Phase 5: Supabase Backend (Day 10)

| Step | Task | File(s) Affected |
|------|------|------------------|
| 5.1 | Run SQL migration for `profiles` and `child_activity` tables | Supabase Dashboard → SQL Editor |
| 5.2 | Create Row Level Security (RLS) policies | Same |
| 5.3 | Create Edge Function `send-block-notification` | `supabase/functions/` |
| 5.4 | Set up database trigger for `is_blocked` | SQL Editor |

**Edge Function Code (TypeScript):**
```typescript
// supabase/functions/send-block-notification/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

serve(async (req) => {
  const { child_id, app_name } = await req.json()
  
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  )
  
  // Get parent's FCM token
  const { data: child } = await supabase
    .from('profiles')
    .select('linked_to')
    .eq('id', child_id)
    .single()
  
  const { data: parent } = await supabase
    .from('profiles')
    .select('fcm_token')
    .eq('id', child.linked_to)
    .single()
  
  // Send FCM notification
  const fcmResponse = await fetch('https://fcm.googleapis.com/fcm/send', {
    method: 'POST',
    headers: {
      'Authorization': `key=${Deno.env.get('FCM_SERVER_KEY')}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      to: parent.fcm_token,
      notification: {
        title: 'App Blocked',
        body: `${app_name} has been blocked on your child's device.`
      }
    })
  })
  
  return new Response(JSON.stringify({ success: true }))
})
```

---

### 🔷 Phase 6: Flutter UI Screens (Days 11-13)

| Step | Task | File(s) Affected |
|------|------|------------------|
| 6.1 | Build `SplashScreen` with auth check | `lib/screens/splash_screen.dart` |
| 6.2 | Build `ParentDashboardScreen` with real-time stats | `lib/screens/parent/` |
| 6.3 | Build `SetLimitsScreen` for configuring app limits | Same |
| 6.4 | Build `ChildActiveScreen` showing monitoring status | `lib/screens/child/` |
| 6.5 | Implement real-time subscription for live updates | `lib/services/database_service.dart` |

---

### 🔷 Phase 7: Testing & Polish (Days 14-15)

| Step | Task |
|------|------|
| 7.1 | Test Android blocking overlay on physical device |
| 7.2 | Test iOS Screen Time shielding on physical device |
| 7.3 | Test FCM notifications end-to-end |
| 7.4 | Handle edge cases (app killed, device reboot) |
| 7.5 | Add loading states, error handling, and UI polish |

---

## 📱 Required Dependencies (`pubspec.yaml`)

```yaml
dependencies:
  flutter:
    sdk: flutter
  
  # Supabase
  supabase_flutter: ^2.3.0
  
  # Firebase
  firebase_core: ^2.24.0
  firebase_messaging: ^14.7.0
  flutter_local_notifications: ^17.0.0
  
  # Utilities
  shared_preferences: ^2.2.2
  go_router: ^13.0.0
  provider: ^6.1.0
  
dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0
```

---

## ⚠️ Critical Notes for Beginners

### Where to Find Native Code Files

**Android (Kotlin):**
```
android/app/src/main/kotlin/com/example/parentlock/MainActivity.kt
```
> [!NOTE]  
> The package path (`com/example/parentlock`) matches your app's package name. If you named your project differently, adjust accordingly.

**iOS (Swift):**
```
ios/Runner/AppDelegate.swift
```

### Manual Permission Setup (Required for Testing)

| Platform | Permission | How to Enable |
|----------|-----------|---------------|
| Android | Usage Access | Settings → Apps → Special Access → Usage Access → ParentLock ✓ |
| Android | Overlay | Settings → Apps → Special Access → Display Over Other Apps → ParentLock ✓ |
| Android | Notifications | Settings → Apps → ParentLock → Notifications → Allow |
| iOS | Screen Time | The app will prompt for FamilyControls authorization |

---

## ✅ Verification Plan

### Automated Tests
Since this project involves significant native platform code and real device permissions, automated tests are limited. However:

1. **Unit Tests** (Flutter):
   ```bash
   flutter test
   ```
   - Test `AuthService` login/logout flows
   - Test data models serialization
   - Test `DatabaseService` CRUD operations (with mocked Supabase)

2. **Widget Tests**:
   ```bash
   flutter test test/widget_test.dart
   ```
   - Test UI screens render correctly
   - Test role selection flow

### Manual Verification (Required)

> [!CAUTION]  
> **Physical devices are REQUIRED for testing.** Native features like UsageStats, Overlay, and Screen Time API cannot be tested on emulators/simulators.

| Test Case | Steps | Expected Result |
|-----------|-------|-----------------|
| **Android: Usage Stats** | 1. Enable Usage Access permission<br>2. Use other apps for a few minutes<br>3. Open ParentLock → Check dashboard | Usage stats appear correctly |
| **Android: App Blocking** | 1. Set Instagram limit to 1 minute<br>2. Use Instagram for 1 minute<br>3. Try to open Instagram again | Full-screen overlay blocks the app |
| **iOS: Screen Time Shield** | 1. Authorize FamilyControls<br>2. Set app limit<br>3. Exceed the limit | iOS shield appears over the app |
| **Push Notification** | 1. Login as Child, exceed limit<br>2. Check Parent device | Parent receives "App Blocked" notification |
| **Foreground Service** | 1. Start monitoring<br>2. Kill the app<br>3. Check if service continues | Notification persists, monitoring continues |

---

## 🚀 Getting Started Command

Once the plan is approved, run these commands to initialize:

```bash
cd /Users/athuls/parentlock
flutter create --org com.parentlock .
flutter pub add supabase_flutter firebase_core firebase_messaging flutter_local_notifications shared_preferences go_router provider
```

---

## 📝 Summary

This plan outlines a **15-day implementation** for a full-featured Parental Control app. The key challenges are:

1. **Android**: Managing permissions and keeping the Foreground Service alive
2. **iOS**: Correctly implementing the Device Activity Monitor Extension
3. **Backend**: Setting up real-time sync and FCM triggers

**Next Steps**: Approve this plan to begin Phase 1 (Project Setup & Authentication).
