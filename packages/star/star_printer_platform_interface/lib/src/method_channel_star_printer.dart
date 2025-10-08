import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'star_printer_platform.dart';
import 'models.dart';

/// An implementation of [StarPrinterPlatform] that uses method channels.
class MethodChannelStarPrinter extends StarPrinterPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('star_printer');

  @override
  Future<List<String>> discoverPrinters() async {
    final result = await methodChannel.invokeMethod<List<dynamic>>('discoverPrinters');
    return result?.cast<String>() ?? [];
  }

  @override
  Future<List<String>> discoverBluetoothPrinters() async {
    final result = await methodChannel.invokeMethod<List<dynamic>>('discoverBluetoothPrinters');
    return result?.cast<String>() ?? [];
  }

  @override
  Future<Map<String, dynamic>> usbDiagnostics() async {
    final result = await methodChannel.invokeMethod<Map<dynamic, dynamic>>('usbDiagnostics');
    return result?.cast<String, dynamic>() ?? {};
  }

  @override
  Future<void> connect(StarConnectionSettings settings) async {
    await methodChannel.invokeMethod<void>('connect', settings.toMap());
  }

  @override
  Future<void> disconnect() async {
    await methodChannel.invokeMethod<void>('disconnect');
  }

  @override
  Future<void> printReceipt(PrintJob printJob) async {
    await methodChannel.invokeMethod<void>('printReceipt', printJob.toMap());
  }

  @override
  Future<PrinterStatus> getStatus() async {
    final result = await methodChannel.invokeMethod<Map<String, dynamic>>('getStatus');
    return PrinterStatus.fromMap(result ?? {});
  }

  @override
  Future<void> openCashDrawer() async {
    await methodChannel.invokeMethod<void>('openCashDrawer');
  }

  @override
  Future<bool> isConnected() async {
    final result = await methodChannel.invokeMethod<bool>('isConnected');
    return result ?? false;
  }
}
