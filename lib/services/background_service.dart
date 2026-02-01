import 'package:workmanager/workmanager.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:parentlock/services/database_service.dart';
import 'package:parentlock/services/native_service.dart';
import 'package:parentlock/config/supabase_config.dart';
import 'package:flutter/foundation.dart';

const String backgroundSyncTask = "backgroundSyncTask";

@pragma('vm:entry-point') 
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    switch (task) {
      case backgroundSyncTask:
        print("Native called background task: $backgroundSyncTask");
        try {
          // Initialize Supabase
          await _initializeSupabase();
          
          final nativeService = NativeService();
          final databaseService = DatabaseService();

          // Get the current session user
          final session = Supabase.instance.client.auth.currentSession;
          final user = Supabase.instance.client.auth.currentUser;

          if (user != null) {
              print("Starting background sync for user: ${user.id}");
              
              // 1. Get stats from native
              final fullUsageStats = await nativeService.getFullUsageStats();
              
              // 2. Sync to Supabase
              await databaseService.syncAllUsageStats(
                childId: user.id,
                fullUsageStats: fullUsageStats,
              );
              
              // 3. Enforce Blocking (Get latest rules from DB)
              final blockedApps = await databaseService.getBlockedApps(user.id);
              await nativeService.updateBlockedApps(blockedApps);
              print("Background enforcement updated: ${blockedApps.length} apps blocked");
              
              print("Background sync completed successfully");
          } else {
              print("No active user in background, skipping sync");
          }

        } catch (err) {
          print("Background sync failed: $err");
          return Future.value(false);
        }
        break;
    }
    return Future.value(true);
  });
}

Future<void> _initializeSupabase() async {
  await Supabase.initialize(
    url: SupabaseConfig.supabaseUrl,
    anonKey: SupabaseConfig.supabaseAnonKey,
  );
}

class BackgroundService {
  static final BackgroundService _instance = BackgroundService._internal();

  factory BackgroundService() {
    return _instance;
  }

  BackgroundService._internal();

  Future<void> initialize() async {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: kDebugMode, 
    );
  }

  void registerPeriodicTask() {
    Workmanager().registerPeriodicTask(
      "1", 
      backgroundSyncTask,
      frequency: const Duration(minutes: 15), 
      constraints: Constraints(
        networkType: NetworkType.connected, 
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    );
  }
}
