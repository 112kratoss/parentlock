
import 'parentlock_native_platform_interface.dart';

class ParentlockNative {
  Future<String?> getPlatformVersion() {
    return ParentlockNativePlatform.instance.getPlatformVersion();
  }
}
