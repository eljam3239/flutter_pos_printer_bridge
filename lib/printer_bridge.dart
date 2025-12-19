import 'package:epson_printer/epson_printer.dart';
import 'dart:io';

class PrinterBridge {
  /// Discover printers for a specific brand
  /// Returns list of discovered printers with their connection details
  static Future<List<Map<String, String>>> discover(String brand) async {
    switch (brand.toLowerCase()) {
      case 'epson':
        return _discoverEpsonPrinters();
      case 'star':
        throw UnimplementedError('Star discovery not implemented yet');
      case 'zebra':
        throw UnimplementedError('Zebra discovery not implemented yet');
      default:
        throw ArgumentError('Unsupported brand: $brand');
    }
  }

  static Future<List<Map<String, String>>> _discoverEpsonPrinters() async {
    // Check if native discovery is idle (prevent concurrent discoveries)
    try {
      final native = await EpsonPrinter.getDiscoveryState();
      final nativeDiscoveryState = (native['state'] as String?) ?? 'idle';
      if (nativeDiscoveryState != 'idle') {
        throw Exception('Epson discovery already in progress');
      }
    } catch (_) {}

    final List<String> allPrinters = [];
    
    // Stage 1: LAN discovery
    try {
      final lanPrinters = await EpsonPrinter.discoverPrinters();
      allPrinters.addAll(lanPrinters);
    } catch (e) {
      print('Epson LAN discovery error: $e');
    }

    // Small delay between discoveries
    await Future.delayed(const Duration(milliseconds: 500));

    // Stage 2: Bluetooth discovery 
    // Note: iOS has complexity around USB disabling BT radio - for now always try BT
    // TODO: Consider adding options parameter if POS app needs to handle this edge case
    try {
      final btPrinters = await EpsonPrinter.discoverBluetoothPrinters();
      allPrinters.addAll(btPrinters);
    } catch (e) {
      print('Epson Bluetooth discovery error: $e');
    }

    // Small delay before USB
    await Future.delayed(const Duration(milliseconds: 500));

    // Stage 3: USB discovery
    try {
      final usbPrinters = await EpsonPrinter.discoverUsbPrinters();
      allPrinters.addAll(usbPrinters);
    } catch (e) {
      print('Epson USB discovery error: $e');
    }

    // Convert to hybrid format
    return allPrinters.map((raw) => _parseEpsonPrinter(raw)).toList();
  }

  static Map<String, String> _parseEpsonPrinter(String raw) {
    // Parse Epson format: "TCP:A4:D7:3C:AA:CA:01:TM-m30III"
    // Format is: INTERFACE:MAC_ADDRESS:MODEL
    
    final firstColon = raw.indexOf(':');
    if (firstColon == -1) {
      return {
        'raw': raw,
        'brand': 'epson',
        'interface': '',
        'address': raw,
        'model': '',
      };
    }
    
    final interface = raw.substring(0, firstColon).toLowerCase();
    final remaining = raw.substring(firstColon + 1);
    
    // Find the last colon to separate address from model
    final lastColon = remaining.lastIndexOf(':');
    if (lastColon == -1) {
      return {
        'raw': raw,
        'brand': 'epson',
        'interface': interface,
        'address': remaining,
        'model': '',
      };
    }
    
    final address = remaining.substring(0, lastColon);
    final model = remaining.substring(lastColon + 1);
    
    return {
      'raw': raw,
      'brand': 'epson',
      'interface': interface,
      'address': address,
      'model': model,
    };
  }

  /// Connect to a printer using brand, interface type, and connection string
  /// Returns true if connection successful
  static Future<bool> connect(String brand, String interface, String connectionString) async {
    switch (brand.toLowerCase()) {
      case 'epson':
        return _connectEpsonPrinter(interface, connectionString);
      case 'star':
        throw UnimplementedError('Star connection not implemented yet');
      case 'zebra':
        throw UnimplementedError('Zebra connection not implemented yet');
      default:
        throw ArgumentError('Unsupported brand: $brand');
    }
  }

  static Future<bool> _connectEpsonPrinter(String interface, String connectionString) async {
    try {
      // Disconnect if already connected
      try {
        await EpsonPrinter.disconnect();
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (_) {}

      // Reconstruct the target string that Epson SDK expects
      String target;
      EpsonPortType portType;
      
      switch (interface.toLowerCase()) {
        case 'tcp':
          target = 'TCP:$connectionString';
          portType = EpsonPortType.tcp;
          break;
        case 'bt':
          target = 'BT:$connectionString';
          portType = EpsonPortType.bluetooth;
          break;
        case 'ble':
          target = 'BLE:$connectionString';
          portType = EpsonPortType.bluetoothLe;
          break;
        case 'usb':
          target = 'USB:$connectionString';
          portType = EpsonPortType.usb;
          break;
        default:
          throw ArgumentError('Unsupported Epson interface: $interface');
      }

      final settings = EpsonConnectionSettings(
        portType: portType,
        identifier: target,
        timeout: portType == EpsonPortType.bluetoothLe ? 30000 : 15000,
      );

      await EpsonPrinter.connect(settings);
      return true;
    } catch (e) {
      print('Epson connection failed: $e');
      return false;
    }
  }

  /// Print a receipt using the connected printer of the specified brand
  /// Returns true if print successful
  static Future<bool> printReceipt(String brand, Map<String, dynamic> receiptData) async {
    throw UnimplementedError('Print receipt not implemented yet');
  }

  /// Print a label using the connected printer of the specified brand
  /// Returns true if print successful
  static Future<bool> printLabel(String brand, Map<String, dynamic> labelData) async {
    throw UnimplementedError('Print label not implemented yet');
  }
}