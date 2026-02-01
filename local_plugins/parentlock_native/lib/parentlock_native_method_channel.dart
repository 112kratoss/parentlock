import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'parentlock_native_platform_interface.dart';

/// An implementation of [ParentlockNativePlatform] that uses method channels.
class MethodChannelParentlockNative extends ParentlockNativePlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('parentlock_native');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
