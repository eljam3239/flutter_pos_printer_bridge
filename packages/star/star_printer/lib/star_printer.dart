library star_printer;

export 'package:star_printer_platform_interface/star_printer_platform_interface.dart'
    show PrinterStatus, StarConnectionSettings, StarInterfaceType, PrintJob;

import 'package:star_printer_platform_interface/star_printer_platform_interface.dart';

/// The main Star printer API class
class StarPrinter {
  static final StarPrinterPlatform _platform = StarPrinterPlatform.instance;

  /// Discovers available Star printers on the network/bluetooth
  static Future<List<String>> discoverPrinters() {
    return _platform.discoverPrinters();
  }

  /// Discovers available Bluetooth Star printers specifically
  static Future<List<String>> discoverBluetoothPrinters() {
    return _platform.discoverBluetoothPrinters();
  }

  /// Runs USB system diagnostics for troubleshooting
  static Future<Map<String, dynamic>> usbDiagnostics() {
    return _platform.usbDiagnostics();
  }

  /// Connects to a Star printer using the provided settings
  static Future<void> connect(StarConnectionSettings settings) {
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

  /// Gets the current printer status
  static Future<PrinterStatus> getStatus() {
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
}
