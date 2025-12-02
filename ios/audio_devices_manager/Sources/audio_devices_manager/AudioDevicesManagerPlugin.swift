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

    // MARK: - EventChannel (for change streams)
    private var eventSink: FlutterEventSink?
    
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

        case "showRoutePicker":
            // System Route Picker must be shown from UI layer
            // Here we only send a notification
            result(FlutterError(code: "NOT_IMPLEMENTED",
                               message: "Route Picker must be called from UI layer",
                               details: nil))

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
        isInitialized = true

        // Configure audio session
        do {
            try audioSession.setCategory(.playAndRecord,
                                         mode: .default,
                                         options: [.allowBluetooth,
                                                   .allowBluetoothA2DP,
                                                   .defaultToSpeaker])
            try audioSession.setActive(true)
        } catch {
            print("Error setting audio session: \(error.localizedDescription)")
        }

        // Get current device state immediately
        fetchAudioDevices()

        // Subscribe to route changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    /// Audio route change handler (headphones connect/disconnect, etc.)
    @objc private func handleRouteChange(_ notification: Notification) {
        DispatchQueue.main.async {
            self.fetchAudioDevices()
        }
    }

    /// Update list of available inputs and selected device
    private func fetchAudioDevices() {
        availableInputs = audioSession.availableInputs ?? []

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
            UserDefaults.standard.set(uid, forKey: "selectedAudioInput")
        } catch {
            print("Error selecting audio input: \(error.localizedDescription)")
        }

        // Update dataSources, notify about changes
        updateDataSources()
        sendDeviceUpdateEvent()
    }

    /// Load previously saved input
    private func loadSelectedInput() {
        guard
            let savedUID = UserDefaults.standard.string(forKey: "selectedAudioInput"),
            let input = availableInputs.first(where: { $0.uid == savedUID })
        else {
            // If nothing saved, take first
            selectedInput = availableInputs.first
            return
        }

        do {
            try audioSession.setPreferredInput(input)
            selectedInput = input
        } catch {
            print("Error setting saved input: \(error.localizedDescription)")
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
            UserDefaults.standard.set(source.dataSourceID, forKey: "selectedDataSource")
        } catch {
            print("Error selecting microphone data source: \(error.localizedDescription)")
        }
        sendDeviceUpdateEvent()
    }
    
    private func loadSelectedDataSource() {
        guard
            let savedDataSourceID = UserDefaults.standard.value(forKey: "selectedDataSource") as? NSNumber,
            let source = availableDataSources.first(where: { $0.dataSourceID == savedDataSourceID })
        else {
            selectedDataSource = availableDataSources.first
            return
        }
        do {
            try selectedInput?.setPreferredDataSource(source)
            selectedDataSource = source
        } catch {
            print("Error loading saved data source: \(error.localizedDescription)")
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
        // But we can save user preference for information
        selectedOutput = output
        UserDefaults.standard.set(uid, forKey: "selectedAudioOutput")

        print("Output selection saved (iOS limitation: cannot programmatically change): \(output.portName)")
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
            UserDefaults.standard.set(enable, forKey: "defaultToSpeaker")

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
        NotificationCenter.default.removeObserver(self)
        try? audioSession.setActive(false)
        eventSink = nil
        isInitialized = false
    }
}
