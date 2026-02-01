import 'package:flutter_test/flutter_test.dart';
import 'package:parentlock_native/parentlock_native.dart';
import 'package:parentlock_native/parentlock_native_platform_interface.dart';
import 'package:parentlock_native/parentlock_native_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockParentlockNativePlatform
    with MockPlatformInterfaceMixin
    implements ParentlockNativePlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final ParentlockNativePlatform initialPlatform = ParentlockNativePlatform.instance;

  test('$MethodChannelParentlockNative is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelParentlockNative>());
  });

  test('getPlatformVersion', () async {
    ParentlockNative parentlockNativePlugin = ParentlockNative();
    MockParentlockNativePlatform fakePlatform = MockParentlockNativePlatform();
    ParentlockNativePlatform.instance = fakePlatform;

    expect(await parentlockNativePlugin.getPlatformVersion(), '42');
  });
}
