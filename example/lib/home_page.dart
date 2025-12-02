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

  List<Map<String, dynamic>> _availableOutputs = [];
  Map<String, dynamic>? _selectedOutput;

  bool _permissionsGranted = false;
  bool _bluetoothGranted = false;
  String _permissionStatus = 'Checking permissions...';
  int? _androidInputDeviceId;
  int? _androidOutputDeviceId;

  @override
  void initState() {
    super.initState();
    _requestPermissionsAndInit();
  }

  Future<void> _requestPermissionsAndInit() async {
    // Request only Bluetooth permission to get device names
    bool bluetoothGranted = true;
    if (Platform.isAndroid) {
      // On Android 12+ we need Bluetooth permission
      if (await Permission.bluetoothConnect.isDenied) {
        final btPermission = await Permission.bluetoothConnect.request();
        bluetoothGranted = btPermission.isGranted || btPermission.isPermanentlyDenied;
      }
    }

    setState(() {
      _permissionsGranted = true; // Microphone not required for device enumeration
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
    // Initialize audio
    await AudioDevicesManager.initialize();

    // Subscribe to events
    _subscription = AudioDevicesManager.deviceEvents().listen((event) {
      // event is a Map with fields: availableInputs, selectedInput, availableOutputs, selectedOutput, ...
      debugPrint('📡 [AudioDevices] Event received:');
      debugPrint('   Available inputs: ${event['availableInputs']}');
      debugPrint('   Selected input: ${event['selectedInput']}');
      debugPrint('   Available outputs: ${event['availableOutputs']}');
      debugPrint('   Selected output: ${event['selectedOutput']}');
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

        _availableOutputs = (event['availableOutputs'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

        if (event['selectedOutput'] != null && event['selectedOutput'] is Map) {
          _selectedOutput = Map<String, dynamic>.from(event['selectedOutput'] as Map);
        } else {
          _selectedOutput = null;
        }
      });

      // Update Android Device IDs when selected devices change
      if (Platform.isAndroid) {
        _updateAndroidDeviceIds();
      }
    });
  }

  Future<void> _updateAndroidDeviceIds() async {
    if (!Platform.isAndroid) return;

    final inputDeviceId = await AudioDevicesManager.getSelectedInputDeviceId();
    final outputDeviceId = await AudioDevicesManager.getSelectedOutputDeviceId();

    setState(() {
      _androidInputDeviceId = inputDeviceId;
      _androidOutputDeviceId = outputDeviceId;
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
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 16),

            // Show permissions status
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

            // Show Android Device ID (important for recording integration)
            if (Platform.isAndroid && _androidInputDeviceId != null)
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
                            'Android Input Device ID',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'ID: $_androidInputDeviceId',
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

            // List inputs
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

            // List data sources
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

            const Divider(height: 32, thickness: 2),

            // ========== OUTPUT DEVICES SECTION ==========
            const Text(
              "Available Outputs:",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                Platform.isAndroid
                    ? "Android: Full control - select any output device"
                    : "iOS: Limited control - system decides the output",
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Show Android Output Device ID
            if (Platform.isAndroid && _androidOutputDeviceId != null)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange, width: 1),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.android, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Android Output Device ID',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'ID: $_androidOutputDeviceId',
                            style: const TextStyle(fontSize: 12),
                          ),
                          const Text(
                            'Use this ID for AudioTrack.setPreferredDevice()',
                            style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            // List outputs
            ..._availableOutputs.map((output) {
              final isSelected = (output['uid'] == _selectedOutput?['uid']);
              return ListTile(
                leading: Icon(
                  _getOutputIcon(output['portName'] ?? ''),
                  color: isSelected ? Colors.green : Colors.grey,
                ),
                title: Text(output['portName'] ?? 'Unnamed'),
                subtitle: Text("UID: ${output['uid']}"),
                trailing: isSelected ? const Icon(Icons.check, color: Colors.green) : null,
                onTap: () {
                  debugPrint('🔊 [User] Selecting output: ${output['portName']} (${output['uid']})');
                  AudioDevicesManager.selectOutput(output['uid']);
                },
              );
            }),

            if (_availableOutputs.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'No output devices available',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Helper method to select icon for output device
  IconData _getOutputIcon(String portName) {
    final lowerName = portName.toLowerCase();
    if (lowerName.contains('bluetooth')) {
      return Icons.bluetooth_audio;
    } else if (lowerName.contains('speaker')) {
      return Icons.volume_up;
    } else if (lowerName.contains('earpiece')) {
      return Icons.phone;
    } else if (lowerName.contains('headphone') || lowerName.contains('headset')) {
      return Icons.headphones;
    } else if (lowerName.contains('usb')) {
      return Icons.usb;
    } else {
      return Icons.speaker;
    }
  }
}
