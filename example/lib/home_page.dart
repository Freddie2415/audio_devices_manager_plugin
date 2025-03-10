import 'dart:async';

import 'package:audio_devices_manager/audio_devices_manager.dart';
import 'package:flutter/material.dart';

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

  @override
  void initState() {
    super.initState();
    _initAudioManager();
  }

  Future<void> _initAudioManager() async {
    // Инициализируем аудио
    await AudioDevicesManager.initialize();

    // Подписываемся на события
    _subscription = AudioDevicesManager.deviceEvents().listen((event) {
      // event — это Map c полями: availableInputs, selectedInput, ...
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
          const Text("Available Inputs:", style: TextStyle(fontSize: 16)),

          // Перечисляем входы
          ..._availableInputs.map((input) {
            final isSelected = (input['uid'] == _selectedInput?['uid']);
            return ListTile(
              title: Text(input['portName'] ?? 'Unnamed'),
              subtitle: Text("UID: ${input['uid']}"),
              trailing: isSelected ? const Icon(Icons.check) : null,
              onTap: () => AudioDevicesManager.selectInput(input['uid']),
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
              onTap:
                  () =>
                      AudioDevicesManager.selectDataSource(ds['dataSourceID']),
            );
          }),
        ],
      ),
    );
  }
}
