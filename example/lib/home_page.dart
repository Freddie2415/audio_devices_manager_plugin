import 'dart:async';
import 'dart:io';

import 'package:audio_devices_manager/audio_devices_manager.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  StreamSubscription<Map<String, dynamic>>? _subscription;

  List<Map<String, dynamic>> _availableInputs = [];
  Map<String, dynamic>? _selectedInput;

  List<Map<String, dynamic>> _availableDataSources = [];
  Map<String, dynamic>? _selectedDataSource;

  bool _permissionsGranted = false;
  bool _bluetoothGranted = false;
  String _permissionStatus = 'Checking permissions...';
  int? _androidDeviceId;

  @override
  void initState() {
    super.initState();
    _requestPermissionsAndInit();
  }

  Future<void> _requestPermissionsAndInit() async {
    // Запрашиваем только Bluetooth permission для получения имен устройств
    bool bluetoothGranted = true;
    if (Platform.isAndroid) {
      // На Android 12+ нужно разрешение для Bluetooth
      if (await Permission.bluetoothConnect.isDenied) {
        final btPermission = await Permission.bluetoothConnect.request();
        bluetoothGranted = btPermission.isGranted || btPermission.isPermanentlyDenied;
      }
    }

    setState(() {
      _permissionsGranted = true; // Микрофон не требуется для перечисления устройств
      _bluetoothGranted = bluetoothGranted;

      if (!_bluetoothGranted && Platform.isAndroid) {
        _permissionStatus = 'Bluetooth permission denied (device names may not show correctly)';
      } else {
        _permissionStatus = 'Ready to enumerate audio devices ✓';
      }
    });

    await _initAudioManager();
  }

  Future<void> _initAudioManager() async {
    // Инициализируем аудио
    await AudioDevicesManager.initialize();

    // Подписываемся на события
    _subscription = AudioDevicesManager.deviceEvents().listen((event) {
      // event — это Map c полями: availableInputs, selectedInput, ...
      debugPrint('📡 [AudioDevices] Event received:');
      debugPrint('   Available inputs: ${event['availableInputs']}');
      debugPrint('   Selected input: ${event['selectedInput']}');
      debugPrint('   Available data sources: ${event['availableDataSources']}');
      debugPrint('   Selected data source: ${event['selectedDataSource']}');

      setState(() {
        _availableInputs = (event['availableInputs'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

        if (event['selectedInput'] != null && event['selectedInput'] is Map) {
          _selectedInput = Map<String, dynamic>.from(event['selectedInput'] as Map);
        } else {
          _selectedInput = null;
        }

        _availableDataSources = (event['availableDataSources'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

        if (event['selectedDataSource'] != null &&
            event['selectedDataSource'] is Map) {
          _selectedDataSource = Map<String, dynamic>.from(
            event['selectedDataSource'] as Map,
          );
        } else {
          _selectedDataSource = null;
        }
      });

      // Обновляем Android Device ID при изменении выбранного устройства
      if (Platform.isAndroid && event['selectedInput'] != null) {
        _updateAndroidDeviceId();
      }
    });
  }

  Future<void> _updateAndroidDeviceId() async {
    if (!Platform.isAndroid) return;

    final deviceId = await AudioDevicesManager.getSelectedInputDeviceId();
    setState(() {
      _androidDeviceId = deviceId;
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Audio Devices Manager Demo")),
      body: Column(
        children: [
          const SizedBox(height: 16),

          // Показываем статус permissions
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _permissionsGranted ? Colors.green.shade50 : Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _permissionsGranted ? Colors.green : Colors.red,
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _permissionsGranted ? Icons.check_circle : Icons.error,
                    color: _permissionsGranted ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _permissionStatus,
                      style: TextStyle(
                        color: _permissionsGranted ? Colors.green.shade900 : Colors.red.shade900,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (!_permissionsGranted)
                    TextButton(
                      onPressed: () {
                        openAppSettings();
                      },
                      child: const Text('Settings'),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),
          const Text("Available Inputs:", style: TextStyle(fontSize: 16)),

          // Показываем Android Device ID (важно для интеграции с записью)
          if (Platform.isAndroid && _androidDeviceId != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue, width: 1),
              ),
              child: Row(
                children: [
                  const Icon(Icons.android, color: Colors.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Android Device ID',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'ID: $_androidDeviceId',
                          style: const TextStyle(fontSize: 12),
                        ),
                        const Text(
                          'Use this ID for AudioRecord.setPreferredDevice()',
                          style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // Перечисляем входы
          ..._availableInputs.map((input) {
            final isSelected = (input['uid'] == _selectedInput?['uid']);
            return ListTile(
              title: Text(input['portName'] ?? 'Unnamed'),
              subtitle: Text("UID: ${input['uid']}"),
              trailing: isSelected ? const Icon(Icons.check) : null,
              onTap: () {
                debugPrint('🎤 [User] Selecting input: ${input['portName']} (${input['uid']})');
                AudioDevicesManager.selectInput(input['uid']);
              },
            );
          }),

          const Divider(),

          Text(
            "Selected Data Source: ${_selectedDataSource?['dataSourceName'] ?? 'None'}",
          ),
          const Text("Available Data Sources:", style: TextStyle(fontSize: 16)),

          // Перечисляем dataSources
          ..._availableDataSources.map((ds) {
            final isSelected =
                ds['dataSourceID'] == _selectedDataSource?['dataSourceID'];
            return ListTile(
              title: Text(ds['dataSourceName']?.toString() ?? 'Unknown'),
              subtitle: Text("ID: ${ds['dataSourceID']}"),
              trailing: isSelected ? const Icon(Icons.check) : null,
              onTap: () {
                debugPrint('🎚️ [User] Selecting data source: ${ds['dataSourceName']} (${ds['dataSourceID']})');
                AudioDevicesManager.selectDataSource(ds['dataSourceID']);
              },
            );
          }),
        ],
      ),
    );
  }
}
