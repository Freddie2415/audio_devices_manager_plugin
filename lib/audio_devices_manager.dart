import 'package:flutter/services.dart';

class AudioDevicesManager {
  // Для одноразовых запросов
  static const MethodChannel _methodChannel = MethodChannel(
    'audio_devices_manager',
  );

  // Для стримов событий
  static const EventChannel _eventChannel = EventChannel(
    'audio_devices_manager_events',
  );

  /// Инициализируем аудиосессию
  static Future<void> initialize() async {
    await _methodChannel.invokeMethod('initialize');
  }

  /// Получить список доступных входов (микрофонов)
  static Future<List<Map<String, dynamic>>> getAvailableInputs() async {
    final List<dynamic> result = await _methodChannel.invokeMethod(
      'getAvailableInputs',
    );
    return result.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  /// Выбрать вход по uid
  static Future<void> selectInput(String uid) async {
    await _methodChannel.invokeMethod('selectInput', {'uid': uid});
  }

  /// Узнать, какой вход сейчас выбран
  static Future<Map<String, dynamic>?> getSelectedInput() async {
    final result = await _methodChannel.invokeMethod('getSelectedInput');
    if (result == null) return null;
    return Map<String, dynamic>.from(result);
  }

  /// Получить список dataSources
  static Future<List<Map<String, dynamic>>> getAvailableDataSources() async {
    final List<dynamic> result = await _methodChannel.invokeMethod(
      'getAvailableDataSources',
    );
    return result.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  /// Выбрать dataSource по ID
  static Future<void> selectDataSource(int dataSourceID) async {
    await _methodChannel.invokeMethod('selectDataSource', {
      'dataSourceID': dataSourceID,
    });
  }

  /// Подписаться на события (изменения списка устройств, выбора и т. д.)
  /// Каждый ивент приходит в виде Map<String, dynamic>:
  /// {
  ///   "availableInputs": [ { uid, portName }, ... ],
  ///   "selectedInput": { uid, portName } или null,
  ///   "availableDataSources": [ { dataSourceID, dataSourceName }, ... ],
  ///   "selectedDataSource": { dataSourceID, dataSourceName } или null,
  /// }
  static Stream<Map<String, dynamic>> deviceEvents() {
    return _eventChannel.receiveBroadcastStream().map((event) {
      return Map<String, dynamic>.from(event);
    });
  }

  /// Получить ID выбранного входного устройства (Android device ID)
  /// Этот ID можно использовать для AudioRecord.setPreferredDevice()
  /// На iOS возвращает null, так как выбор устройства применяется автоматически
  static Future<int?> getSelectedInputDeviceId() async {
    final result = await _methodChannel.invokeMethod('getSelectedInputDeviceId');
    return result as int?;
  }

  /// (Опционально) Чтобы «выключить» плагин, если реализовать dispose() в Swift
  static Future<void> dispose() async {
    // Можно сделать метод на MethodChannel, если нужна деактивация
    await _methodChannel.invokeMethod('dispose');
  }
}
