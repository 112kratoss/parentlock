# Screen Time Extension Scaffold

These files are the checked-in source scaffold for the iOS Screen Time work that
still needs to be wired into real Xcode targets.

What is already in the repo:
- `Runner.entitlements` with the Family Controls entitlement and the shared App Group
- placeholder Swift sources for Device Activity and Managed Settings extension points
- the Flutter app now reports iOS support honestly instead of claiming monitoring works

What still needs to happen in Xcode:
1. Create real extension targets for Device Activity Monitor and Shield Configuration.
2. Attach the same App Group and Family Controls capability to each target.
3. Add these Swift files to the new targets and provide the target-specific `Info.plist` files.
4. Test on a real iPhone signed with the correct Apple team and Screen Time entitlement.
