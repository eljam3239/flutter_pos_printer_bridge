import 'package:epson_printer/epson_printer.dart';

/// Universal line item class for receipts
class PrinterLineItem {
  final String itemName;
  final int quantity;
  final double unitPrice;
  final double totalPrice;

  PrinterLineItem({
    required this.itemName,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
  });
}

/// Universal receipt data class for all printer brands
class PrinterReceiptData {
  final String storeName;
  final String storeAddress;
  final String? storePhone;
  final String date;
  final String time;
  final String? cashierName;
  final String? receiptNumber;
  final String? laneNumber;
  final List<PrinterLineItem> items;
  final String? thankYouMessage;
  final String? logoBase64;
  final DateTime? transactionDate;

  PrinterReceiptData({
    required this.storeName,
    required this.storeAddress,
    this.storePhone,
    required this.date,
    required this.time,
    this.cashierName,
    this.receiptNumber,
    this.laneNumber,
    required this.items,
    this.thankYouMessage,
    this.logoBase64,
    this.transactionDate,
  });
}

/// Universal label data class for all printer brands  
class PrinterLabelData {
  final String productName;
  final String price;
  final String colorSize;
  final String barcode;
  final int quantity;

  PrinterLabelData({
    required this.productName,
    required this.price,
    required this.colorSize,
    required this.barcode,
    this.quantity = 1,
  });
}

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
  static Future<bool> printReceipt(String brand, PrinterReceiptData receiptData) async {
    switch (brand.toLowerCase()) {
      case 'epson':
        return _printEpsonReceipt(receiptData);
      case 'star':
        throw UnimplementedError('Star receipt printing not implemented yet');
      case 'zebra':
        throw UnimplementedError('Zebra receipt printing not implemented yet');
      default:
        throw ArgumentError('Unsupported brand: $brand');
    }
  }

  static Future<bool> _printEpsonReceipt(PrinterReceiptData receiptData) async {
    try {
      // Build Epson commands from universal receipt data
      final commands = _buildEpsonReceiptCommands(receiptData);
      
      if (commands.isEmpty) {
        print('Epson receipt has no content');
        return false;
      }

      final printJob = EpsonPrintJob(commands: commands);
      await EpsonPrinter.printReceipt(printJob);
      
      return true;
    } catch (e) {
      print('Epson receipt print failed: $e');
      return false;
    }
  }

  static List<EpsonPrintCommand> _buildEpsonReceiptCommands(PrinterReceiptData receiptData) {
    final List<EpsonPrintCommand> commands = [];
    
    // Center alignment for header
    commands.add(EpsonPrintCommand(
      type: EpsonCommandType.text,
      parameters: {'align': 'center'}
    ));
    
    // Store name (bold, larger)
    commands.add(EpsonPrintCommand(
      type: EpsonCommandType.textStyle,
      parameters: {'bold': 'true'}
    ));
    commands.add(EpsonPrintCommand(
      type: EpsonCommandType.text,
      parameters: {'data': '${receiptData.storeName}\n'}
    ));
    
    // Reset to normal style
    commands.add(EpsonPrintCommand(
      type: EpsonCommandType.textStyle,
      parameters: {'bold': 'false'}
    ));
    
    // Store address
    commands.add(EpsonPrintCommand(
      type: EpsonCommandType.text,
      parameters: {'data': '${receiptData.storeAddress}\n'}
    ));
    
    if (receiptData.storePhone != null) {
      commands.add(EpsonPrintCommand(
        type: EpsonCommandType.text,
        parameters: {'data': '${receiptData.storePhone}\n'}
      ));
    }
    
    commands.add(EpsonPrintCommand(
      type: EpsonCommandType.text,
      parameters: {'data': '\n'}
    ));
    
    // Left alignment for receipt details
    commands.add(EpsonPrintCommand(
      type: EpsonCommandType.text,
      parameters: {'align': 'left'}
    ));
    
    // Receipt details
    commands.add(EpsonPrintCommand(
      type: EpsonCommandType.text,
      parameters: {'data': 'Date: ${receiptData.date} ${receiptData.time}\n'}
    ));
    
    if (receiptData.receiptNumber != null) {
      commands.add(EpsonPrintCommand(
        type: EpsonCommandType.text,
        parameters: {'data': 'Receipt: ${receiptData.receiptNumber}\n'}
      ));
    }
    
    if (receiptData.cashierName != null) {
      commands.add(EpsonPrintCommand(
        type: EpsonCommandType.text,
        parameters: {'data': 'Cashier: ${receiptData.cashierName}\n'}
      ));
    }
    
    if (receiptData.laneNumber != null) {
      commands.add(EpsonPrintCommand(
        type: EpsonCommandType.text,
        parameters: {'data': 'Lane: ${receiptData.laneNumber}\n'}
      ));
    }
    
    commands.add(EpsonPrintCommand(
      type: EpsonCommandType.text,
      parameters: {'data': '\n'}
    ));
    
    // Items section
    double total = 0.0;
    for (final item in receiptData.items) {
      commands.add(EpsonPrintCommand(
        type: EpsonCommandType.text,
        parameters: {'data': '${item.quantity}x ${item.itemName}\n'}
      ));
      commands.add(EpsonPrintCommand(
        type: EpsonCommandType.text,
        parameters: {'data': '    \$${item.totalPrice.toStringAsFixed(2)}\n'}
      ));
      total += item.totalPrice;
    }
    
    // Total
    commands.add(EpsonPrintCommand(
      type: EpsonCommandType.text,
      parameters: {'data': '\n'}
    ));
    commands.add(EpsonPrintCommand(
      type: EpsonCommandType.textStyle,
      parameters: {'bold': 'true'}
    ));
    commands.add(EpsonPrintCommand(
      type: EpsonCommandType.text,
      parameters: {'data': 'Total: \$${total.toStringAsFixed(2)}\n'}
    ));
    commands.add(EpsonPrintCommand(
      type: EpsonCommandType.textStyle,
      parameters: {'bold': 'false'}
    ));
    
    // Footer message
    if (receiptData.thankYouMessage != null) {
      commands.add(EpsonPrintCommand(
        type: EpsonCommandType.text,
        parameters: {'data': '\n'}
      ));
      commands.add(EpsonPrintCommand(
        type: EpsonCommandType.text,
        parameters: {'align': 'center'}
      ));
      commands.add(EpsonPrintCommand(
        type: EpsonCommandType.text,
        parameters: {'data': '${receiptData.thankYouMessage}\n'}
      ));
    }
    
    // Cut paper
    commands.add(EpsonPrintCommand(
      type: EpsonCommandType.cut,
      parameters: {}
    ));
    
    return commands;
  }

  /// Print a label using the connected printer of the specified brand
  /// Returns true if print successful
  static Future<bool> printLabel(String brand, Map<String, dynamic> labelData) async {
    throw UnimplementedError('Print label not implemented yet');
  }
}