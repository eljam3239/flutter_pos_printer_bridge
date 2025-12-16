import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'models.dart';
import 'method_channel_zebra_printer.dart';

/// The interface that implementations of zebra_printer must implement.
abstract class ZebraPrinterPlatform extends PlatformInterface {
  /// Constructs a ZebraPrinterPlatform.
  ZebraPrinterPlatform() : super(token: _token);

  static final Object _token = Object();

  static ZebraPrinterPlatform _instance = MethodChannelZebraPrinter();

  /// The default instance of [ZebraPrinterPlatform] to use.
  static ZebraPrinterPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [ZebraPrinterPlatform].
  static set instance(ZebraPrinterPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Discovers available Zebra printers using local broadcast
  Future<List<DiscoveredPrinter>> discoverPrinters() {
    throw UnimplementedError('discoverPrinters() has not been implemented.');
  }

  /// Discovers printers using multicast with specified hops
  Future<List<DiscoveredPrinter>> discoverMulticastPrinters({int hops = 3, int? timeoutMs}) {
    throw UnimplementedError('discoverMulticastPrinters() has not been implemented.');
  }

  /// Discovers printers using directed broadcast to a specific subnet
  Future<List<DiscoveredPrinter>> discoverDirectedBroadcast(String ipAddress, {int? timeoutMs}) {
    throw UnimplementedError('discoverDirectedBroadcast() has not been implemented.');
  }

  /// Discovers printers in a subnet range (e.g., "192.168.1.*", "192.168.1.10-50")
  Future<List<DiscoveredPrinter>> discoverSubnetSearch(String subnetRange, {int? timeoutMs}) {
    throw UnimplementedError('discoverSubnetSearch() has not been implemented.');
  }

  /// Automatically discovers printers on local network subnets
  /// This method detects the device's current network and searches common subnet ranges
  Future<List<DiscoveredPrinter>> discoverNetworkPrintersAuto({int? timeoutMs}) {
    throw UnimplementedError('discoverNetworkPrintersAuto() has not been implemented.');
  }

  /// Discovers available Bluetooth Zebra printers specifically
  Future<List<DiscoveredPrinter>> discoverBluetoothPrinters() {
    throw UnimplementedError('discoverBluetoothPrinters() has not been implemented.');
  }

  /// Discovers Bluetooth devices using native Android scanner (debugging)
  Future<List<DiscoveredPrinter>> discoverBluetoothNative() {
    throw UnimplementedError('discoverBluetoothNative() has not been implemented.');
  }

  /// Tests direct BLE connection to a printer using known MAC address
  Future<List<DiscoveredPrinter>> testDirectBleConnection({String? macAddress}) {
    throw UnimplementedError('testDirectBleConnection() has not been implemented.');
  }

  /// Discovers USB printers
  Future<List<DiscoveredPrinter>> discoverUsbPrinters() {
    throw UnimplementedError('discoverUsbPrinters() has not been implemented.');
  }

  /// Connects to a Zebra printer
  Future<void> connect(ZebraConnectionSettings settings) {
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

  /// Sends raw ZPL or CPCL commands to the printer
  Future<void> sendCommands(String commands, {ZebraPrintLanguage? language}) {
    throw UnimplementedError('sendCommands() has not been implemented.');
  }

  /// Requests Bluetooth permissions from the user
  Future<bool> requestBluetoothPermissions() {
    throw UnimplementedError('requestBluetoothPermissions() has not been implemented.');
  }

  /// Requests USB permissions for a specific device
  Future<bool> requestUsbPermissions({required String deviceName}) {
    throw UnimplementedError('requestUsbPermissions() has not been implemented.');
  }

  /// Gets the printer control language (ZPL or CPCL)
  Future<ZebraPrintLanguage> getPrinterLanguage() {
    throw UnimplementedError('getPrinterLanguage() has not been implemented.');
  }

  /// Retrieves an SGD (Set Get Do) parameter from the printer
  Future<String?> getSgdParameter(String parameter) {
    throw UnimplementedError('getSgdParameter() has not been implemented.');
  }

  /// Sets an SGD (Set Get Do) parameter on the printer  
  Future<void> setSgdParameter(String parameter, String value) {
    throw UnimplementedError('setSgdParameter() has not been implemented.');
  }

  /// Gets the current printer status
  Future<PrinterStatus> getStatus() {
    throw UnimplementedError('getStatus() has not been implemented.');
  }

  /// Checks if a printer is connected
  Future<bool> isConnected() {
    throw UnimplementedError('isConnected() has not been implemented.');
  }

  /// Gets printer dimensions (width, height, DPI, etc.)
  Future<Map<String, int>> getPrinterDimensions() {
    throw UnimplementedError('getPrinterDimensions() has not been implemented.');
  }

  /// Sets the label length using ZPL ^LL command for immediate effect
  Future<void> setLabelLength(int lengthInDots) {
    throw UnimplementedError('setLabelLength() has not been implemented.');
  }
}
