# ParentLock 🛡️

A Flutter application for parental control and child usage monitoring.

## 🚀 Getting Started for Collaborators

To run this project on your machine, follow these steps:

### 1. Prerequisites
- Install [Flutter SDK](https://docs.flutter.dev/get-started/install)
- Setup an editor (VS Code or Android Studio)
- Ensure you have a physical device or emulator/simulator ready.

### 2. Clone the Repository
```bash
git clone https://github.com/112kratoss/parentlock.git
cd parentlock
```

### 3. Setup Configuration (CRITICAL)
For security, Firebase configuration files are **not** included in the repository. You must obtain these from the project owner and place them in the correct directories:

- **Android**: Place `google-services.json` in `android/app/`
- **iOS**: Place `GoogleService-Info.plist` in `ios/Runner/`

> [!IMPORTANT]
> The app will not build or run without these files.

### 4. Install Dependencies
Run the following command in the project root:
```bash
flutter pub get
```

### 5. Run the App
```bash
flutter run
```

## Project Structure
- `lib/screens/`: UI screens for Parent and Child roles.
- `lib/services/`: Backend logic for Firebase, Supabase, and Native APIs.
- `lib/models/`: Data structures.
- `lib/app_router.dart`: Navigation configuration.
