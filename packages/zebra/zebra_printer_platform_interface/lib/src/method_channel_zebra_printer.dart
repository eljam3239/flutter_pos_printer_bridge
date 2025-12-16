import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'zebra_printer_platform.dart';
import 'models.dart';

/// An implementation of [ZebraPrinterPlatform] that uses method channels.
class MethodChannelZebraPrinter extends ZebraPrinterPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('zebra_printer');

  @override
  Future<List<DiscoveredPrinter>> discoverPrinters() async {
    final result = await methodChannel.invokeMethod<List<dynamic>>('discoverPrinters');
    return result?.map((item) => DiscoveredPrinter.fromMap(item.cast<String, dynamic>())).toList() ?? [];
  }

  @override
  Future<List<DiscoveredPrinter>> discoverMulticastPrinters({int hops = 3, int? timeoutMs}) async {
    final result = await methodChannel.invokeMethod<List<dynamic>>('discoverMulticastPrinters', {
      'hops': hops,
      'timeoutMs': timeoutMs,
    });
    return result?.map((item) => DiscoveredPrinter.fromMap(item.cast<String, dynamic>())).toList() ?? [];
  }

  @override
  Future<List<DiscoveredPrinter>> discoverDirectedBroadcast(String ipAddress, {int? timeoutMs}) async {
    final result = await methodChannel.invokeMethod<List<dynamic>>('discoverDirectedBroadcast', {
      'ipAddress': ipAddress,
      'timeoutMs': timeoutMs,
    });
    return result?.map((item) => DiscoveredPrinter.fromMap(item.cast<String, dynamic>())).toList() ?? [];
  }

  @override
  Future<List<DiscoveredPrinter>> discoverSubnetSearch(String subnetRange, {int? timeoutMs}) async {
    final result = await methodChannel.invokeMethod<List<dynamic>>('discoverSubnetSearch', {
      'subnetRange': subnetRange,
      'timeoutMs': timeoutMs,
    });
    return (result ?? []).map((e) => DiscoveredPrinter.fromMap(Map<String, dynamic>.from(e))).toList();
  }

  @override
  Future<List<DiscoveredPrinter>> discoverNetworkPrintersAuto({int? timeoutMs}) async {
    final result = await methodChannel.invokeMethod<List<dynamic>>('discoverNetworkPrintersAuto', {
      'timeoutMs': timeoutMs,
    });
    return (result ?? []).map((e) => DiscoveredPrinter.fromMap(Map<String, dynamic>.from(e))).toList();
  }

  @override
  Future<List<DiscoveredPrinter>> discoverBluetoothPrinters() async {
    final result = await methodChannel.invokeMethod<List<dynamic>>('discoverBluetoothPrinters');
    return result?.map((item) => DiscoveredPrinter.fromMap(Map<String, dynamic>.from(item))).toList() ?? [];
  }

  @override
  Future<List<DiscoveredPrinter>> discoverBluetoothNative() async {
    final result = await methodChannel.invokeMethod<List<dynamic>>('discoverBluetoothNative');
    return result?.map((item) => DiscoveredPrinter.fromMap(Map<String, dynamic>.from(item))).toList() ?? [];
  }

  @override
  Future<List<DiscoveredPrinter>> testDirectBleConnection({String? macAddress}) async {
    final result = await methodChannel.invokeMethod<List<dynamic>>('testDirectBleConnection', {
      if (macAddress != null) 'macAddress': macAddress,
    });
    return result?.map((item) => DiscoveredPrinter.fromMap(Map<String, dynamic>.from(item))).toList() ?? [];
  }

  @override
  Future<List<DiscoveredPrinter>> discoverUsbPrinters() async {
    final result = await methodChannel.invokeMethod<List<dynamic>>('discoverUsbPrinters');
    return result?.map((item) => DiscoveredPrinter.fromMap(item.cast<String, dynamic>())).toList() ?? [];
  }

  @override
  Future<void> connect(ZebraConnectionSettings settings) async {
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
  Future<void> sendCommands(String commands, {ZebraPrintLanguage? language}) async {
    await methodChannel.invokeMethod<void>('sendCommands', {
      'commands': commands,
      'language': language?.name,
    });
  }

  @override
  Future<ZebraPrintLanguage> getPrinterLanguage() async {
    final result = await methodChannel.invokeMethod<String>('getPrinterLanguage');
    switch (result?.toLowerCase()) {
      case 'cpcl':
        return ZebraPrintLanguage.cpcl;
      case 'zpl':
      default:
        return ZebraPrintLanguage.zpl;
    }
  }

  @override
  Future<String?> getSgdParameter(String parameter) async {
    final result = await methodChannel.invokeMethod<String>('getSgdParameter', {'parameter': parameter});
    return result;
  }

  @override
  Future<bool> requestBluetoothPermissions() async {
    final result = await methodChannel.invokeMethod<bool>('requestBluetoothPermissions');
    return result ?? false;
  }

  @override
  Future<bool> requestUsbPermissions({required String deviceName}) async {
    final result = await methodChannel.invokeMethod<bool>('requestUsbPermissions', {
      'deviceName': deviceName,
    });
    return result ?? false;
  }

  @override
  Future<void> setSgdParameter(String parameter, String value) async {
    await methodChannel.invokeMethod<void>('setSgdParameter', {
      'parameter': parameter,
      'value': value,
    });
  }

  @override
  Future<PrinterStatus> getStatus() async {
    final result = await methodChannel.invokeMethod<Map<String, dynamic>>('getStatus');
    return PrinterStatus.fromMap(result ?? {});
  }

  @override
  Future<bool> isConnected() async {
    final result = await methodChannel.invokeMethod<bool>('isConnected');
    return result ?? false;
  }

  @override
  Future<Map<String, int>> getPrinterDimensions() async {
    final result = await methodChannel.invokeMethod<Map<Object?, Object?>>('getPrinterDimensions');
    if (result == null) return {};
    
    // Safely cast the result to Map<String, int>
    final Map<String, int> dimensions = {};
    for (final entry in result.entries) {
      final key = entry.key?.toString();
      final value = entry.value;
      if (key != null && value is num) {
        dimensions[key] = value.toInt();
      }
    }
    return dimensions;
  }

  @override
  Future<void> setLabelLength(int lengthInDots) async {
    await methodChannel.invokeMethod<void>('setLabelLength', {
      'lengthInDots': lengthInDots,
    });
  }
}
