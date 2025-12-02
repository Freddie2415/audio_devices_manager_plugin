// This is a basic Flutter integration test.
//
// Since integration tests run in a full Flutter application, they can interact
// with the host side of a plugin implementation, unlike Dart unit tests.
//
// For more information about Flutter integration tests, please see
// https://flutter.dev/to/integration-testing


import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:audio_devices_manager/audio_devices_manager.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Initialize audio devices manager', (WidgetTester tester) async {
    // Initialize the audio manager
    await AudioDevicesManager.initialize();

    // Get available inputs
    final inputs = await AudioDevicesManager.getAvailableInputs();

    // Should have at least one input device (built-in microphone)
    expect(inputs.isNotEmpty, true);

    // Each input should have uid and portName
    for (final input in inputs) {
      expect(input['uid'], isNotNull);
      expect(input['portName'], isNotNull);
    }
  });
}
