import Flutter
import UIKit
import AVFoundation

public class AudioDevicesManagerPlugin: NSObject, FlutterPlugin {
    /// Flag to prevent repeated session initialization
    private var isInitialized = false

    // MARK: - Audio properties
    private var audioSession = AVAudioSession.sharedInstance()
    private var availableInputs: [AVAudioSessionPortDescription] = []
    private var selectedInput: AVAudioSessionPortDescription?
    private var availableDataSources: [AVAudioSessionDataSourceDescription] = []
    private var selectedDataSource: AVAudioSessionDataSourceDescription?

    // Output devices
    private var availableOutputs: [AVAudioSessionPortDescription] = []
    private var selectedOutput: AVAudioSessionPortDescription?
    private var defaultToSpeaker: Bool = true

    // MARK: - Persistence
    private let userDefaults = UserDefaults.standard
    private let selectedInputKey = "selectedAudioInput"
    private let selectedDataSourceKey = "selectedDataSource"
    private let selectedOutputKey = "selectedAudioOutput"

    // MARK: - EventChannel (for change streams)
    private var eventSink: FlutterEventSink?

    // MARK: - Debounce for route changes
    private var debounceWorkItem: DispatchWorkItem?
    private let debounceDelay: TimeInterval = 0.3
    
    // MARK: - Plugin registration (called by Flutter framework)
    public static func register(with registrar: FlutterPluginRegistrar) {
        // MethodChannel: one-time requests (getAvailableInputs, selectInput, etc.)
        let methodChannel = FlutterMethodChannel(
            name: "audio_devices_manager",
            binaryMessenger: registrar.messenger()
        )
        // EventChannel: events (route changes, device selection, etc.)
        let eventChannel = FlutterEventChannel(
            name: "audio_devices_manager_events",
            binaryMessenger: registrar.messenger()
        )

        let instance = AudioDevicesManagerPlugin()
        // Bind method handler
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        // Bind stream handler
        eventChannel.setStreamHandler(instance)
    }

    // MARK: - MethodChannel handling
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize":
            initializeAudioSession()
            result(nil)
            
        case "getAvailableInputs":
            let inputsInfo = getAvailableInputsList()
            result(inputsInfo)
            
        case "selectInput":
            guard let args = call.arguments as? [String: Any],
                  let uid = args["uid"] as? String
            else {
                result(FlutterError(code: "BAD_ARGS", message: "No UID provided", details: nil))
                return
            }
            selectInput(uid: uid)
            result(nil)
            
        case "getSelectedInput":
            if let input = selectedInput {
                result([
                    "uid": input.uid,
                    "portName": input.portName
                ])
            } else {
                result(nil)
            }
            
        case "getAvailableDataSources":
            let dsList = getAvailableDataSourcesList()
            result(dsList)
            
        case "selectDataSource":
            guard let args = call.arguments as? [String: Any],
                  let dataSourceID = args["dataSourceID"] as? NSNumber
            else {
                result(FlutterError(code: "BAD_ARGS", message: "No dataSourceID provided", details: nil))
                return
            }
            selectDataSource(dataSourceID: dataSourceID)
            result(nil)

        case "getSelectedInputDeviceId":
            // On iOS device selection is applied automatically via setPreferredInput
            // So device ID is not needed - return nil
            result(nil)

        case "getAvailableOutputs":
            let outputsInfo = getAvailableOutputsList()
            result(outputsInfo)

        case "selectOutput":
            guard let args = call.arguments as? [String: Any],
                  let uid = args["uid"] as? String
            else {
                result(FlutterError(code: "BAD_ARGS", message: "No UID provided", details: nil))
                return
            }
            selectOutput(uid: uid)
            result(nil)

        case "getSelectedOutput":
            if let output = selectedOutput {
                result([
                    "uid": output.uid,
                    "portName": output.portName
                ])
            } else {
                result(nil)
            }

        case "getSelectedOutputDeviceId":
            // On iOS device ID is not needed for outputs
            result(nil)

        case "setDefaultToSpeaker":
            guard let args = call.arguments as? [String: Any],
                  let enable = args["enable"] as? Bool
            else {
                result(FlutterError(code: "BAD_ARGS", message: "No enable value provided", details: nil))
                return
            }
            setDefaultToSpeakerOption(enable: enable)
            result(nil)

        case "dispose":
            dispose()
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

// MARK: - EventChannel implementation (FlutterStreamHandler)
extension AudioDevicesManagerPlugin: FlutterStreamHandler {
    // When Dart subscribes to events
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        // Send current state immediately on first subscription
        sendDeviceUpdateEvent()
        return nil
    }

    // When Dart unsubscribes from events
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
}


// MARK: - Helper methods
extension AudioDevicesManagerPlugin {
    /// Main audio session initialization method
    private func initializeAudioSession() {
        // Protection against repeated initialization
        guard !isInitialized else {
            // Already initialized, skip
            return
        }

        // Configure audio session
        do {
            try audioSession.setCategory(.playAndRecord,
                                         mode: .default,
                                         options: [.allowBluetooth,
                                                   .allowBluetoothA2DP,
                                                   .defaultToSpeaker])
            try audioSession.setActive(true)

            // Only set isInitialized after successful initialization
            isInitialized = true

            // Get current device state immediately
            fetchAudioDevices()

            // Subscribe to route changes
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleRouteChange(_:)),
                name: AVAudioSession.routeChangeNotification,
                object: nil
            )
        } catch {
            print("Error setting audio session: \(error.localizedDescription)")
            // isInitialized remains false, allowing retry
        }
    }

    /// Audio route change handler (headphones connect/disconnect, etc.)
    @objc private func handleRouteChange(_ notification: Notification) {
        // Cancel previous debounce work item
        debounceWorkItem?.cancel()

        // Create new work item with debounce
        // IMPORTANT: AVAudioSession must be accessed from main thread for correct data
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            // Fetch audio devices on main thread (AVAudioSession requires main thread)
            self.fetchAudioDevices()
        }

        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceDelay, execute: workItem)
    }

    /// Update list of available inputs and selected device
    private func fetchAudioDevices() {
        // Get all potentially available inputs
        let allInputs = audioSession.availableInputs ?? []

        // Get currently connected ports from route
        let currentInputUIDs = Set(audioSession.currentRoute.inputs.map { $0.uid })
        let currentOutputUIDs = Set(audioSession.currentRoute.outputs.map { $0.uid })

        // Filter: show only Built-In Microphone + currently connected devices
        // Built-In Microphone is always available even if not in currentRoute
        availableInputs = allInputs.filter { input in
            // Always show built-in microphone
            if input.portType == .builtInMic {
                return true
            }

            // For Bluetooth devices: check outputs (iOS doesn't auto-switch inputs to BT)
            // If AirPods are in outputs, their microphone is also available as input
            if input.portType == .bluetoothHFP || input.portType == .bluetoothA2DP {
                return currentOutputUIDs.contains(input.uid)
            }

            // For other devices (wired, USB): check inputs
            return currentInputUIDs.contains(input.uid)
        }

        // Load last selected input (from UserDefaults), if any
        loadSelectedInput()

        // Update dataSources
        updateDataSources()

        // Update outputs
        fetchOutputDevices()

        // Send event to Dart
        sendDeviceUpdateEvent()
    }

    /// Get list of available outputs from current route
    private func fetchOutputDevices() {
        availableOutputs = audioSession.currentRoute.outputs

        // Select current active output
        selectedOutput = availableOutputs.first
    }

    // MARK: - Working with input list

    /// Returns array of dictionaries for Dart
    private func getAvailableInputsList() -> [[String: String]] {
        return availableInputs.map {
            [
                "uid": $0.uid,
                "portName": $0.portName
            ]
        }
    }

    /// Select input by uid
    private func selectInput(uid: String) {
        guard let input = availableInputs.first(where: { $0.uid == uid }) else { return }

        do {
            try audioSession.setPreferredInput(input)
            selectedInput = input

            // Save selection to UserDefaults
            userDefaults.set(uid, forKey: selectedInputKey)
        } catch {
            print("Error selecting audio input: \(error.localizedDescription)")
        }

        // Update dataSources, notify about changes
        updateDataSources()
        sendDeviceUpdateEvent()
    }

    /// Synchronize selectedInput with actual active microphone from currentRoute
    /// Priority:
    /// 1. Previously saved input from UserDefaults (if still available)
    /// 2. Current active input from audioSession.currentRoute.inputs.first
    /// 3. Fallback to first available input
    private func loadSelectedInput() {
        // Try to load saved input from UserDefaults
        if let savedUID = userDefaults.string(forKey: selectedInputKey),
           let savedInput = availableInputs.first(where: { $0.uid == savedUID }) {
            // Saved input is still available - use it
            selectedInput = savedInput

            // Try to apply it (best effort)
            try? audioSession.setPreferredInput(savedInput)
            return
        }

        // Get current active input from system
        let currentActiveInput = audioSession.currentRoute.inputs.first

        // Check if current active input is in our available list
        if let activeInput = currentActiveInput,
           let matchingInput = availableInputs.first(where: { $0.uid == activeInput.uid }) {
            // Current active input is available - use it as selected
            selectedInput = matchingInput
        } else {
            // Fallback to first available input
            selectedInput = availableInputs.first
        }
    }

    // MARK: - Data Sources

    /// Update dataSources list
    private func updateDataSources() {
        availableDataSources = selectedInput?.dataSources ?? []
        loadSelectedDataSource()
    }
    
    private func getAvailableDataSourcesList() -> [[String: Any]] {
        return availableDataSources.map { ds in
            [
                "dataSourceID": ds.dataSourceID,
                "dataSourceName": ds.dataSourceName
            ]
        }
    }
    
    private func selectDataSource(dataSourceID: NSNumber) {
        guard
            let input = selectedInput,
            let source = availableDataSources.first(where: { $0.dataSourceID == dataSourceID })
        else {
            return
        }
        do {
            try input.setPreferredDataSource(source)
            selectedDataSource = source

            // Save selection to UserDefaults
            userDefaults.set(dataSourceID, forKey: selectedDataSourceKey)
        } catch {
            print("Error selecting microphone data source: \(error.localizedDescription)")
        }
        sendDeviceUpdateEvent()
    }
    
    private func loadSelectedDataSource() {
        // Try to load saved data source from UserDefaults
        if let savedDataSourceID = userDefaults.object(forKey: selectedDataSourceKey) as? NSNumber,
           let savedDataSource = availableDataSources.first(where: { $0.dataSourceID == savedDataSourceID }) {
            // Saved data source is still available - use it
            selectedDataSource = savedDataSource

            // Try to apply it (best effort)
            try? selectedInput?.setPreferredDataSource(savedDataSource)
        } else {
            // Fallback to first available data source
            selectedDataSource = availableDataSources.first
        }
    }

    // MARK: - Output Devices

    /// Returns array of dictionaries for Dart (outputs)
    private func getAvailableOutputsList() -> [[String: String]] {
        return availableOutputs.map {
            [
                "uid": $0.uid,
                "portName": $0.portName
            ]
        }
    }

    /// Select output by uid
    /// IMPORTANT: On iOS cannot programmatically select specific output device
    /// This is informational only, actual selection is done by the system
    private func selectOutput(uid: String) {
        guard let output = availableOutputs.first(where: { $0.uid == uid }) else {
            print("Output device not found: \(uid)")
            return
        }

        // On iOS we cannot programmatically change the output
        // Just track the selection for information
        selectedOutput = output

        // Save selection to UserDefaults (for tracking only)
        userDefaults.set(uid, forKey: selectedOutputKey)

        print("Output selection tracked (iOS limitation: cannot programmatically change): \(output.portName)")
        sendDeviceUpdateEvent()
    }

    /// Set defaultToSpeaker option
    private func setDefaultToSpeakerOption(enable: Bool) {
        defaultToSpeaker = enable

        var options: AVAudioSession.CategoryOptions = [.allowBluetooth, .allowBluetoothA2DP]
        if enable {
            options.insert(.defaultToSpeaker)
        }

        do {
            try audioSession.setCategory(.playAndRecord,
                                        mode: .default,
                                        options: options)

            // Update device list after changing options
            fetchOutputDevices()

            print("DefaultToSpeaker set to: \(enable)")
        } catch {
            print("Error setting defaultToSpeaker option: \(error.localizedDescription)")
        }
    }

    // MARK: - Sending events (EventChannel)

    /// Send current state (device list + selected) to Dart
    private func sendDeviceUpdateEvent() {
        guard let eventSink = eventSink else { return }

        let data: [String: Any] = [
            "availableInputs": getAvailableInputsList(),
            "selectedInput": selectedInput.map {
                [
                    "uid": $0.uid,
                    "portName": $0.portName
                ]
            } ?? NSNull(),
            "availableDataSources": getAvailableDataSourcesList(),
            "selectedDataSource": selectedDataSource.map {
                [
                    "dataSourceID": $0.dataSourceID,
                    "dataSourceName": $0.dataSourceName
                ]
            } ?? NSNull(),
            "availableOutputs": getAvailableOutputsList(),
            "selectedOutput": selectedOutput.map {
                [
                    "uid": $0.uid,
                    "portName": $0.portName
                ]
            } ?? NSNull()
        ]

        eventSink(data)
    }

    // MARK: - (Optional) Method for unsubscribing and deactivation

    /// You can call this from Dart if needed to completely "turn off" the plugin
    private func dispose() {
        // Cancel any pending debounce work items
        debounceWorkItem?.cancel()
        debounceWorkItem = nil

        NotificationCenter.default.removeObserver(self)
        try? audioSession.setActive(false)
        eventSink = nil
        isInitialized = false

        // Note: We intentionally do NOT clear UserDefaults here
        // User preferences should persist across dispose/initialize cycles
    }
}
