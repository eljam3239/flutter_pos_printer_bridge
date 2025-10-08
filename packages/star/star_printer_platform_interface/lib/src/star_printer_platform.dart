import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'models.dart';
import 'method_channel_star_printer.dart';

/// The interface that implementations of star_printer must implement.
abstract class StarPrinterPlatform extends PlatformInterface {
  /// Constructs a StarPrinterPlatform.
  StarPrinterPlatform() : super(token: _token);

  static final Object _token = Object();

  static StarPrinterPlatform _instance = MethodChannelStarPrinter();

  /// The default instance of [StarPrinterPlatform] to use.
  static StarPrinterPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [StarPrinterPlatform].
  static set instance(StarPrinterPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Discovers available Star printers
  Future<List<String>> discoverPrinters() {
    throw UnimplementedError('discoverPrinters() has not been implemented.');
  }

  /// Discovers available Bluetooth Star printers specifically
  Future<List<String>> discoverBluetoothPrinters() {
    throw UnimplementedError('discoverBluetoothPrinters() has not been implemented.');
  }

  /// Runs USB system diagnostics
  Future<Map<String, dynamic>> usbDiagnostics() {
    throw UnimplementedError('usbDiagnostics() has not been implemented.');
  }

  /// Connects to a Star printer
  Future<void> connect(StarConnectionSettings settings) {
    throw UnimplementedError('connect() has not been implemented.');
  }

  /// Disconnects from the current printer
  Future<void> disconnect() {
    throw UnimplementedError('disconnect() has not been implemented.');
  }

  /// Prints a receipt with the given content
  Future<void> printReceipt(PrintJob printJob) {
    throw UnimplementedError('printReceipt() has not been implemented.');
  }

  /// Gets the current printer status
  Future<PrinterStatus> getStatus() {
    throw UnimplementedError('getStatus() has not been implemented.');
  }

  /// Opens the cash drawer
  Future<void> openCashDrawer() {
    throw UnimplementedError('openCashDrawer() has not been implemented.');
  }

  /// Checks if a printer is connected
  Future<bool> isConnected() {
    throw UnimplementedError('isConnected() has not been implemented.');
  }
}
