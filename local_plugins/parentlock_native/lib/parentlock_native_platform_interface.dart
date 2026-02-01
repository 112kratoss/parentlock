import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'parentlock_native_method_channel.dart';

abstract class ParentlockNativePlatform extends PlatformInterface {
  /// Constructs a ParentlockNativePlatform.
  ParentlockNativePlatform() : super(token: _token);

  static final Object _token = Object();

  static ParentlockNativePlatform _instance = MethodChannelParentlockNative();

  /// The default instance of [ParentlockNativePlatform] to use.
  ///
  /// Defaults to [MethodChannelParentlockNative].
  static ParentlockNativePlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [ParentlockNativePlatform] when
  /// they register themselves.
  static set instance(ParentlockNativePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
