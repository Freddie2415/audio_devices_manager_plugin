import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'audio_devices_manager_method_channel.dart';

abstract class AudioDevicesManagerPlatform extends PlatformInterface {
  /// Constructs a AudioDevicesManagerPlatform.
  AudioDevicesManagerPlatform() : super(token: _token);

  static final Object _token = Object();

  static AudioDevicesManagerPlatform _instance = MethodChannelAudioDevicesManager();

  /// The default instance of [AudioDevicesManagerPlatform] to use.
  ///
  /// Defaults to [MethodChannelAudioDevicesManager].
  static AudioDevicesManagerPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [AudioDevicesManagerPlatform] when
  /// they register themselves.
  static set instance(AudioDevicesManagerPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
