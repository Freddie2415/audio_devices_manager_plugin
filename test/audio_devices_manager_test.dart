import 'package:flutter_test/flutter_test.dart';
import 'package:audio_devices_manager/audio_devices_manager_platform_interface.dart';
import 'package:audio_devices_manager/audio_devices_manager_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockAudioDevicesManagerPlatform
    with MockPlatformInterfaceMixin
    implements AudioDevicesManagerPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final AudioDevicesManagerPlatform initialPlatform = AudioDevicesManagerPlatform.instance;

  test('$MethodChannelAudioDevicesManager is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelAudioDevicesManager>());
  });

  test('getPlatformVersion', () async {
    MockAudioDevicesManagerPlatform fakePlatform = MockAudioDevicesManagerPlatform();
    AudioDevicesManagerPlatform.instance = fakePlatform;

    // expect(await AudioDevicesManager.getPlatformVersion(), '42');
  });
}
