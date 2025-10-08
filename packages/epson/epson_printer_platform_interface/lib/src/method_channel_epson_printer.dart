import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'epson_printer_platform.dart';
import 'models.dart';

/// An implementation of [EpsonPrinterPlatform] that uses method channels.
class MethodChannelEpsonPrinter extends EpsonPrinterPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('epson_printer');

  @override
  Future<List<String>> discoverPrinters() async {
    final result = await methodChannel.invokeMethod<List<dynamic>>('discoverPrinters');
    return result?.cast<String>() ?? [];
  }

  @override
  Future<List<String>> discoverBluetoothPrinters() async {
    final List<dynamic> result = await methodChannel.invokeMethod('discoverBluetoothPrinters');
    return result.cast<String>();
  }

  @override
  Future<List<String>> discoverUsbPrinters() async {
    final List<dynamic> result = await methodChannel.invokeMethod('discoverUsbPrinters');
    return result.cast<String>();
  }

  @override
  Future<List<String>> findPairedBluetoothPrinters() async {
    final List<dynamic> result = await methodChannel.invokeMethod('findPairedBluetoothPrinters');
    return result.cast<String>();
  }

  @override
  Future<Map<String, dynamic>> pairBluetoothDevice() async {
    final Map<dynamic, dynamic> result = await methodChannel.invokeMethod('pairBluetoothDevice');
    return Map<String, dynamic>.from(result);
  }

  @override
  Future<Map<String, dynamic>> usbDiagnostics() async {
    final result = await methodChannel.invokeMethod<Map<dynamic, dynamic>>('usbDiagnostics');
    return result?.cast<String, dynamic>() ?? {};
  }

  @override
  Future<void> connect(EpsonConnectionSettings settings) async {
    await methodChannel.invokeMethod<void>('connect', settings.toMap());
  }

  @override
  Future<void> disconnect() async {
    await methodChannel.invokeMethod<void>('disconnect');
  }

  @override
  Future<void> printReceipt(EpsonPrintJob printJob) async {
    await methodChannel.invokeMethod<void>('printReceipt', printJob.toMap());
  }

  @override
  Future<EpsonPrinterStatus> getStatus() async {
    final result = await methodChannel.invokeMethod<Map<String, dynamic>>('getStatus');
    return EpsonPrinterStatus.fromMap(result ?? {});
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
