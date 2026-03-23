# Android Release Checklist

## Signing
- Copy `android/key.properties.example` to `android/key.properties` and fill in your upload keystore values.
- Or set these environment variables instead:
  - `PARENTLOCK_UPLOAD_STORE_FILE`
  - `PARENTLOCK_UPLOAD_STORE_PASSWORD`
  - `PARENTLOCK_UPLOAD_KEY_ALIAS`
  - `PARENTLOCK_UPLOAD_KEY_PASSWORD`
- If neither is set, local release builds fall back to the debug key so CI and smoke tests can still run, but that build is not Play Store ready.

## Sensitive Permissions To Document
- `PACKAGE_USAGE_STATS`
  Needed to measure app usage and enforce limits.
- `SYSTEM_ALERT_WINDOW`
  Needed to show the full-screen block overlay when a restricted app opens.
- `QUERY_ALL_PACKAGES`
  Needed to identify installed apps so parents can manage restrictions consistently.
- Background location
  Needed for live location, geofence alerts, and SOS reporting.
- Foreground service usage
  Needed to keep child-device monitoring and location uploads alive in the background.
- Battery optimization exemption
  Needed so Android does not suspend monitoring on child devices.

## Manual Release Validation
- Install on a real child Android device and complete every permission step.
- Verify usage sync, manual blocking, category limits, and overnight schedules.
- Swipe the child app away and confirm monitoring resumes.
- Reboot the child device and confirm monitoring restarts with the previous blocked-app state.
- Verify live location, geofence events, SOS alerts, and push notifications after a fresh login.
