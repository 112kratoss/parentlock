# iOS Setup Guide for ParentLock

## 📱 Important Information First

**Before you start:**
- iOS parental controls only work on **real iPhones** (not the simulator on your computer)
- Your iPhone needs to be running **iOS 15 or newer**
- You'll need a Mac computer with Xcode installed
- This setup takes about 10-15 minutes

---

## Step 1: Open the Project in Xcode

### What is Xcode?
Xcode is Apple's tool for building iPhone apps. We need to use it to configure special permissions.

### How to open:
1. On your Mac, open the **Terminal** app (you can find it using Spotlight - press `Command + Space` and type "Terminal")
2. Copy and paste this command, then press Enter:
   ```bash
   cd /Users/athuls/parentlock/ios
   open Runner.xcworkspace
   ```
3. Wait for Xcode to open (it might take a minute)

**✅ You'll know it worked when**: A window opens showing files on the left side with "Runner" at the top.

---

## Step 2: Select Your Team (Apple Developer Account)

### Why do we need this?
Apple requires you to sign apps with your Apple ID to run them on your iPhone.

### Steps:
1. In Xcode, **look at the left sidebar** with all the files
2. **Click on the very top item** that says "Runner" (it has a blue icon)
3. **Look at the main area** - you should see tabs like "General", "Signing & Capabilities", etc.
4. **Click on "Signing & Capabilities"** tab
5. Under "Signing", you'll see a dropdown that says "Team"
6. **Click the Team dropdown** and select your Apple ID
   - If you don't see your Apple ID, click "Add Account..." and sign in with your Apple ID
   - You can use your regular Apple ID (no paid developer account needed for testing)

**✅ You'll know it worked when**: 
- The "Team" dropdown shows your name or Apple ID
- You don't see any red error messages

**⚠️ If you see errors**:
- "Failed to create provisioning profile" → This is normal, just continue
- "No signing certificate" → Click "Try Again" or "Download Manual Profiles"

---

## Step 3: Add Family Controls Permission

### Why do we need this?
This gives the app permission to monitor and control app usage on the iPhone.

### Steps:
1. **Make sure you're still on the "Signing & Capabilities" tab**
2. **Look for a "+ Capability" button** near the top (it might be small)
3. **Click "+ Capability"**
4. A popup list will appear - **scroll down and find "Family Controls"**
5. **Click on "Family Controls"** to add it

**✅ You'll know it worked when**: 
- You see a new section appear called "Family Controls" under the Signing section
- It should NOT have any red error icons

---

## Step 4: Add App Groups

### Why do we need this?
This allows different parts of the app to share data securely.

### Steps:
1. **Still on "Signing & Capabilities" tab**, click **"+ Capability"** again
2. **Scroll down and find "App Groups"**
3. **Click on "App Groups"** to add it
4. You'll see a new "App Groups" section appear
5. **Click the small "+" button** under "App Groups"
6. **Type this exactly**: `group.com.parentlock.parentlock`
7. **Press Enter** or click outside the text box

**✅ You'll know it worked when**: 
- You see a checkbox with "group.com.parentlock.parentlock" next to it
- The checkbox should be **checked** (has a checkmark)

---

## Step 5: Set iOS Version Requirement

### Why do we need this?
Family Controls only works on iOS 15 and newer.

### Steps:
1. **Click on the "General" tab** (it's next to "Signing & Capabilities")
2. **Look for "Deployment Info"** section
3. **Find the "iOS" dropdown** (it shows a version number like "14.0" or "15.0")
4. **Click the dropdown** and select **"15.0"** or higher

**✅ You'll know it worked when**: The iOS version shows 15.0 or higher

---

## Step 6: Ready to Build!

### You're all set! Now let's test it:

1. **Connect your iPhone** to your Mac with a USB cable
2. **Unlock your iPhone** and tap "Trust This Computer" if asked
3. **Go back to Terminal** and run:
   ```bash
   cd /Users/athuls/parentlock
   flutter run
   ```
4. **Wait** - the first build takes 5-10 minutes
5. **On your iPhone**: You might see "Untrusted Developer" 
   - Go to **Settings → General → VPN & Device Management**
   - Tap on your email/name
   - Tap **"Trust [your name]"**
   - Tap **"Trust"** again to confirm

### First time running the app:
The app will ask for permission to use Family Controls. This is normal - tap "Allow"!

---

## 🆘 Troubleshooting

### "No supported iOS devices available"
- Make sure your iPhone is **unlocked** and **connected via USB**
- Check that you tapped **"Trust This Computer"** on your iPhone
- Try **unplugging and re-plugging** the cable

### "Signing requires a development team"
- Go back to **Step 2** and make sure you selected a Team
- If you still have issues, try signing out and back into your Apple ID in Xcode:
  - **Xcode → Settings → Accounts** → Click "-" to remove account, then "+" to add it back

### "Family Controls Not Working"
- Family Controls **ONLY works on real iPhones** (not the Simulator)
- Your iPhone must be running **iOS 15 or newer**
- Check: Settings → General → About → iOS Version

### "App Crashes Immediately"
- Make sure you **allowed permissions** when the app asked
- Try **deleting the app** from your iPhone and running `flutter run` again

---

## ℹ️ Additional Notes

### What Family Controls Does:
- Allows the app to see which apps are running
- Lets the app block access to specific apps
- Requires user permission each time (you can't secretly monitor someone)

### Privacy & Safety:
- The child's iPhone must **give permission** for monitoring
- Works best when both parent and child phones are in the same iCloud Family
- All data is stored securely in your Supabase database

### Testing Tips:
- Test on a **real iPhone** (simulator won't work)
- You need at least **2 devices**: one parent, one child
- Both devices need to be signed into the app with different accounts

---

## ✅ Setup Complete!

Once you've completed all steps above, your iOS app is configured and ready to test. The Android version works without these extra steps!

**Need help?** Double-check each step above carefully - the most common issues are:
1. Forgetting to add Family Controls capability
2. Not selecting a Team for signing
3. Not creating the App Group correctly
