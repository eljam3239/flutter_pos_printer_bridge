export 'package:epson_printer_platform_interface/epson_printer_platform_interface.dart'
  show EpsonPrinterStatus, EpsonConnectionSettings, EpsonPortType, EpsonPrintJob, 
     EpsonPrintCommand, EpsonCommandType, EpsonImageConfig;

import 'package:epson_printer_platform_interface/epson_printer_platform_interface.dart';

/// The main Epson printer API class
class EpsonPrinter {
  static final EpsonPrinterPlatform _platform = EpsonPrinterPlatform.instance;

  /// Discovers available Epson printers on the network/bluetooth
  static Future<List<String>> discoverPrinters() {
    return _platform.discoverPrinters();
  }

  /// Discovers available Bluetooth Epson printers. On iOS this returns both live and already paired devices.
  static Future<List<String>> discoverBluetoothPrinters() {
    return _platform.discoverBluetoothPrinters();
  }

  /// Discovers available USB Epson printers specifically
  static Future<List<String>> discoverUsbPrinters() {
    return _platform.discoverUsbPrinters();
  }

  /// Discovers all printer interfaces in one go (native orchestrated)
  static Future<List<String>> discoverAllPrinters() {
    return _platform.discoverAllPrinters();
  }

  @Deprecated('Use discoverBluetoothPrinters() instead; it returns paired and live Bluetooth printers.')
  static Future<List<String>> findPairedBluetoothPrinters() {
    // Alias to keep API simple and consistent
    return _platform.discoverBluetoothPrinters();
  }

  static Future<Map<String, dynamic>> pairBluetoothDevice() {
    return _platform.pairBluetoothDevice();
  }

  /// Runs USB system diagnostics for troubleshooting
  static Future<Map<String, dynamic>> usbDiagnostics() {
    return _platform.usbDiagnostics();
  }

  /// Connects to a Epson printer using the provided settings
  static Future<void> connect(EpsonConnectionSettings settings) {
    return _platform.connect(settings);
  }

  /// Disconnects from the current printer
  static Future<void> disconnect() {
    return _platform.disconnect();
  }

  /// Prints a receipt with the given content
  static Future<void> printReceipt(EpsonPrintJob printJob) {
    return _platform.printReceipt(printJob);
  }

  /// Gets the current printer status
  static Future<EpsonPrinterStatus> getStatus() {
    return _platform.getStatus();
  }

  /// Opens the cash drawer connected to the printer
  static Future<void> openCashDrawer() {
    return _platform.openCashDrawer();
  }

  /// Checks if a printer is currently connected
  static Future<bool> isConnected() {
    return _platform.isConnected();
  }

  /// Returns current native discovery state (idle, discoveringLan, discoveringBluetooth, discoveringUsb, cleaningUp, suspendedAfterUsbDisconnect)
  static Future<Map<String, dynamic>> getDiscoveryState() {
    return _platform.getDiscoveryState();
  }

  /// Aborts an in-progress discovery and forces idle (use if UI detects freeze)
  static Future<void> abortDiscovery() {
    return _platform.abortDiscovery();
  }
}


