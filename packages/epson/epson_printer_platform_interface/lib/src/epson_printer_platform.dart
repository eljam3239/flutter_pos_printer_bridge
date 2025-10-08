import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'models.dart';
import 'method_channel_epson_printer.dart';

/// The interface that implementations of epson_printer must implement.
abstract class EpsonPrinterPlatform extends PlatformInterface {
  /// Constructs a EpsonPrinterPlatform.
  EpsonPrinterPlatform() : super(token: _token);

  static final Object _token = Object();

  static EpsonPrinterPlatform _instance = MethodChannelEpsonPrinter();

  /// The default instance of [EpsonPrinterPlatform] to use.
  static EpsonPrinterPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [EpsonPrinterPlatform].
  static set instance(EpsonPrinterPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Discovers available Epson printers
  Future<List<String>> discoverPrinters() {
    throw UnimplementedError('discoverPrinters() has not been implemented.');
  }

  /// Discovers available Bluetooth Epson printers specifically
  Future<List<String>> discoverBluetoothPrinters() {
    throw UnimplementedError('discoverBluetoothPrinters() has not been implemented.');
  }

  /// Discovers available USB Epson printers specifically
  Future<List<String>> discoverUsbPrinters() {
    throw UnimplementedError('discoverUsbPrinters() has not been implemented.');
  }

  Future<List<String>> findPairedBluetoothPrinters() {
    throw UnimplementedError('findPairedBluetoothPrinters() has not been implemented.');
  }

  Future<Map<String, dynamic>> pairBluetoothDevice() {
    throw UnimplementedError('pairBluetoothDevice() has not been implemented.');
  }

  /// Runs USB system diagnostics
  Future<Map<String, dynamic>> usbDiagnostics() {
    throw UnimplementedError('usbDiagnostics() has not been implemented.');
  }

  /// Connects to a Epson printer
  Future<void> connect(EpsonConnectionSettings settings) {
    throw UnimplementedError('connect() has not been implemented.');
  }

  /// Disconnects from the current printer
  Future<void> disconnect() {
    throw UnimplementedError('disconnect() has not been implemented.');
  }

  /// Prints a receipt with the given content
  Future<void> printReceipt(EpsonPrintJob printJob) {
    throw UnimplementedError('printReceipt() has not been implemented.');
  }

  /// Gets the current printer status
  Future<EpsonPrinterStatus> getStatus() {
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
