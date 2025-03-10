import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'audio_devices_manager_platform_interface.dart';

/// An implementation of [AudioDevicesManagerPlatform] that uses method channels.
class MethodChannelAudioDevicesManager extends AudioDevicesManagerPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('audio_devices_manager');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
