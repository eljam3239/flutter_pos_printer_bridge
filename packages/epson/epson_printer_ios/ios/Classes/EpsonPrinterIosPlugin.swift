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
    
    override init() {
        epsonWrapper = EpsonSDKWrapper()
        super.init()
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
            // Debug: list currently connected ExternalAccessory devices and protocol strings
            let accessories = EAAccessoryManager.shared().connectedAccessories
            if accessories.isEmpty {
                print("EAAccessory: No connected accessories found.")
            } else {
                for acc in accessories {
                    print("EAAccessory connected: name=\(acc.name), manufacturer=\(acc.manufacturer), model=\(acc.modelNumber), serial=\(acc.serialNumber), protocols=\(acc.protocolStrings)")
                }
            }
            discoverBluetoothPrinters(call: call, result: result)
        case "discoverUsbPrinters":
            discoverUsbPrinters(result: result)
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
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func discoverPrinters(call: FlutterMethodCall, result: @escaping FlutterResult) {
        print("DEBUG: Starting Epson printer discovery...")
        
        // Start with TCP discovery (most common for network printers)
        let filterOption: Int32 = 1 // EPOS2_PORTTYPE_TCP
        
        print("DEBUG: Using TCP filter option: \(filterOption)")
        
        // Add error handling wrapper
        do {
            epsonWrapper.startDiscovery(withFilter: filterOption) { [weak self] printers in
                print("DEBUG: Discovery callback received with \(printers.count) printers")
                
                // Convert to legacy string format for backwards compatibility
                let printerStrings = printers.compactMap { printer -> String? in
                    guard let target = printer["target"] as? String,
                          let deviceName = printer["deviceName"] as? String else {
                        print("DEBUG: Skipping printer with invalid data: \(printer)")
                        return nil
                    }
                    print("DEBUG: Found printer: \(target):\(deviceName)")
                    return "\(target):\(deviceName)"
                }
                
                print("DEBUG: Discovery completed. Found \(printerStrings.count) printers: \(printerStrings)")
                
                DispatchQueue.main.async {
                    result(printerStrings)
                }
            }
        } catch {
            print("DEBUG: Discovery threw error: \(error)")
            DispatchQueue.main.async {
                result([])
            }
        }
    }
    
    private func discoverBluetoothPrinters(call: FlutterMethodCall, result: @escaping FlutterResult) {
        print("DEBUG: Starting Bluetooth printer discovery...")
        
        // First: active discovery (BLE with fallback to Classic BT)
        do {
            epsonWrapper.startBluetoothDiscovery { [weak self] livePrinters in
                print("DEBUG: Bluetooth discovery callback received with \(livePrinters.count) printers")
                
                let liveStrings = livePrinters.compactMap { printer -> String? in
                    guard let target = printer["target"] as? String,
                          let deviceName = printer["deviceName"] as? String else {
                        print("DEBUG: Skipping printer with missing target or deviceName")
                        return nil
                    }
                    print("DEBUG: Found Bluetooth printer - Target: \(target), Name: \(deviceName)")
                    return "\(target):\(deviceName)"
                }
                
                // Second: paired discovery to include already paired devices
                self?.epsonWrapper.findPairedBluetoothPrinters { pairedPrinters in
                    print("DEBUG: Paired Bluetooth discovery callback received with \(pairedPrinters.count) printers")
                    let pairedStrings = pairedPrinters.compactMap { printer -> String? in
                        guard let target = printer["target"] as? String,
                              let deviceName = printer["deviceName"] as? String else { return nil }
                        return "\(target):\(deviceName)"
                    }
                    
                    // Merge and de-dupe
                    var set = Set<String>()
                    liveStrings.forEach { set.insert($0) }
                    pairedStrings.forEach { set.insert($0) }
                    let all = Array(set)
                    print("DEBUG: Bluetooth combined discovery found \(all.count) printers: \(all)")
                    DispatchQueue.main.async { result(all) }
                }
            }
        } catch {
            print("DEBUG: Bluetooth discovery threw error: \(error)")
            DispatchQueue.main.async { result([]) }
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
                                message: "Failed to connect to printer", 
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
        print("DEBUG: Starting USB printer discovery...")
        // USB discovery: use port type USB and deviceType PRINTER
        let EPOS2_PORTTYPE_USB_VALUE: Int32 = 4 // EPOS2_PORTTYPE_USB
        epsonWrapper.startDiscovery(withFilter: EPOS2_PORTTYPE_USB_VALUE) { printers in
            var printerStrings = printers.compactMap { printer -> String? in
                guard let target = printer["target"] as? String,
                      let deviceName = printer["deviceName"] as? String else { return nil }
                return "\(target):\(deviceName)"
            }

            if printerStrings.isEmpty {
                // Fallback for iOS: discovery for USB may return 0. If an Epson accessory is connected,
                // return a default USB target that connects to the first USB device.
                let accessories = EAAccessoryManager.shared().connectedAccessories
                let epsonAccessories = accessories.filter { acc in
                    acc.protocolStrings.contains("com.epson.escpos") || acc.protocolStrings.contains("com.epson.posprinter")
                }
                if !epsonAccessories.isEmpty {
                    let names = epsonAccessories.map { $0.name }
                    print("DEBUG: USB discovery empty. EAAccessory fallback found Epson accessories: \(names)")
                    // Use the accessory names for display; target should be just 'USB:' so OS picks the first device
                    // If multiple, still present one entry per accessory to help the user choose visually
                    let fallback = epsonAccessories.map { "USB::\($0.name)" }
                    printerStrings.append(contentsOf: fallback)
                } else {
                    print("DEBUG: USB discovery empty and no Epson EAAccessory found")
                }
            }

            print("DEBUG: USB discovery completed. Found \(printerStrings.count) printers: \(printerStrings)")
            result(printerStrings)
        }
    }
}
