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
        debugPrint('Native called background task: $backgroundSyncTask');
        try {
          // Initialize Supabase
          await _initializeSupabase();

          final nativeService = NativeService();
          final databaseService = DatabaseService();
          final platformStatus = await nativeService.getPlatformStatus();

          // Get the current session user
          final user = Supabase.instance.client.auth.currentUser;

          if (user != null) {
            debugPrint('Starting background sync for user: ${user.id}');

            // 1. Get stats from native
            final fullUsageStats = await nativeService.getFullUsageStats();

            // 2. Sync to Supabase
            await databaseService.syncAllUsageStats(
              childId: user.id,
              fullUsageStats: fullUsageStats,
            );

            // 3. Enforce Blocking (Get latest rules from DB)
            if (platformStatus.appBlockingSupported) {
              final blockedApps = await databaseService.getBlockedApps(user.id);
              await nativeService.updateBlockedApps(blockedApps);
              debugPrint(
                'Background enforcement updated: ${blockedApps.length} apps blocked',
              );
            }

            debugPrint('Background sync completed successfully');
          } else {
            debugPrint('No active user in background, skipping sync');
          }
        } catch (err) {
          debugPrint('Background sync failed: $err');
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
    await Workmanager().initialize(callbackDispatcher);
  }

  void registerPeriodicTask() {
    Workmanager().registerPeriodicTask(
      "1",
      backgroundSyncTask,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    );
  }
}
