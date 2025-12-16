library zebra_printer;

export 'package:zebra_printer_platform_interface/zebra_printer_platform_interface.dart'
    show PrinterStatus, ZebraConnectionSettings, ZebraInterfaceType, PrintJob, 
         DiscoveredPrinter, ConnectedPrinter, LabelData, ReceiptData, ReceiptLineItem, ZebraPrintLanguage;

import 'package:zebra_printer_platform_interface/zebra_printer_platform_interface.dart';

/// The main Zebra printer API class
class ZebraPrinter {
  static final ZebraPrinterPlatform _platform = ZebraPrinterPlatform.instance;

  /// Discovers available Zebra printers using local broadcast
  static Future<List<DiscoveredPrinter>> discoverPrinters() {
    return _platform.discoverPrinters();
  }

  /// Discovers printers using multicast with specified hops
  static Future<List<DiscoveredPrinter>> discoverMulticastPrinters({int hops = 3, int? timeoutMs}) {
    return _platform.discoverMulticastPrinters(hops: hops, timeoutMs: timeoutMs);
  }

  /// Discovers printers using directed broadcast to a specific subnet
  static Future<List<DiscoveredPrinter>> discoverDirectedBroadcast(String ipAddress, {int? timeoutMs}) {
    return _platform.discoverDirectedBroadcast(ipAddress, timeoutMs: timeoutMs);
  }

  /// Discovers printers in a subnet range (e.g., "192.168.1.*", "192.168.1.10-50")
  static Future<List<DiscoveredPrinter>> discoverSubnetSearch(String subnetRange, {int? timeoutMs}) {
    return _platform.discoverSubnetSearch(subnetRange, timeoutMs: timeoutMs);
  }

  /// Automatically discovers printers on local network subnets
  /// This method detects the device's current network and searches common subnet ranges
  static Future<List<DiscoveredPrinter>> discoverNetworkPrintersAuto({int? timeoutMs}) {
    return _platform.discoverNetworkPrintersAuto(timeoutMs: timeoutMs);
  }

  /// Discovers available Bluetooth Zebra printers specifically
  static Future<List<DiscoveredPrinter>> discoverBluetoothPrinters() {
    return _platform.discoverBluetoothPrinters();
  }

  /// Discovers Bluetooth devices using native Android scanner (for debugging)
  static Future<List<DiscoveredPrinter>> discoverBluetoothNative() {
    return _platform.discoverBluetoothNative();
  }

  /// Tests direct BLE connection to a printer using known MAC address
  static Future<List<DiscoveredPrinter>> testDirectBleConnection({String? macAddress}) {
    return _platform.testDirectBleConnection(macAddress: macAddress);
  }

  /// Discovers USB printers
  static Future<List<DiscoveredPrinter>> discoverUsbPrinters() {
    return _platform.discoverUsbPrinters();
  }

  /// Connects to a Zebra printer using the provided settings
  static Future<void> connect(ZebraConnectionSettings settings) {
    return _platform.connect(settings);
  }

  /// Disconnects from the current printer
  static Future<void> disconnect() {
    return _platform.disconnect();
  }

  /// Prints a receipt with the given content
  static Future<void> printReceipt(PrintJob printJob) {
    return _platform.printReceipt(printJob);
  }

  /// Sends raw ZPL or CPCL commands to the printer
  static Future<void> sendCommands(String commands, {ZebraPrintLanguage? language}) {
    return _platform.sendCommands(commands, language: language);
  }

  /// Gets the printer control language (ZPL or CPCL)
  static Future<ZebraPrintLanguage> getPrinterLanguage() {
    return _platform.getPrinterLanguage();
  }

  /// Retrieves an SGD (Set Get Do) parameter from the printer
  static Future<String?> getSgdParameter(String parameter) {
    return _platform.getSgdParameter(parameter);
  }

  /// Sets an SGD (Set Get Do) parameter on the printer  
  static Future<void> setSgdParameter(String parameter, String value) {
    return _platform.setSgdParameter(parameter, value);
  }

  /// Sets the label length using ZPL ^LL command for immediate effect
  static Future<void> setLabelLength(int lengthInDots) {
    return _platform.setLabelLength(lengthInDots);
  }

  /// Requests Bluetooth permissions from the user (Android only)
  static Future<bool> requestBluetoothPermissions() {
    return _platform.requestBluetoothPermissions();
  }

  /// Requests USB permissions for a specific device (Android only)
  static Future<bool> requestUsbPermissions({required String deviceName}) {
    return _platform.requestUsbPermissions(deviceName: deviceName);
  }

  /// Gets the current printer status
  static Future<PrinterStatus> getStatus() {
    return _platform.getStatus();
  }

  /// Checks if a printer is currently connected
  static Future<bool> isConnected() {
    return _platform.isConnected();
  }

  /// Gets printer dimensions (width, height, DPI, etc.)
  static Future<Map<String, int>> getPrinterDimensions() {
    return _platform.getPrinterDimensions();
  }
}
