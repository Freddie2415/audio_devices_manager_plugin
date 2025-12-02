import 'package:flutter/services.dart';

class AudioDevicesManager {
  // For one-time requests
  static const MethodChannel _methodChannel = MethodChannel(
    'audio_devices_manager',
  );

  // For event streams
  static const EventChannel _eventChannel = EventChannel(
    'audio_devices_manager_events',
  );

  /// Initialize audio session
  static Future<void> initialize() async {
    await _methodChannel.invokeMethod('initialize');
  }

  /// Get list of available inputs (microphones)
  static Future<List<Map<String, dynamic>>> getAvailableInputs() async {
    final List<dynamic> result = await _methodChannel.invokeMethod(
      'getAvailableInputs',
    );
    return result.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  /// Select input by uid
  static Future<void> selectInput(String uid) async {
    await _methodChannel.invokeMethod('selectInput', {'uid': uid});
  }

  /// Get currently selected input
  static Future<Map<String, dynamic>?> getSelectedInput() async {
    final result = await _methodChannel.invokeMethod('getSelectedInput');
    if (result == null) return null;
    return Map<String, dynamic>.from(result);
  }

  /// Get list of available data sources
  static Future<List<Map<String, dynamic>>> getAvailableDataSources() async {
    final List<dynamic> result = await _methodChannel.invokeMethod(
      'getAvailableDataSources',
    );
    return result.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  /// Select data source by ID
  static Future<void> selectDataSource(int dataSourceID) async {
    await _methodChannel.invokeMethod('selectDataSource', {
      'dataSourceID': dataSourceID,
    });
  }

  /// Subscribe to events (device list changes, selection changes, etc.)
  /// Each event comes as `Map<String, dynamic>`:
  /// {
  ///   "availableInputs": [ { uid, portName }, ... ],
  ///   "selectedInput": { uid, portName } or null,
  ///   "availableOutputs": [ { uid, portName }, ... ],
  ///   "selectedOutput": { uid, portName } or null,
  ///   "availableDataSources": [ { dataSourceID, dataSourceName }, ... ],
  ///   "selectedDataSource": { dataSourceID, dataSourceName } or null,
  /// }
  static Stream<Map<String, dynamic>> deviceEvents() {
    return _eventChannel.receiveBroadcastStream().map((event) {
      return Map<String, dynamic>.from(event);
    });
  }

  /// Get selected input device ID (Android device ID)
  /// This ID can be used for AudioRecord.setPreferredDevice()
  /// On iOS returns null since device selection is applied automatically
  static Future<int?> getSelectedInputDeviceId() async {
    final result = await _methodChannel.invokeMethod('getSelectedInputDeviceId');
    return result as int?;
  }

  /// ========== OUTPUT DEVICES (OUTPUTS) ==========

  /// Get list of available outputs (speakers, headphones, Bluetooth)
  static Future<List<Map<String, dynamic>>> getAvailableOutputs() async {
    final List<dynamic> result = await _methodChannel.invokeMethod(
      'getAvailableOutputs',
    );
    return result.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  /// Select output by uid
  /// Android: full control - can select specific device
  /// iOS: limited control - uses system settings
  static Future<void> selectOutput(String uid) async {
    await _methodChannel.invokeMethod('selectOutput', {'uid': uid});
  }

  /// Get currently selected output
  static Future<Map<String, dynamic>?> getSelectedOutput() async {
    final result = await _methodChannel.invokeMethod('getSelectedOutput');
    if (result == null) return null;
    return Map<String, dynamic>.from(result);
  }

  /// Get selected output device ID (Android device ID)
  /// This ID can be used for AudioTrack.setPreferredDevice()
  /// On iOS returns null
  static Future<int?> getSelectedOutputDeviceId() async {
    final result = await _methodChannel.invokeMethod('getSelectedOutputDeviceId');
    return result as int?;
  }

  /// ========== IOS SPECIFIC OUTPUT CONTROL ==========

  /// iOS: Enable/disable built-in speaker
  /// Android: this method has no effect (use selectOutput)
  static Future<void> setDefaultToSpeaker(bool enable) async {
    await _methodChannel.invokeMethod('setDefaultToSpeaker', {'enable': enable});
  }

  /// iOS: Show system Route Picker for user device selection
  /// Android: this method has no effect
  static Future<void> showRoutePicker() async {
    await _methodChannel.invokeMethod('showRoutePicker');
  }

  /// (Optional) Dispose plugin resources
  static Future<void> dispose() async {
    await _methodChannel.invokeMethod('dispose');
  }
}
