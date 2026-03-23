import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parentlock/services/native_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.parentlock.parentlock/native');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'getFullUsageStats preserves app_category from native payload',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getUsageStats') {
          return [
            {
              'app_package_name': 'com.example.social',
              'app_display_name': 'Social App',
              'minutes_used': 42,
              'app_category': 'social',
            },
          ];
        }
        return null;
      });

      final service = NativeService();
      final stats = await service.getFullUsageStats();

      expect(stats, hasLength(1));
      expect(stats.first['packageName'], 'com.example.social');
      expect(stats.first['app_category'], 'social');
    },
  );
}
