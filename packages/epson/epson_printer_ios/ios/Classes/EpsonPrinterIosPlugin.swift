import Foundation
import Flutter
import ExternalAccessory
import UIKit

public class EpsonPrinterIosPlugin: NSObject, FlutterPlugin {
    private let BLE_CONNECTION_TIMEOUT_MILLIS: Int = 30000 // Set BLE connection timeout to 30 seconds
    
    private var discoveryResult: FlutterResult?
    private var epsonWrapper: EpsonSDKWrapper
    private var target: String?
    private var printerSeries: Int32 = 29 // EPOS2_TM_M30III (based on the discovery result)
    private var printerLang: Int32 = 0 // EPOS2_MODEL_ANK
    private var currentBluetoothDeviceNames: Set<String> = [] // Track CURRENT Bluetooth-connected devices
    private var knownBluetoothAccessoryNames: Set<String> = [] // Track EAAccessory names that are likely Bluetooth
    private var usbWasConnectedThisSession: Bool = false // Track if USB was ever connected (BT hardware turns off on iOS)
    private var connectedAccessories: Set<String> = [] // Track currently connected EAAccessory devices
    // Discovery coordination
    private enum DiscoveryState: String { case idle, discoveringLan, discoveringBluetooth, discoveringUsb, cleaningUp, suspendedAfterUsbDisconnect }
    private var discoveryState: DiscoveryState = .idle
    private var discoverySessionId: UInt64 = 0
    private let sdkQueue = DispatchQueue(label: "epson.sdk.serial", qos: .userInitiated) // elevated QoS to reduce inversion risk
    private var pendingDiscoveryWork: (() -> Void)?
    private var watchdogTimers: [UInt64: DispatchWorkItem] = [:]
    private let watchdogTimeoutSeconds: TimeInterval = 12.0 // safety timeout to auto-reset state

    private func nextSessionId() -> UInt64 { discoverySessionId &+= 1; return discoverySessionId }
    private func setState(_ new: DiscoveryState, sessionId: UInt64) {
        print("DEBUG: State transition: \(discoveryState.rawValue) -> \(new.rawValue) (session=\(sessionId))")
        discoveryState = new
    }
    private func startWatchdog(sessionId: UInt64, label: String) {
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if self.discoverySessionId == sessionId && self.discoveryState != .idle {
                print("DEBUG: Watchdog fired for session \(sessionId) [\(label)] - forcing state reset to idle")
                self.discoveryState = .idle
            }
        }
        watchdogTimers[sessionId]?.cancel()
        watchdogTimers[sessionId] = item
        DispatchQueue.main.asyncAfter(deadline: .now() + watchdogTimeoutSeconds, execute: item)
    }
    private func clearWatchdog(sessionId: UInt64) { watchdogTimers[sessionId]?.cancel(); watchdogTimers.removeValue(forKey: sessionId) }
    
    override init() {
        epsonWrapper = EpsonSDKWrapper()
        super.init()
        
        // CRITICAL: Populate connectedAccessories with devices that are ALREADY connected at app launch
        // This prevents treating Bluetooth devices as "NEW" (USB) connections
        for accessory in EAAccessoryManager.shared().connectedAccessories {
            if accessory.protocolStrings.contains("com.epson.escpos") {
                connectedAccessories.insert(accessory.name)
                print("DEBUG: Found already-connected accessory at init: \(accessory.name)")
                if isLikelyBluetoothAccessoryName(accessory.name) {
                    knownBluetoothAccessoryNames.insert(accessory.name)
                    print("DEBUG: Classified accessory as Bluetooth by name pattern at init: \(accessory.name)")
                }
            }
        }
        
        // Register for EAAccessory connect/disconnect notifications for logging
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accessoryDidConnect(_:)),
            name: .EAAccessoryDidConnect,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accessoryDidDisconnect(_:)),
            name: .EAAccessoryDidDisconnect,
            object: nil
        )
        EAAccessoryManager.shared().registerForLocalNotifications()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        EAAccessoryManager.shared().unregisterForLocalNotifications()
    }
    
    @objc private func accessoryDidConnect(_ notification: Notification) {
        if let accessory = notification.userInfo?[EAAccessoryKey] as? EAAccessory {
            print("DEBUG: EAAccessory connected: \(accessory.name)")
            
            // If this device is NOT already in our connected set, it means a cable was just plugged in
            // (Bluetooth devices are already connected at app launch)
            if !connectedAccessories.contains(accessory.name) {
                if isLikelyBluetoothAccessoryName(accessory.name) {
                    print("DEBUG: NEW accessory connection classified as Bluetooth (by name): \(accessory.name)")
                    knownBluetoothAccessoryNames.insert(accessory.name)
                } else {
                    print("DEBUG: NEW accessory connection detected - USB cable was just plugged in!")
                    print("DEBUG: Bluetooth hardware on printer is now OFF - disabling BT discovery for session")
                    usbWasConnectedThisSession = true
                    
                    // Cancel any pending Bluetooth timeout to prevent SDK corruption
                    // Note: The timeout is managed in Objective-C, so we call the wrapper to cancel it
                    epsonWrapper.cancelBluetoothTimeout()
                }
            }
            
            connectedAccessories.insert(accessory.name)
        }
    }
    
    @objc private func accessoryDidDisconnect(_ notification: Notification) {
        guard let accessory = notification.userInfo?[EAAccessoryKey] as? EAAccessory else { return }
        print("DEBUG: EAAccessory disconnected: \(accessory.name)")

        // When USB cable unplugged after a session with USB, perform cleanup then cooldown
        if accessory.name.contains("TM-") && usbWasConnectedThisSession {
            print("DEBUG: USB cable unplugged - scheduling non-blocking cleanup")
            let session = nextSessionId()
            setState(.cleaningUp, sessionId: session)
            startWatchdog(sessionId: session, label: "usb_cleanup")
            sdkQueue.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self = self else { return }
                print("DEBUG: Performing serial cleanup (session=\(session))")
                self.epsonWrapper.forceDiscoveryCleanup(completion: { [weak self] in
                    guard let self = self else { return }
                    self.clearWatchdog(sessionId: session)
                    // Only transition if still cleaning up for this session
                    if self.discoveryState == .cleaningUp && self.discoverySessionId == session {
                        self.discoveryState = .suspendedAfterUsbDisconnect
                        print("DEBUG: Cleanup complete -> suspendedAfterUsbDisconnect (cooldown) (session=\(session))")
                        let cooldownSession = self.nextSessionId()
                        self.startWatchdog(sessionId: cooldownSession, label: "post_usb_cooldown")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                            guard let self = self else { return }
                            if self.discoveryState == .suspendedAfterUsbDisconnect {
                                self.discoveryState = .idle
                                print("DEBUG: Cooldown ended -> idle (session=\(cooldownSession))")
                                // Do not auto-run any queued discovery; Dart side should trigger explicitly
                                self.pendingDiscoveryWork = nil
                            }
                            self.clearWatchdog(sessionId: cooldownSession)
                        }
                    }
                })
            }
        }

        connectedAccessories.remove(accessory.name)
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "epson_printer", binaryMessenger: registrar.messenger())
        let instance = EpsonPrinterIosPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "discoverPrinters":
            discoverPrinters(call: call, result: result)
        case "discoverBluetoothPrinters":
            // Clear previous Bluetooth tracking before new discovery
            currentBluetoothDeviceNames.removeAll()
            let accessories = EAAccessoryManager.shared().connectedAccessories
            if accessories.isEmpty {
                print("EAAccessory: No connected accessories found.")
            } else {
                for acc in accessories { print("EAAccessory connected: name=\(acc.name), manufacturer=\(acc.manufacturer), model=\(acc.modelNumber), serial=\(acc.serialNumber), protocols=\(acc.protocolStrings)") }
            }
            discoverBluetoothPrinters(call: call, result: result)
        case "discoverUsbPrinters":
            discoverUsbPrinters(result: result)
        case "discoverAllPrinters":
            discoverAllPrinters(result: result)
        case "findPairedBluetoothPrinters":
            findPairedBluetoothPrinters(call: call, result: result)
        case "pairBluetoothDevice":
            pairBluetoothDevice(result: result)
        case "usbDiagnostics":
            usbDiagnostics(result: result)
        case "connect":
            connect(call: call, result: result)
        case "disconnect":
            disconnect(result: result)
        case "printReceipt":
            printReceipt(call: call, result: result)
        case "getStatus":
            getStatus(result: result)
        case "openCashDrawer":
            openCashDrawer(result: result)
        case "isConnected":
            isConnected(result: result)
        case "getDiscoveryState":
            getDiscoveryState(result: result)
        case "abortDiscovery":
            abortDiscovery(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    private func discoverAllPrinters(result: @escaping FlutterResult) {
        let attemptSession = nextSessionId()
        if discoveryState == .cleaningUp || discoveryState == .suspendedAfterUsbDisconnect {
            print("DEBUG: Deferring discoverAll during cleanup/cooldown (session=\(attemptSession))")
            result([])
            return
        }
        // Orchestrate sequentially on sdkQueue
        setState(.discoveringLan, sessionId: attemptSession)
        startWatchdog(sessionId: attemptSession, label: "all")
        var snapshot: [String] = []
        sdkQueue.async { [weak self] in
            guard let self = self else { return }
            // LAN first
            do {
                try self.epsonWrapper.startDiscovery(withFilter: 1) { printers in
                    for p in printers {
                        if let t = p["target"] as? String, let n = p["deviceName"] as? String {
                            snapshot.append("\(t):\(n)")
                        }
                    }
                }
            } catch { }
            // Small pause
            Thread.sleep(forTimeInterval: 0.2)
            // Bluetooth (skip if USB seen in session)
            if !self.usbWasConnectedThisSession {
                do {
                    self.epsonWrapper.startBluetoothDiscovery { printers in
                        for p in printers {
                            if let t = p["target"] as? String, let n = p["deviceName"] as? String {
                                snapshot.append("\(t):\(n)")
                            }
                        }
                    }
                }
            }
            Thread.sleep(forTimeInterval: 0.2)
            // USB via EAAccessory
            let accessories = EAAccessoryManager.shared().connectedAccessories
            let epsonAccessories = accessories.filter { acc in
                (acc.protocolStrings.contains("com.epson.escpos") || acc.protocolStrings.contains("com.epson.posprinter"))
            }
            for acc in epsonAccessories {
                if self.currentBluetoothDeviceNames.contains(acc.name) || self.knownBluetoothAccessoryNames.contains(acc.name) || self.isLikelyBluetoothAccessoryName(acc.name) {
                    continue
                }
                snapshot.append("USB::\(acc.name)")
            }
            // Dedupe and prefer TCP over TCPS
            var unique: [String: String] = [:] // mac->target
            var finalList: [String] = []
            for entry in snapshot {
                let parts = entry.split(separator: ":")
                if parts.count >= 8 { // e.g., TCP:AA:BB:CC:DD:EE:FF:Name
                    let mac = parts[1...6].joined(separator: ":")
                    let target = parts[0...6].joined(separator: ":")
                    let name = parts.dropFirst(7).joined(separator: ":")
                    if let existing = unique[mac] {
                        if target.hasPrefix("TCP") && existing.hasPrefix("TCPS") {
                            if let idx = finalList.firstIndex(where: { $0.hasPrefix(existing) }) { finalList.remove(at: idx) }
                            unique[mac] = target
                            finalList.append("\(target):\(name)")
                        }
                    } else {
                        unique[mac] = target
                        finalList.append("\(target):\(name)")
                    }
                } else {
                    if !finalList.contains(entry) { finalList.append(entry) }
                }
            }
            DispatchQueue.main.async {
                self.clearWatchdog(sessionId: attemptSession)
                if self.discoverySessionId == attemptSession { self.discoveryState = .idle }
                result(finalList)
            }
        }
    }

    // Updated LAN discovery with state machine & watchdog
    private func discoverPrinters(call: FlutterMethodCall, result: @escaping FlutterResult) {
        let attemptSession = nextSessionId()
        if discoveryState == .cleaningUp || discoveryState == .suspendedAfterUsbDisconnect {
            print("DEBUG: Deferring LAN discovery during cleanup/cooldown (session=\(attemptSession))")
            result([])
            return
        }
        guard discoveryState == .idle else {
            print("DEBUG: Ignoring LAN discovery request; current state=\(discoveryState.rawValue)")
            result([])
            return
        }
        setState(.discoveringLan, sessionId: attemptSession)
        startWatchdog(sessionId: attemptSession, label: "lan")
        print("DEBUG: Starting Epson printer discovery (session=\(attemptSession))...")
        let filterOption: Int32 = 1 // EPOS2_PORTTYPE_TCP
        print("DEBUG: Using TCP filter option: \(filterOption)")
        sdkQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                self.epsonWrapper.startDiscovery(withFilter: filterOption) { [weak self] printers in
                    guard let self = self else { return }
                    print("DEBUG: Discovery callback received with \(printers.count) printers (session=\(attemptSession))")
                    var seenMacs: [String: String] = [:]
                    var printerStrings: [String] = []
                    for printer in printers {
                        guard let target = printer["target"] as? String,
                              let deviceName = printer["deviceName"] as? String else {
                            print("DEBUG: Skipping printer with invalid data: \(printer)")
                            continue
                        }
                        let mac = self.extractMacAddress(from: target)
                        if !mac.isEmpty {
                            if let existing = seenMacs[mac] {
                                if target.starts(with: "TCP:") && existing.starts(with: "TCPS:") {
                                    if let idx = printerStrings.firstIndex(where: { $0.starts(with: existing) }) { printerStrings.remove(at: idx) }
                                    seenMacs[mac] = target
                                    printerStrings.append("\(target):\(deviceName)")
                                } else if target.starts(with: "TCPS:") && existing.starts(with: "TCP:") {
                                    print("DEBUG: Skipping TCPS duplicate, already have TCP for MAC \(mac)")
                                    continue
                                }
                            } else {
                                seenMacs[mac] = target
                                printerStrings.append("\(target):\(deviceName)")
                            }
                        } else {
                            printerStrings.append("\(target):\(deviceName)")
                        }
                        print("DEBUG: Found printer: \(target):\(deviceName)")
                    }
                    print("DEBUG: Discovery completed. Found \(printerStrings.count) unique printers: \(printerStrings) (session=\(attemptSession))")
                    DispatchQueue.main.async {
                        self.clearWatchdog(sessionId: attemptSession)
                        if self.discoverySessionId == attemptSession { self.discoveryState = .idle }
                        result(printerStrings)
                    }
                }
            } catch {
                print("DEBUG: Discovery threw error: \(error) (session=\(attemptSession))")
                DispatchQueue.main.async {
                    self.clearWatchdog(sessionId: attemptSession)
                    if self.discoverySessionId == attemptSession { self.discoveryState = .idle }
                    result([])
                }
            }
        }
    }
    
    private func extractMacAddress(from target: String) -> String {
        // Extract MAC from "TCP:A4:D7:3C:AA:CA:01" or "TCPS:A4:D7:3C:AA:CA:01[local_printer]"
        // Remove any bracketed suffix first
        var cleanTarget = target
        if let bracketIndex = target.firstIndex(of: "[") {
            cleanTarget = String(target[..<bracketIndex])
        }
        
        let parts = cleanTarget.split(separator: ":")
        if parts.count >= 7 {
            // Join the MAC parts (last 6 components after protocol)
            return parts[1...6].joined(separator: ":")
        }
        return ""
    }
    
    private func discoverBluetoothPrinters(call: FlutterMethodCall, result: @escaping FlutterResult) {
        let attemptSession = nextSessionId()
        if discoveryState == .cleaningUp || discoveryState == .suspendedAfterUsbDisconnect {
            print("DEBUG: Deferring Bluetooth discovery during cleanup/cooldown (session=\(attemptSession))")
            result([])
            return
        }
        guard discoveryState == .idle else {
            print("DEBUG: Ignoring Bluetooth discovery request; state=\(discoveryState.rawValue)")
            result([])
            return
        }
        setState(.discoveringBluetooth, sessionId: attemptSession)
        startWatchdog(sessionId: attemptSession, label: "bt")
        print("DEBUG: Starting Bluetooth printer discovery (session=\(attemptSession))...")
        
        // iOS hardware limitation: When USB cable connects, BT radio on printer physically turns off
        // and cannot re-enable until manual reconnect in iOS Settings + app restart
        if usbWasConnectedThisSession {
            print("DEBUG: Skipping Bluetooth discovery - USB was connected this session")
            print("DEBUG: iOS limitation: Printer's BT hardware disabled when USB connected")
            print("DEBUG: User must manually reconnect in iOS Settings after unplugging USB")
            currentBluetoothDeviceNames.removeAll()
            DispatchQueue.main.async { [weak self] in
                if let self = self { self.clearWatchdog(sessionId: attemptSession); if self.discoverySessionId == attemptSession { self.discoveryState = .idle } }
                result([])
            }
            return
        }
        
        // Clear previous Bluetooth device tracking
        currentBluetoothDeviceNames.removeAll()
        
        // Optimized: single discovery pass (Classic BT finds paired devices quickly)
        do {
            epsonWrapper.startBluetoothDiscovery { [weak self] printers in
                guard let self = self else { return }
                print("DEBUG: Bluetooth discovery callback received with \(printers.count) printers (session=\(attemptSession))")
                let printerStrings = printers.compactMap { printer -> String? in
                    guard let target = printer["target"] as? String,
                          let deviceName = printer["deviceName"] as? String else {
                        print("DEBUG: Skipping printer with missing target or deviceName")
                        return nil
                    }
                    print("DEBUG: Found Bluetooth printer - Target: \(target), Name: \(deviceName)")
                    if target.starts(with: "BT:") || target.starts(with: "BLE:") { self.currentBluetoothDeviceNames.insert(deviceName) }
                    return "\(target):\(deviceName)"
                }
                print("DEBUG: Bluetooth discovery found \(printerStrings.count) printers: \(printerStrings) (session=\(attemptSession))")
                DispatchQueue.main.async {
                    self.clearWatchdog(sessionId: attemptSession)
                    if self.discoverySessionId == attemptSession { self.discoveryState = .idle }
                    result(printerStrings)
                }
            }
        } catch {
            print("DEBUG: Bluetooth discovery threw error: \(error) (session=\(attemptSession))")
            DispatchQueue.main.async { [weak self] in
                if let self = self { self.clearWatchdog(sessionId: attemptSession); if self.discoverySessionId == attemptSession { self.discoveryState = .idle } }
                result([])
            }
        }
    }
    
    private func findPairedBluetoothPrinters(call: FlutterMethodCall, result: @escaping FlutterResult) {
        print("DEBUG: Starting paired Bluetooth printer discovery...")
        
        do {
            epsonWrapper.findPairedBluetoothPrinters { [weak self] printers in
                print("DEBUG: Paired Bluetooth discovery callback received with \(printers.count) printers")
                
                // Convert to legacy string format for backwards compatibility
                let printerStrings = printers.compactMap { printer -> String? in
                    guard let target = printer["target"] as? String,
                          let deviceName = printer["deviceName"] as? String else {
                        print("DEBUG: Skipping paired printer with missing target or deviceName")
                        return nil
                    }
                    
                    // Log the MAC address if available
                    if let macAddress = printer["macAddress"] as? String, !macAddress.isEmpty {
                        print("DEBUG: Found paired Bluetooth printer - Target: \(target), Name: \(deviceName), MAC: \(macAddress)")
                    } else {
                        print("DEBUG: Found paired Bluetooth printer - Target: \(target), Name: \(deviceName)")
                    }
                    
                    return "\(target):\(deviceName)"
                }
                
                print("DEBUG: Paired Bluetooth discovery completed. Found \(printerStrings.count) printers: \(printerStrings)")
                
                DispatchQueue.main.async {
                    result(printerStrings)
                }
            }
        } catch {
            print("DEBUG: Paired Bluetooth discovery threw error: \(error)")
            DispatchQueue.main.async {
                result([])
            }
        }
    }

    private func usbDiagnostics(result: @escaping FlutterResult) {
        print("DEBUG: usbDiagnostics called")
        result(["status": "not_implemented", "message": "USB diagnostics not yet implemented"])
    }
    
    private func pairBluetoothDevice(result: @escaping FlutterResult) {
        print("DEBUG: pairBluetoothDevice called")
        epsonWrapper.pairBluetoothDevice { target, ret in
            print("DEBUG: pairBluetoothDevice completed with ret=\(ret), target=\(String(describing: target))")
            if let target = target {
                result(["target": target, "resultCode": ret])
            } else {
                result(["target": NSNull(), "resultCode": ret])
            }
        }
    }

    private func connect(call: FlutterMethodCall, result: @escaping FlutterResult) {
        print("DEBUG: connect called with arguments: \(String(describing: call.arguments))")
        
        guard let args = call.arguments as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Invalid arguments", details: nil))
            return
        }
        
        guard let targetString = args["targetString"] as? String else {
            result(FlutterError(code: "MISSING_TARGET", message: "Target string required", details: nil))
            return
        }
        
        self.target = targetString
        
        // Parse printer series and language if provided
        if let series = args["printerSeries"] as? Int {
          self.printerSeries = Int32(series)
        }
        if let lang = args["printerLanguage"] as? Int {
          self.printerLang = Int32(lang)
        }
        
        let timeout = args["timeout"] as? Int ?? 15000
        
        // Use background QoS to avoid QoS inversion with Epson internals
        DispatchQueue.global(qos: .background).async {
          let success = self.epsonWrapper.connect(toPrinter: targetString, 
                                                          withSeries: self.printerSeries, 
                                                          language: self.printerLang, 
                                                          timeout: Int32(timeout))
          DispatchQueue.main.async {
            if success {
              print("DEBUG: Connected successfully to \(targetString)")
              result(nil)
            } else {
              print("DEBUG: Connection failed")
              result(FlutterError(code: "CONNECTION_FAILED", 
                                message: "Connection failed. Make sure your printer isn't connected to any other device via Bluetooth and try again.", 
                                details: nil))
            }
          }
        }
    }
    
    private func disconnect(result: @escaping FlutterResult) {
        print("DEBUG: disconnect called")
        
        DispatchQueue.global(qos: .userInitiated).async {
          self.epsonWrapper.disconnect()
          DispatchQueue.main.async {
            print("DEBUG: Disconnected successfully")
            result(nil)
          }
        }
    }
    
    private func printReceipt(call: FlutterMethodCall, result: @escaping FlutterResult) {
        print("DEBUG: printReceipt called")
        print("DEBUG: Arguments: \(call.arguments ?? "nil")")
        
        guard let args = call.arguments as? [String: Any] else {
          print("DEBUG: Invalid arguments - not a dictionary")
          result(FlutterError(code: "INVALID_ARGUMENTS", message: "Arguments must be a dictionary", details: nil))
          return
        }
        
        guard let commands = args["commands"] as? [[String: Any]] else {
          print("DEBUG: Commands not found or invalid format")
          print("DEBUG: Available keys: \(args.keys)")
          result(FlutterError(code: "INVALID_ARGUMENTS", message: "Commands are required and must be an array", details: nil))
          return
        }
        
        print("DEBUG: Processing \(commands.count) print commands")
        for (index, command) in commands.enumerated() {
            print("DEBUG: Command \(index): \(command)")
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
          let success = self.epsonWrapper.print(withCommands: commands)
          
          DispatchQueue.main.async {
            if success {
              print("DEBUG: Print job sent successfully")
              result(nil)
            } else {
              print("DEBUG: Print failed")
              result(FlutterError(code: "PRINT_FAILED", 
                                message: "Failed to print", 
                                details: nil))
            }
          }
        }
    }
    
    private func getStatus(result: @escaping FlutterResult) {
        print("DEBUG: getStatus called")
        
        let statusDict = epsonWrapper.getPrinterStatus()
        result(statusDict)
    }
    
    private func openCashDrawer(result: @escaping FlutterResult) {
        print("DEBUG: openCashDrawer called")
        
        DispatchQueue.global(qos: .userInitiated).async {
          let success = self.epsonWrapper.openCashDrawer()
          
          DispatchQueue.main.async {
            if success {
              print("DEBUG: Cash drawer pulse sent successfully")
              result(nil)
            } else {
              print("DEBUG: Cash drawer failed")
              result(FlutterError(code: "DRAWER_FAILED", 
                                message: "Failed to open cash drawer", 
                                details: nil))
            }
          }
        }
    }
    
    private func isConnected(result: @escaping FlutterResult) {
        let connected = (epsonWrapper.printer != nil)
        print("DEBUG: isConnected called - returning \(connected)")
        result(connected)
    }
    
    private func discoverUsbPrinters(result: @escaping FlutterResult) {
        let attemptSession = nextSessionId()
        if discoveryState == .cleaningUp || discoveryState == .suspendedAfterUsbDisconnect {
            print("DEBUG: Deferring USB discovery during cleanup/cooldown (session=\(attemptSession))")
            result([])
            return
        }
        guard discoveryState == .idle else {
            print("DEBUG: Ignoring USB discovery request; state=\(discoveryState.rawValue)")
            result([])
            return
        }
        setState(.discoveringUsb, sessionId: attemptSession)
        startWatchdog(sessionId: attemptSession, label: "usb")
        print("DEBUG: Starting USB printer discovery (session=\(attemptSession))...")
        
        // IMPORTANT: Skip Epson SDK entirely for USB discovery
        // The SDK's USB discovery internally triggers BLE finder which causes threading issues
        // EAAccessory provides direct hardware enumeration without SDK overhead
        print("DEBUG: Using EAAccessory-only mode (bypassing SDK to avoid BLE threading issues)")
        
        let accessories = EAAccessoryManager.shared().connectedAccessories
        let epsonAccessories = accessories.filter { acc in
            (acc.protocolStrings.contains("com.epson.escpos") || acc.protocolStrings.contains("com.epson.posprinter"))
        }
        
        if !epsonAccessories.isEmpty {
            print("DEBUG: Found \(epsonAccessories.count) EAAccessory devices")
            print("DEBUG: Current Bluetooth device names: \(currentBluetoothDeviceNames)")
            
            // Filter out devices that are Bluetooth connections
            // EAAccessory shows BOTH USB and Bluetooth Classic devices
            let usbPrinters = epsonAccessories.compactMap { acc -> String? in
                print("DEBUG: EAAccessory device: \(acc.name), connectionID: \(acc.connectionID), protocols: \(acc.protocolStrings)")
                
                // If this device was discovered via Bluetooth, it's a BT connection, not USB
                if currentBluetoothDeviceNames.contains(acc.name) || knownBluetoothAccessoryNames.contains(acc.name) || isLikelyBluetoothAccessoryName(acc.name) {
                    print("DEBUG: Skipping '\(acc.name)' - this is a Bluetooth connection, not USB")
                    return nil
                }
                
                print("DEBUG: Including '\(acc.name)' as USB device")
                return "USB::\(acc.name)"
            }
            
            print("DEBUG: USB discovery completed. Found \(usbPrinters.count) USB printers: \(usbPrinters) (session=\(attemptSession))")
            clearWatchdog(sessionId: attemptSession)
            if discoverySessionId == attemptSession { discoveryState = .idle }
            result(usbPrinters)
        } else {
            print("DEBUG: No Epson EAAccessory devices found (session=\(attemptSession))")
            clearWatchdog(sessionId: attemptSession)
            if discoverySessionId == attemptSession { discoveryState = .idle }
            result([])
        }
    }

    // Manual reset callable from Dart if UI detects prolonged freeze (optional future method exposure)
    private func debugResetStateIfStuck() {
        print("DEBUG: Manual state reset requested (current=\(discoveryState.rawValue))")
        discoveryState = .idle
    }
    
    private func isLikelyBluetoothAccessoryName(_ name: String) -> Bool {
        // Many Epson BT accessories include a suffix like _XXXXXX (hex) in the display name
        // e.g., TM-m30III_004541. Use a permissive regex for 4-12 hex chars at end.
        let pattern = "_([0-9A-Fa-f]{4,12})$"
        return name.range(of: pattern, options: .regularExpression) != nil
    }

    // Expose discovery state & session info to Dart
    private func getDiscoveryState(result: @escaping FlutterResult) {
        let stateMap: [String: Any] = [
            "state": discoveryState.rawValue,
            "sessionId": discoverySessionId,
            "usbWasConnectedThisSession": usbWasConnectedThisSession,
            "pendingWorkQueued": pendingDiscoveryWork != nil,
        ]
        result(stateMap)
    }

    // Public abort invoked from Dart
    private func abortDiscovery(result: @escaping FlutterResult) {
        print("DEBUG: abortDiscovery called from Dart")
        if discoveryState != .idle {
            debugResetStateIfStuck()
            pendingDiscoveryWork = nil
        }
        result(nil)
    }
}
