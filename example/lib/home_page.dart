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

  List<Map> _availableInputs = [];
  Map? _selectedInput;

  List<Map> _availableDataSources = [];
  Map? _selectedDataSource;

  bool _permissionsGranted = false;
  String _permissionStatus = 'Checking permissions...';

  @override
  void initState() {
    super.initState();
    _requestPermissionsAndInit();
  }

  Future<void> _requestPermissionsAndInit() async {
    // Запрашиваем необходимые permissions
    final micPermission = await Permission.microphone.request();

    bool bluetoothGranted = true;
    if (Platform.isAndroid) {
      // На Android 12+ нужно разрешение для Bluetooth
      if (await Permission.bluetoothConnect.isDenied) {
        final btPermission = await Permission.bluetoothConnect.request();
        bluetoothGranted = btPermission.isGranted || btPermission.isPermanentlyDenied;
      }
    }

    setState(() {
      _permissionsGranted = micPermission.isGranted;
      if (_permissionsGranted) {
        _permissionStatus = 'Permissions granted ✓';
      } else if (micPermission.isPermanentlyDenied) {
        _permissionStatus = 'Permissions permanently denied. Please enable in settings.';
      } else {
        _permissionStatus = 'Permissions denied. App may not work correctly.';
      }
    });

    if (_permissionsGranted) {
      await _initAudioManager();
    }
  }

  Future<void> _initAudioManager() async {
    // Инициализируем аудио
    await AudioDevicesManager.initialize();

    // Подписываемся на события
    _subscription = AudioDevicesManager.deviceEvents().listen((event) {
      // event — это Map c полями: availableInputs, selectedInput, ...
      print('📡 [AudioDevices] Event received:');
      print('   Available inputs: ${event['availableInputs']}');
      print('   Selected input: ${event['selectedInput']}');
      print('   Available data sources: ${event['availableDataSources']}');
      print('   Selected data source: ${event['selectedDataSource']}');

      setState(() {
        _availableInputs = List<Map>.from(
          event['availableInputs'] as List,
        );

        if (event['selectedInput'] != null && event['selectedInput'] is Map) {
          _selectedInput = Map.from(event['selectedInput']);
        } else {
          _selectedInput = null;
        }

        _availableDataSources = List<Map>.from(
          event['availableDataSources'] ?? [],
        );

        if (event['selectedDataSource'] != null &&
            event['selectedDataSource'] is Map) {
          _selectedDataSource = Map.from(
            event['selectedDataSource'],
          );
        } else {
          _selectedDataSource = null;
        }
      });
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

          // Перечисляем входы
          ..._availableInputs.map((input) {
            final isSelected = (input['uid'] == _selectedInput?['uid']);
            return ListTile(
              title: Text(input['portName'] ?? 'Unnamed'),
              subtitle: Text("UID: ${input['uid']}"),
              trailing: isSelected ? const Icon(Icons.check) : null,
              onTap: () {
                print('🎤 [User] Selecting input: ${input['portName']} (${input['uid']})');
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
                print('🎚️ [User] Selecting data source: ${ds['dataSourceName']} (${ds['dataSourceID']})');
                AudioDevicesManager.selectDataSource(ds['dataSourceID']);
              },
            );
          }),
        ],
      ),
    );
  }
}
