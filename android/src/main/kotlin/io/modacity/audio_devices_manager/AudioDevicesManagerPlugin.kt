package io.modacity.audio_devices_manager

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.content.Context
import android.content.SharedPreferences
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/** AudioDevicesManagerPlugin */
class AudioDevicesManagerPlugin : FlutterPlugin, MethodCallHandler, EventChannel.StreamHandler {
    /// MethodChannel for one-time requests
    private lateinit var methodChannel: MethodChannel

    /// EventChannel for event streams
    private lateinit var eventChannel: EventChannel

    /// Android AudioManager
    private var audioManager: AudioManager? = null

    /// Application context
    private var context: Context? = null

    /// SharedPreferences for saving user selection
    private var sharedPreferences: SharedPreferences? = null

    /// EventSink for sending events to Dart
    private var eventSink: EventChannel.EventSink? = null

    /// Initialization flag
    private var isInitialized = false

    /// List of available inputs
    private var availableInputs: List<AudioDeviceInfo> = emptyList()

    /// Currently selected input
    private var selectedInput: AudioDeviceInfo? = null

    /// Currently selected audioSource (for dataSources)
    private var selectedAudioSource: Int = MediaRecorder.AudioSource.MIC

    /// Handler for UI thread operations
    private val mainHandler = Handler(Looper.getMainLooper())

    /// Callback for tracking audio device changes
    private val audioDeviceCallback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>) {
            mainHandler.post {
                fetchAudioDevices()
            }
        }

        override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) {
            mainHandler.post {
                fetchAudioDevices()
            }
        }
    }

    // MARK: - FlutterPlugin lifecycle

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        audioManager = context?.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        sharedPreferences = context?.getSharedPreferences("audio_devices_manager", Context.MODE_PRIVATE)

        // Setup MethodChannel
        methodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, "audio_devices_manager")
        methodChannel.setMethodCallHandler(this)

        // Setup EventChannel
        eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "audio_devices_manager_events")
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        dispose()
    }

    // MARK: - MethodChannel handler

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "initialize" -> {
                initialize()
                result.success(null)
            }

            "getAvailableInputs" -> {
                val inputs = getAvailableInputsList()
                result.success(inputs)
            }

            "selectInput" -> {
                val uid = call.argument<String>("uid")
                if (uid == null) {
                    result.error("BAD_ARGS", "No UID provided", null)
                    return
                }
                selectInput(uid)
                result.success(null)
            }

            "getSelectedInput" -> {
                val selected = selectedInput?.let { deviceInfoToMap(it) }
                result.success(selected)
            }

            "getAvailableDataSources" -> {
                val sources = getAvailableDataSourcesList()
                result.success(sources)
            }

            "selectDataSource" -> {
                val dataSourceID = call.argument<Int>("dataSourceID")
                if (dataSourceID == null) {
                    result.error("BAD_ARGS", "No dataSourceID provided", null)
                    return
                }
                selectDataSource(dataSourceID)
                result.success(null)
            }

            "getSelectedInputDeviceId" -> {
                val deviceId = selectedInput?.id
                result.success(deviceId)
            }

            "dispose" -> {
                dispose()
                result.success(null)
            }

            else -> {
                result.notImplemented()
            }
        }
    }

    // MARK: - EventChannel.StreamHandler

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        // Send current state on first subscription
        sendDeviceUpdateEvent()
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    // MARK: - Initialization

    private fun initialize() {
        if (isInitialized) {
            return
        }
        isInitialized = true

        // Register callback for tracking changes
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            audioManager?.registerAudioDeviceCallback(audioDeviceCallback, mainHandler)
        }

        // Load saved audioSource
        selectedAudioSource = sharedPreferences?.getInt("selectedAudioSource", MediaRecorder.AudioSource.MIC)
            ?: MediaRecorder.AudioSource.MIC

        // Get current device state
        fetchAudioDevices()
    }

    // MARK: - Fetching device list

    private fun fetchAudioDevices() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            // Get all input devices
            availableInputs = audioManager?.getDevices(AudioManager.GET_DEVICES_INPUTS)
                ?.filter { isValidInputDevice(it) }
                ?: emptyList()

            // Load last selected input
            loadSelectedInput()

            // Send event to Dart
            sendDeviceUpdateEvent()
        }
    }

    private fun isValidInputDevice(device: AudioDeviceInfo): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            return when (device.type) {
                AudioDeviceInfo.TYPE_BUILTIN_MIC,
                AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
                AudioDeviceInfo.TYPE_WIRED_HEADSET,
                AudioDeviceInfo.TYPE_USB_DEVICE,
                AudioDeviceInfo.TYPE_USB_HEADSET -> true
                else -> false
            }
        }
        return false
    }

    private fun getAvailableInputsList(): List<Map<String, String>> {
        return availableInputs.map { device ->
            mapOf(
                "uid" to device.id.toString(),
                "portName" to getDeviceName(device)
            )
        }
    }

    private fun getDeviceName(device: AudioDeviceInfo): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            // For built-in and wired devices use human-readable names by type
            // For external (USB/Bluetooth) get actual device name
            return when (device.type) {
                AudioDeviceInfo.TYPE_BUILTIN_MIC -> "Built-in Microphone"
                AudioDeviceInfo.TYPE_WIRED_HEADSET -> "Wired Headset"
                AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> {
                    // For Bluetooth get device name via BluetoothAdapter
                    getBluetoothDeviceName(device) ?: "Bluetooth Headset"
                }
                AudioDeviceInfo.TYPE_USB_DEVICE,
                AudioDeviceInfo.TYPE_USB_HEADSET -> {
                    // For USB devices show productName if available
                    val productName = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        device.productName.toString()
                    } else null

                    if (!productName.isNullOrEmpty() && productName != "null") {
                        productName
                    } else {
                        if (device.type == AudioDeviceInfo.TYPE_USB_HEADSET) "USB Headset" else "USB Device"
                    }
                }
                else -> "Unknown"
            }
        }
        return "Unknown"
    }

    @Suppress("MissingPermission")
    private fun getBluetoothDeviceName(device: AudioDeviceInfo): String? {
        val TAG = "AudioDevicesManager"
        try {
            val bluetoothAdapter = BluetoothAdapter.getDefaultAdapter()
            if (bluetoothAdapter == null) {
                Log.d(TAG, "BluetoothAdapter is null")
                return null
            }

            // Method 1: Try via address (Android P+)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val address = device.address
                Log.d(TAG, "Device address: $address")
                if (!address.isNullOrEmpty()) {
                    try {
                        val bluetoothDevice = bluetoothAdapter.getRemoteDevice(address)
                        val name = bluetoothDevice.name
                        Log.d(TAG, "Bluetooth device name from address: $name")
                        if (!name.isNullOrEmpty()) {
                            return name
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error getting device by address: ${e.message}")
                    }
                }
            }

            // Method 2: Search for actively connected device among bonded devices
            try {
                val bondedDevices = bluetoothAdapter.bondedDevices
                Log.d(TAG, "Bonded devices count: ${bondedDevices?.size ?: 0}")

                if (bondedDevices != null && bondedDevices.isNotEmpty()) {
                    // First search for connected device
                    var connectedAudioDevice: String? = null

                    for (btDevice in bondedDevices) {
                        val deviceClass = btDevice.bluetoothClass
                        val majorClass = deviceClass?.majorDeviceClass
                        val name = btDevice.name

                        // Log all devices for diagnostics
                        Log.d(TAG, "Bonded device: $name, address: ${btDevice.address}, majorClass: $majorClass, bondState: ${btDevice.bondState}")

                        // Check if device is connected
                        try {
                            val isConnectedMethod = btDevice.javaClass.getMethod("isConnected")
                            val isConnected = isConnectedMethod.invoke(btDevice) as Boolean
                            Log.d(TAG, "  -> isConnected: $isConnected")

                            if (isConnected && deviceClass != null) {
                                // Audio/Video class (0x0400 = 1024)
                                if (majorClass == 1024) {
                                    Log.d(TAG, "Found CONNECTED audio device: $name")
                                    if (!name.isNullOrEmpty()) {
                                        connectedAudioDevice = name
                                        break
                                    }
                                }
                            }
                        } catch (e: Exception) {
                            Log.d(TAG, "  -> Cannot check connection status: ${e.message}")
                        }
                    }

                    // If found connected device, return it
                    if (connectedAudioDevice != null) {
                        return connectedAudioDevice
                    }

                    // If no connected device found, use first audio device as fallback
                    for (btDevice in bondedDevices) {
                        val deviceClass = btDevice.bluetoothClass
                        if (deviceClass != null) {
                            val majorClass = deviceClass.majorDeviceClass
                            if (majorClass == 1024) {
                                val name = btDevice.name
                                if (!name.isNullOrEmpty()) {
                                    Log.d(TAG, "Using first audio device as fallback: $name")
                                    return name
                                }
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error getting bonded devices: ${e.message}")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in getBluetoothDeviceName: ${e.message}")
        }
        return null
    }

    private fun deviceInfoToMap(device: AudioDeviceInfo): Map<String, String> {
        return mapOf(
            "uid" to device.id.toString(),
            "portName" to getDeviceName(device)
        )
    }

    // MARK: - Input device selection

    private fun selectInput(uid: String) {
        val device = availableInputs.firstOrNull { it.id.toString() == uid }
        if (device == null) {
            return
        }

        selectedInput = device

        // Save selection
        sharedPreferences?.edit()?.putString("selectedAudioInput", uid)?.apply()

        // Send event
        sendDeviceUpdateEvent()
    }

    private fun loadSelectedInput() {
        val savedUID = sharedPreferences?.getString("selectedAudioInput", null)

        if (savedUID != null) {
            selectedInput = availableInputs.firstOrNull { it.id.toString() == savedUID }
        }

        // If nothing saved or device not found, take first one
        if (selectedInput == null && availableInputs.isNotEmpty()) {
            selectedInput = availableInputs.first()
        }
    }

    // MARK: - Data Sources (emulation via audioSource)

    private fun getAvailableDataSourcesList(): List<Map<String, Any>> {
        // Android has no direct equivalent of iOS dataSources
        // Return audioSource types as alternative
        return listOf(
            mapOf(
                "dataSourceID" to MediaRecorder.AudioSource.MIC,
                "dataSourceName" to "Standard Microphone"
            ),
            mapOf(
                "dataSourceID" to MediaRecorder.AudioSource.VOICE_COMMUNICATION,
                "dataSourceName" to "Voice Communication"
            ),
            mapOf(
                "dataSourceID" to MediaRecorder.AudioSource.VOICE_RECOGNITION,
                "dataSourceName" to "Voice Recognition"
            ),
            mapOf(
                "dataSourceID" to MediaRecorder.AudioSource.CAMCORDER,
                "dataSourceName" to "Camcorder"
            )
        )
    }

    private fun selectDataSource(dataSourceID: Int) {
        selectedAudioSource = dataSourceID

        // Save selection
        sharedPreferences?.edit()?.putInt("selectedAudioSource", dataSourceID)?.apply()

        // Send event
        sendDeviceUpdateEvent()
    }

    // MARK: - Sending events to Dart

    private fun sendDeviceUpdateEvent() {
        val sink = eventSink ?: return

        val data = mapOf(
            "availableInputs" to getAvailableInputsList(),
            "selectedInput" to (selectedInput?.let { deviceInfoToMap(it) }),
            "availableDataSources" to getAvailableDataSourcesList(),
            "selectedDataSource" to getSelectedDataSource()
        )

        mainHandler.post {
            sink.success(data)
        }
    }

    private fun getSelectedDataSource(): Map<String, Any>? {
        val sources = getAvailableDataSourcesList()
        return sources.firstOrNull {
            (it["dataSourceID"] as? Int) == selectedAudioSource
        }
    }

    // MARK: - Resource cleanup

    private fun dispose() {
        // Protect against repeated dispose calls without initialization
        if (!isInitialized) {
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            audioManager?.unregisterAudioDeviceCallback(audioDeviceCallback)
        }

        eventSink = null
        isInitialized = false
    }
}