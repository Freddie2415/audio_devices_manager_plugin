# Integration with Audio Recording Libraries

This guide explains how to integrate `audio_devices_manager` with audio recording libraries to ensure the user-selected input device is used for recording.

## 🎯 Goal

When a user selects an audio input device (e.g., Bluetooth headset), your recording should automatically use that device.

## 📱 Platform Differences

### iOS ✅ Works Automatically
On iOS, calling `AudioDevicesManager.selectInput()` sets the preferred input **globally** for the entire app. All recording APIs automatically use it:
- AVAudioRecorder
- AVAudioEngine
- Any Core Audio based recording

**No additional code needed!**

### Android ⚠️ Requires Integration
On Android, you must explicitly apply the selected device to your `AudioRecord` instance using `setPreferredDevice()`.

---

## 🔧 Integration Methods

### Method 1: Using Android Device ID (Recommended for Native Code)

If you're building your own native recording module or have access to `AudioRecord`:

```dart
import 'package:audio_devices_manager/audio_devices_manager.dart';

// User selects a device
await AudioDevicesManager.selectInput(deviceUid);

// Get the Android device ID
final deviceId = await AudioDevicesManager.getSelectedInputDeviceId();

if (deviceId != null) {
  // Pass this ID to your native Android code
  // and call audioRecord.setPreferredDevice()
}
```

**Native Android code:**
```kotlin
import android.media.AudioRecord
import android.media.AudioManager
import android.media.AudioDeviceInfo

class MyAudioRecorder(private val context: Context) {
    private var audioRecord: AudioRecord? = null

    fun applyPreferredDevice(deviceId: Int) {
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val devices = audioManager.getDevices(AudioManager.GET_DEVICES_INPUTS)

        val device = devices.firstOrNull { it.id == deviceId }
        if (device != null && audioRecord != null) {
            audioRecord?.setPreferredDevice(device)
        }
    }
}
```

### Method 2: Using MethodChannel (For Flutter Packages)

Create a custom MethodChannel to pass the device ID to your recording implementation:

**Dart side:**
```dart
import 'package:flutter/services.dart';

class MyRecordingService {
  static const _channel = MethodChannel('my_recording_service');

  Future<void> startRecording() async {
    // Get selected device ID
    final deviceId = await AudioDevicesManager.getSelectedInputDeviceId();

    // Pass to native code
    await _channel.invokeMethod('startRecording', {
      'deviceId': deviceId,
    });
  }
}
```

**Kotlin side:**
```kotlin
class MyRecordingPlugin : MethodCallHandler {
    private var audioRecord: AudioRecord? = null

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "startRecording" -> {
                val deviceId = call.argument<Int>("deviceId")

                // Create AudioRecord
                audioRecord = AudioRecord(...)

                // Apply preferred device if provided
                if (deviceId != null) {
                    applyPreferredDevice(deviceId)
                }

                audioRecord?.startRecording()
                result.success(null)
            }
        }
    }

    private fun applyPreferredDevice(deviceId: Int) {
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val device = audioManager.getDevices(AudioManager.GET_DEVICES_INPUTS)
            .firstOrNull { it.id == deviceId }

        device?.let {
            audioRecord?.setPreferredDevice(it)
        }
    }
}
```

---

## 📦 Integration with Popular Packages

### 1. Using `record` package

The `record` package uses native `MediaRecorder` / `AudioRecord`. You'll need to fork it or create a wrapper:

```dart
import 'package:record/record.dart';
import 'package:audio_devices_manager/audio_devices_manager.dart';

class ManagedAudioRecorder {
  final _recorder = AudioRecorder();

  Future<void> startRecording(String path) async {
    // Option A: If using custom fork with setPreferredDevice support
    final deviceId = await AudioDevicesManager.getSelectedInputDeviceId();
    await _recorder.start(
      path: path,
      preferredDeviceId: deviceId, // Custom parameter in forked version
    );

    // Option B: If package doesn't support it
    // You'll need to create a custom platform channel
  }
}
```

**Note:** The `record` package currently doesn't expose `setPreferredDevice()`. You may need to:
1. Fork the package and add this functionality
2. Create your own recording plugin
3. Use Method 2 above with a custom MethodChannel

### 2. Using `flutter_sound`

Similar approach - fork and add `setPreferredDevice()` support, or use a wrapper with MethodChannel.

### 3. Building Your Own Recorder

**Full example with AudioRecord:**

**Dart:**
```dart
class CustomRecorder {
  static const _channel = MethodChannel('custom_recorder');

  Future<void> start(String path) async {
    final deviceId = await AudioDevicesManager.getSelectedInputDeviceId();

    await _channel.invokeMethod('startRecording', {
      'path': path,
      'deviceId': deviceId,
    });
  }

  Future<void> stop() async {
    await _channel.invokeMethod('stopRecording');
  }
}
```

**Kotlin:**
```kotlin
class CustomRecorderPlugin(private val context: Context) : MethodCallHandler {
    private var audioRecord: AudioRecord? = null
    private var isRecording = false

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "startRecording" -> {
                val path = call.argument<String>("path")
                val deviceId = call.argument<Int?>("deviceId")

                startRecording(path, deviceId)
                result.success(null)
            }
            "stopRecording" -> {
                stopRecording()
                result.success(null)
            }
        }
    }

    private fun startRecording(path: String?, deviceId: Int?) {
        val minBufferSize = AudioRecord.getMinBufferSize(
            44100,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )

        audioRecord = AudioRecord(
            MediaRecorder.AudioSource.MIC,
            44100,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            minBufferSize
        )

        // Apply preferred device
        if (deviceId != null) {
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val device = audioManager.getDevices(AudioManager.GET_DEVICES_INPUTS)
                .firstOrNull { it.id == deviceId }

            device?.let {
                val success = audioRecord?.setPreferredDevice(it)
                Log.d("CustomRecorder", "setPreferredDevice: $success for ${it.productName}")
            }
        }

        audioRecord?.startRecording()
        isRecording = true

        // Start recording thread to write to file...
    }

    private fun stopRecording() {
        isRecording = false
        audioRecord?.stop()
        audioRecord?.release()
        audioRecord = null
    }
}
```

---

## 🎬 Complete Usage Example

```dart
import 'package:flutter/material.dart';
import 'package:audio_devices_manager/audio_devices_manager.dart';

class RecordingScreen extends StatefulWidget {
  @override
  _RecordingScreenState createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> {
  String? selectedDeviceUid;
  bool isRecording = false;

  @override
  void initState() {
    super.initState();
    _initAudio();
  }

  Future<void> _initAudio() async {
    // Initialize audio devices manager
    await AudioDevicesManager.initialize();

    // Listen for device changes
    AudioDevicesManager.deviceEvents().listen((event) {
      // Update UI when devices change
      setState(() {});
    });
  }

  Future<void> startRecording() async {
    if (selectedDeviceUid == null) {
      print('Please select an input device first');
      return;
    }

    // 1. Select the device (important!)
    await AudioDevicesManager.selectInput(selectedDeviceUid!);

    // 2. Get device ID for Android
    final deviceId = await AudioDevicesManager.getSelectedInputDeviceId();
    print('Recording with device ID: $deviceId');

    // 3. Start your recording with the device ID
    // await myRecorder.start(deviceId);

    setState(() {
      isRecording = true;
    });
  }

  Future<void> stopRecording() async {
    // await myRecorder.stop();

    setState(() {
      isRecording = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Audio Recording')),
      body: Column(
        children: [
          // Device selection UI
          FutureBuilder(
            future: AudioDevicesManager.getAvailableInputs(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return CircularProgressIndicator();

              final inputs = snapshot.data as List<Map<String, dynamic>>;

              return ListView.builder(
                shrinkWrap: true,
                itemCount: inputs.length,
                itemBuilder: (context, index) {
                  final input = inputs[index];
                  final uid = input['uid'];

                  return RadioListTile<String>(
                    title: Text(input['portName'] ?? 'Unknown'),
                    value: uid,
                    groupValue: selectedDeviceUid,
                    onChanged: (value) {
                      setState(() {
                        selectedDeviceUid = value;
                      });
                    },
                  );
                },
              );
            },
          ),

          SizedBox(height: 20),

          // Recording controls
          ElevatedButton(
            onPressed: isRecording ? stopRecording : startRecording,
            child: Text(isRecording ? 'Stop Recording' : 'Start Recording'),
          ),
        ],
      ),
    );
  }
}
```

---

## ⚠️ Important Notes

1. **Always call `selectInput()` before recording** to ensure the device is selected
2. **On Android, you must pass the device ID to your AudioRecord**
3. **On iOS, no additional steps needed** - device selection works globally
4. **Device ID can be null** if no device is selected or on iOS
5. **Test with real Bluetooth devices** - emulators don't support Bluetooth audio

---

## 🐛 Troubleshooting

### Recording uses wrong device on Android
- Make sure you're calling `audioRecord.setPreferredDevice()` BEFORE `startRecording()`
- Verify the device ID is not null
- Check that the device is still connected

### No audio from Bluetooth headset
- Ensure `RECORD_AUDIO` permission is granted
- Ensure `BLUETOOTH_CONNECT` permission is granted (Android 12+)
- Check that the Bluetooth device supports voice/SCO profile
- Try selecting the device again

### Works on iOS but not Android
- This is expected - iOS applies globally, Android needs manual integration
- Follow the integration steps in this guide
- Add `setPreferredDevice()` call to your recording code

---

## 📚 References

- [AudioRecord.setPreferredDevice() Documentation](https://developer.android.com/reference/android/media/AudioRecord#setPreferredDevice(android.media.AudioDeviceInfo))
- [AudioDeviceInfo Documentation](https://developer.android.com/reference/android/media/AudioDeviceInfo)
- [iOS AVAudioSession Documentation](https://developer.apple.com/documentation/avfaudio/avaudiosession)

---

## 💡 Need Help?

If you're having trouble integrating with a specific recording library, please open an issue on GitHub with:
1. The recording library you're using
2. Your code snippet
3. Error messages or unexpected behavior

We can help you implement the integration or consider adding built-in support for popular recording libraries.