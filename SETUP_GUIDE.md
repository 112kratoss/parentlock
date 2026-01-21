# ParentLock - Android Setup Guide

> 📖 **Beginner-friendly guide** - Every step tells you exactly what to click.

---

## What You Need to Do

| Task | Time |
|------|------|
| 1. Google OAuth Setup | ~15 min |
| 2. Test on Android Phone | ~10 min |

**Total time: About 25 minutes**

---

# Part 1: Google Sign-In Setup

This allows users to sign in with their Google account.

## Step 1.1: Go to Google Cloud Console

1. **Open your browser**
2. **Go to**: https://console.cloud.google.com/
3. **Sign in** with your Google account

## Step 1.2: Create a Project

1. **Click** "Select a project" at the top
2. **Click** "NEW PROJECT"
3. **Name it**: `ParentLock`
4. **Click** "CREATE"
5. **Wait** 30 seconds

## Step 1.3: Enable the API

1. **Click** the menu (☰) top-left
2. **Click** "APIs & Services" → "Library"
3. **Search**: `Google Identity`
4. **Click** "Google Identity Toolkit API"
5. **Click** the blue "ENABLE" button

## Step 1.4: OAuth Consent Screen

1. **In left sidebar**, click "OAuth consent screen"
2. **Select** "External" → Click "CREATE"
3. **Fill in**:
   - App name: `ParentLock`
   - User support email: *Your email*
   - Developer contact: *Your email*
4. **Click** "SAVE AND CONTINUE" through all screens

## Step 1.5: Create OAuth Credentials

### First: Get Your SHA-1 Key
Open Terminal and run:
```bash
cd /Users/athuls/parentlock/android && ./gradlew signingReport
```
**Copy the SHA1 value** (looks like `AB:CD:12:34:56:...`)

### Create Web Client
1. **Click** "Credentials" in sidebar
2. **Click** "+ CREATE CREDENTIALS" → "OAuth client ID"
3. **Choose** "Web application"
4. **Name**: `ParentLock Web`
5. **Add URI**: `https://clycrthzxpjwxrqlqkqv.supabase.co/auth/v1/callback`
6. **Click** "CREATE"
7. **SAVE** the Client ID and Client Secret somewhere!

### Create Android Client
1. **Click** "+ CREATE CREDENTIALS" → "OAuth client ID"
2. **Choose** "Android"
3. **Name**: `ParentLock Android`
4. **Package name**: `com.parentlock.parentlock`
5. **SHA-1**: *Paste the SHA-1 you copied earlier*
6. **Click** "CREATE"

## Step 1.6: Add to Supabase

1. **Go to**: https://supabase.com/dashboard
2. **Select** your ParentLock project
3. **Click** "Authentication" → "Providers"
4. **Find** "Google" and click it
5. **Enable** it (toggle on)
6. **Paste** your Web Client ID and Secret
7. **Click** "Save"

✅ **Google Sign-In is now configured!**

---

# Part 2: Test on Android Phone

## Connect Your Phone

1. **On your phone**, enable Developer Options:
   - Settings → About Phone → Tap "Build Number" 7 times
2. **Enable USB Debugging**:
   - Settings → Developer Options → USB Debugging → ON
3. **Connect phone** to Mac with USB cable
4. **Tap "Allow"** when asked to trust the computer

## Run the App

In Terminal:
```bash
cd /Users/athuls/parentlock
flutter run
```

Wait for it to build and install (first time takes 3-5 minutes).

## Grant Permissions

When the app opens, you'll need to grant these permissions:

### Usage Access (Required)
1. App will show a prompt
2. Tap to go to Settings
3. Find "ParentLock" in the list
4. **Enable** the toggle

### Overlay Permission (Required)
1. Go to: Settings → Apps → Special Access → Display over other apps
2. Find "ParentLock"
3. **Enable** it

### Disable Battery Optimization (Recommended)
1. Go to: Settings → Apps → ParentLock → Battery
2. Select "Unrestricted"

---

# Part 3: Test the Features

## Test Checklist

- [ ] Register a new account
- [ ] Login with email
- [ ] Login with Google
- [ ] Set role as Parent
- [ ] Set role as Child (on second device/account)
- [ ] Link child to parent using code
- [ ] Parent sets app limits
- [ ] Child exceeds limit → App gets blocked
- [ ] Parent receives notification

---

## Troubleshooting

**App won't install**
```bash
flutter clean
flutter pub get
flutter run
```

**Google Sign-In not working**
- Check Client ID/Secret in Supabase
- Make sure SHA-1 matches your debug key

**Phone not detected**
- Reconnect USB cable
- Enable USB Debugging again
- Try a different cable

**Permissions not saving**
- Uninstall app completely
- Run `flutter run` again

---

## 🎉 You're Done!

Your ParentLock app is ready for Android testing!
