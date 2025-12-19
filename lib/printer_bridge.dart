import 'dart:io';

import 'package:epson_printer/epson_printer.dart';
import 'package:star_printer/star_printer.dart' as star;
import 'package:zebra_printer/zebra_printer.dart';

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

  /// Calculate total from all line items
  double get calculatedTotal {
    return items.fold(0.0, (sum, item) => sum + item.totalPrice);
  }
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
        return _discoverStarPrinters();
      case 'zebra':
        return _discoverZebraPrinters();
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

  static Future<List<Map<String, String>>> _discoverStarPrinters() async {
    try {
      print('Discovering Star printers...');
      final printers = await star.StarPrinter.discoverPrinters();
      print('Star discovery found ${printers.length} printers');
      
      // Convert to hybrid format
      return printers.map((raw) => _parseStarPrinter(raw)).toList();
    } catch (e) {
      print('Star discovery error: $e');
      // Return empty list on error rather than throwing
      return [];
    }
  }

  static Map<String, String> _parseStarPrinter(String raw) {
    // Parse Star format: "LAN:192.168.1.100:TSP654II", "BT:00:11:22:33:44:55:mPOP", etc.
    // Format varies but generally: INTERFACE:ADDRESS:MODEL
    
    final parts = raw.split(':');
    if (parts.length < 2) {
      return {
        'raw': raw,
        'brand': 'star',
        'interface': '',
        'address': raw,
        'model': '',
        'displayName': raw,
      };
    }
    
    final interface = parts[0].toLowerCase();
    final address = parts.length > 1 ? parts[1] : '';
    final model = parts.length > 2 ? parts[2] : '';
    
    // Create user-friendly display name
    String displayName;
    if (model.isNotEmpty) {
      displayName = '$model ($interface: $address)';
    } else if (address.isNotEmpty) {
      displayName = '$address ($interface)';
    } else {
      displayName = raw;
    }
    
    return {
      'raw': raw,
      'brand': 'star',
      'interface': interface, // lan, bt, ble, usb
      'address': address,
      'model': model,
      'displayName': displayName,
    };
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

  static Future<List<Map<String, String>>> _discoverZebraPrinters() async {
    final List<DiscoveredPrinter> allPrinters = [];

    try {
      // Network discovery (works on all platforms)
      try {
        final networkPrinters =
            await ZebraPrinter.discoverNetworkPrintersAuto();
        allPrinters.addAll(networkPrinters);
        print(
          'Zebra network discovery found ${networkPrinters.length} printers',
        );
      } catch (e) {
        print('Zebra network discovery failed: $e');
      }

      // Bluetooth discovery (works on all platforms)
      try {
        final bluetoothPrinters =
            await ZebraPrinter.discoverBluetoothPrinters();
        allPrinters.addAll(bluetoothPrinters);
        print(
          'Zebra Bluetooth discovery found ${bluetoothPrinters.length} printers',
        );
      } catch (e) {
        print('Zebra Bluetooth discovery failed: $e');
      }

      // USB discovery (Android only)
      if (!Platform.isIOS) {
        try {
          final usbPrinters = await ZebraPrinter.discoverUsbPrinters();
          allPrinters.addAll(usbPrinters);
          print('Zebra USB discovery found ${usbPrinters.length} printers');
        } catch (e) {
          print('Zebra USB discovery failed: $e');
        }
      }
    } catch (e) {
      print('Zebra discovery failed: $e');
      rethrow;
    }

    return allPrinters
        .map((discoveredPrinter) => _parseZebraPrinter(discoveredPrinter))
        .toList();
  }

  static Map<String, String> _parseZebraPrinter(DiscoveredPrinter printer) {
    // Convert DiscoveredPrinter to our universal format
    final interface = printer.interfaceType.toLowerCase();
    final address = printer.address;
    final model = printer.friendlyName ?? 'Unknown';

    // Create a raw string similar to Epson format for consistency
    final raw =
        '${printer.interfaceType.toUpperCase()}:${printer.address}:${printer.friendlyName ?? printer.address}';

    return {
      'raw': raw,
      'brand': 'zebra',
      'interface': interface,
      'address': address,
      'model': model,
    };
  }

  /// Connect to a printer using brand, interface type, and connection string
  /// Returns true if connection successful
  static Future<bool> connect(
    String brand,
    String interface,
    String connectionString,
  ) async {
    switch (brand.toLowerCase()) {
      case 'epson':
        return _connectEpsonPrinter(interface, connectionString);
      case 'star':
        return _connectStarPrinter(interface, connectionString);
      case 'zebra':
        return _connectZebraPrinter(interface, connectionString);
      default:
        throw ArgumentError('Unsupported brand: $brand');
    }
  }

  static Future<bool> _connectEpsonPrinter(
    String interface,
    String connectionString,
  ) async {
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

  static Future<bool> _connectStarPrinter(
    String interface,
    String connectionString,
  ) async {
    try {
      // Force disconnect if already connected
      try {
        await star.StarPrinter.disconnect();
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (_) {
        // Ignore disconnect errors
      }

      // Use the interface parameter to determine the connection type
      star.StarInterfaceType interfaceType;
      String identifier = connectionString; // Use connectionString as identifier
      
      // Map interface string to StarInterfaceType enum
      switch (interface.toLowerCase()) {
        case 'lan':
        case 'tcp':
        case 'network':
        case 'wifi':
          interfaceType = star.StarInterfaceType.lan;
          break;
        case 'bt':
        case 'bluetooth':
          interfaceType = star.StarInterfaceType.bluetooth;
          break;
        case 'ble':
        case 'bluetoothle':
        case 'bluetooth_le':
          interfaceType = star.StarInterfaceType.bluetoothLE;
          break;
        case 'usb':
          interfaceType = star.StarInterfaceType.usb;
          break;
        default:
          // Default to LAN if unknown interface
          interfaceType = star.StarInterfaceType.lan;
          break;
      }
      
      print('PrinterBridge: Connecting to Star $interfaceType printer: $identifier');
      
      final settings = star.StarConnectionSettings(
        interfaceType: interfaceType,
        identifier: identifier,
      );
      
      await star.StarPrinter.connect(settings);
      print('PrinterBridge: Star connection successful');
      
      return true;
    } catch (e) {
      print('PrinterBridge: Star connection failed: $e');
      return false;
    }
  }

  static Future<bool> _connectZebraPrinter(
    String interface,
    String connectionString,
  ) async {
    try {
      // Determine interface type for connection
      ZebraInterfaceType interfaceType;
      switch (interface.toLowerCase()) {
        case 'bluetooth':
        case 'bt':
        case 'ble':
          interfaceType = ZebraInterfaceType.bluetooth;
          break;
        case 'usb':
          interfaceType = ZebraInterfaceType.usb;
          break;
        case 'tcp':
        case 'network':
        case 'wifi':
        default:
          interfaceType = ZebraInterfaceType.tcp;
          break;
      }

      final settings = ZebraConnectionSettings(
        interfaceType: interfaceType,
        identifier: connectionString,
        timeout: 15000,
      );

      print(
        'Connecting to Zebra printer: $connectionString via ${interface.toUpperCase()}',
      );
      await ZebraPrinter.connect(settings);
      print('Zebra connection successful');

      // Add small delay to ensure connection is fully established
      await Future.delayed(const Duration(milliseconds: 500));

      return true;
    } catch (e) {
      print('Zebra connection failed: $e');
      return false;
    }
  }

  static Future<bool> _disconnectEpsonPrinter() async {
    try {
      await EpsonPrinter.disconnect();
      return true;
    } catch (e) {
      print('Epson disconnect failed: $e');
      return false;
    }
  }

  static Future<bool> _disconnectStarPrinter() async {
    try {
      await star.StarPrinter.disconnect();
      return true;
    } catch (e) {
      print('Star disconnect failed: $e');
      return false;
    }
  }

  static Future<bool> _disconnectZebraPrinter() async {
    try {
      await ZebraPrinter.disconnect();
      return true;
    } catch (e) {
      print('Zebra disconnect failed: $e');
      return false;
    }
  }

  /// Print a receipt using the connected printer of the specified brand
  /// Returns true if print successful
  static Future<bool> printReceipt(
    String brand,
    PrinterReceiptData receiptData,
  ) async {
    switch (brand.toLowerCase()) {
      case 'epson':
        return _printEpsonReceipt(receiptData);
      case 'star':
        return _printStarReceipt(receiptData);
      case 'zebra':
        return _printZebraReceipt(receiptData);
      default:
        throw ArgumentError('Unsupported brand: $brand');
    }
  }

  /// Disconnect from the connected printer of the specified brand
  /// Returns true if disconnect successful
  static Future<bool> disconnect(String brand) async {
    switch (brand.toLowerCase()) {
      case 'epson':
        return _disconnectEpsonPrinter();
      case 'star':
        return _disconnectStarPrinter();
      case 'zebra':
        return _disconnectZebraPrinter();
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

  static List<EpsonPrintCommand> _buildEpsonReceiptCommands(
    PrinterReceiptData receiptData,
  ) {
    final List<EpsonPrintCommand> cmds = [];

    // Calculate the correct characters per line based on detected paper width
    int effectiveCharsPerLine = 48; // Default to 80mm width

    // Helper functions that use the correct character width
    String horizontalLine() => '-' * effectiveCharsPerLine;

    // Wrap long text to fit within the specified character width
    List<String> wrapText(String text, int maxWidth) {
      text = text.trim();
      if (text.isEmpty) return [];

      final List<String> lines = [];
      final words = text.split(' ');
      String currentLine = '';

      for (String word in words) {
        final testLine = currentLine.isEmpty ? word : '$currentLine $word';
        if (testLine.length <= maxWidth) {
          currentLine = testLine;
        } else {
          if (currentLine.isNotEmpty) {
            lines.add(currentLine);
            currentLine = word;
          } else {
            // Single word longer than maxWidth - just add it
            lines.add(word);
          }
        }
      }

      if (currentLine.isNotEmpty) {
        lines.add(currentLine);
      }

      return lines;
    }

    String leftRight(String left, String right) {
      left = left.trim();
      right = right.trim();
      final space = effectiveCharsPerLine - left.length - right.length;
      if (space < 1) {
        final maxLeft = effectiveCharsPerLine - right.length - 1;
        if (maxLeft < 1)
          return (left + right).substring(0, effectiveCharsPerLine);
        left = left.substring(0, maxLeft);
        return '$left $right';
      }
      return left + ' ' * space + right;
    }

    String qtyNamePrice(String qty, String name, String price) {
      // Layout: qty (3) name (left) price (right) within paper width.
      qty = qty.trim();
      name = name.trim();
      price = price.trim();

      // Adjust field widths for narrower paper
      final qtyWidth = effectiveCharsPerLine >= 40
          ? 4
          : 3; // e.g. '99x' for narrow paper
      final priceWidth = effectiveCharsPerLine >= 40
          ? 8
          : 6; // Shorter price field for narrow paper

      final qtyStr = qty.length > (qtyWidth - 1)
          ? qty.substring(0, qtyWidth - 1)
          : qty;
      final qtyField = (qtyStr + 'x').padRight(qtyWidth);

      // Remaining width for name = total - qtyWidth - priceWidth
      final nameWidth = effectiveCharsPerLine - qtyWidth - priceWidth;
      String nameTrunc = name;
      if (nameTrunc.length > nameWidth)
        nameTrunc = nameTrunc.substring(0, nameWidth);

      // Ensure price has '$' prefix
      final formattedPrice = price.startsWith('\$') ? price : '\$$price';
      final priceField = formattedPrice.padLeft(priceWidth);

      return qtyField + nameTrunc.padRight(nameWidth) + priceField;
    }

    // Store title/header
    String title = receiptData.storeName.trim();
    if (title.isNotEmpty) {
      // Use SDK centering like labels instead of manual padding
      cmds.add(
        EpsonPrintCommand(
          type: EpsonCommandType.text,
          parameters: {'align': 'center'},
        ),
      );
      // Wrap title text to respect the selected paper width
      final wrappedTitleLines = wrapText(title, effectiveCharsPerLine);
      for (String line in wrappedTitleLines) {
        cmds.add(
          EpsonPrintCommand(
            type: EpsonCommandType.text,
            parameters: {'data': line + '\n'},
          ),
        );
      }
      // Reset to left alignment after title
      cmds.add(
        EpsonPrintCommand(
          type: EpsonCommandType.text,
          parameters: {'align': 'left'},
        ),
      );
    }

    // Store address
    if (receiptData.storeAddress.trim().isNotEmpty) {
      cmds.add(
        EpsonPrintCommand(
          type: EpsonCommandType.text,
          parameters: {'align': 'center'},
        ),
      );
      // Wrap location text to respect the selected paper width
      final wrappedLocationLines = wrapText(
        receiptData.storeAddress.trim(),
        effectiveCharsPerLine,
      );
      for (String line in wrappedLocationLines) {
        cmds.add(
          EpsonPrintCommand(
            type: EpsonCommandType.text,
            parameters: {'data': line + '\n'},
          ),
        );
      }
      cmds.add(
        EpsonPrintCommand(
          type: EpsonCommandType.text,
          parameters: {'align': 'left'},
        ),
      );
    }

    // Centered 'Receipt'
    cmds.add(
      EpsonPrintCommand(
        type: EpsonCommandType.text,
        parameters: {'align': 'center'},
      ),
    );
    cmds.add(
      EpsonPrintCommand(
        type: EpsonCommandType.text,
        parameters: {'data': '\nReceipt\n'},
      ),
    );
    cmds.add(
      EpsonPrintCommand(
        type: EpsonCommandType.text,
        parameters: {'align': 'left'},
      ),
    );

    // Date Time (left) vs Cashier (right) - center the whole line using SDK
    final dateTime = '${receiptData.date.trim()} ${receiptData.time.trim()}';
    final cashierStr = receiptData.cashierName != null
        ? 'Cashier: ${receiptData.cashierName!.trim()}'
        : 'Cashier: N/A';
    cmds.add(
      EpsonPrintCommand(
        type: EpsonCommandType.text,
        parameters: {'align': 'center'},
      ),
    );
    cmds.add(
      EpsonPrintCommand(
        type: EpsonCommandType.text,
        parameters: {'data': leftRight(dateTime, cashierStr) + '\n'},
      ),
    );
    cmds.add(
      EpsonPrintCommand(
        type: EpsonCommandType.text,
        parameters: {'align': 'left'},
      ),
    );

    // Receipt # vs Lane - center the whole line using SDK
    final recLine = receiptData.receiptNumber != null
        ? 'Receipt: ${receiptData.receiptNumber!.trim()}'
        : 'Receipt: N/A';
    final laneLine = receiptData.laneNumber != null
        ? 'Lane: ${receiptData.laneNumber!.trim()}'
        : 'Lane: N/A';
    cmds.add(
      EpsonPrintCommand(
        type: EpsonCommandType.text,
        parameters: {'align': 'center'},
      ),
    );
    cmds.add(
      EpsonPrintCommand(
        type: EpsonCommandType.text,
        parameters: {'data': leftRight(recLine, laneLine) + '\n'},
      ),
    );
    cmds.add(
      EpsonPrintCommand(
        type: EpsonCommandType.text,
        parameters: {'align': 'left'},
      ),
    );

    // Blank line
    cmds.add(
      EpsonPrintCommand(type: EpsonCommandType.feed, parameters: {'line': 1}),
    );

    // Horizontal line - center using SDK
    cmds.add(
      EpsonPrintCommand(
        type: EpsonCommandType.text,
        parameters: {'align': 'center'},
      ),
    );
    cmds.add(
      EpsonPrintCommand(
        type: EpsonCommandType.text,
        parameters: {'data': horizontalLine() + '\n'},
      ),
    );
    cmds.add(
      EpsonPrintCommand(
        type: EpsonCommandType.text,
        parameters: {'align': 'left'},
      ),
    );

    // Items - center each item line using SDK
    for (final item in receiptData.items) {
      cmds.add(
        EpsonPrintCommand(
          type: EpsonCommandType.text,
          parameters: {'align': 'center'},
        ),
      );
      cmds.add(
        EpsonPrintCommand(
          type: EpsonCommandType.text,
          parameters: {
            'data':
                qtyNamePrice(
                  item.quantity.toString(),
                  item.itemName,
                  item.totalPrice.toStringAsFixed(2),
                ) +
                '\n',
          },
        ),
      );
      cmds.add(
        EpsonPrintCommand(
          type: EpsonCommandType.text,
          parameters: {'align': 'left'},
        ),
      );
    }

    // Second horizontal line - center using SDK
    cmds.add(
      EpsonPrintCommand(
        type: EpsonCommandType.text,
        parameters: {'align': 'center'},
      ),
    );
    cmds.add(
      EpsonPrintCommand(
        type: EpsonCommandType.text,
        parameters: {'data': horizontalLine() + '\n'},
      ),
    );
    cmds.add(
      EpsonPrintCommand(
        type: EpsonCommandType.text,
        parameters: {'align': 'left'},
      ),
    );

    // Footer message
    if (receiptData.thankYouMessage != null &&
        receiptData.thankYouMessage!.trim().isNotEmpty) {
      cmds.add(
        EpsonPrintCommand(
          type: EpsonCommandType.text,
          parameters: {'align': 'center'},
        ),
      );
      // Wrap footer text to respect the selected paper width
      final wrappedFooterLines = wrapText(
        receiptData.thankYouMessage!.trim(),
        effectiveCharsPerLine,
      );
      for (String line in wrappedFooterLines) {
        cmds.add(
          EpsonPrintCommand(
            type: EpsonCommandType.text,
            parameters: {'data': line + '\n'},
          ),
        );
      }
      cmds.add(
        EpsonPrintCommand(
          type: EpsonCommandType.text,
          parameters: {'align': 'left'},
        ),
      );
    }

    // End feeds + cut
    cmds.add(
      EpsonPrintCommand(type: EpsonCommandType.feed, parameters: {'line': 2}),
    );
    cmds.add(EpsonPrintCommand(type: EpsonCommandType.cut, parameters: {}));
    return cmds;
  }

  /// Print a label using the connected printer of the specified brand
  /// Returns true if print successful
  static Future<bool> printLabel(
    String brand,
    PrinterLabelData labelData,
  ) async {
    switch (brand.toLowerCase()) {
      case 'epson':
        return await _printEpsonLabel(labelData);
      case 'star':
        throw UnimplementedError('Star label printing not implemented yet');
      case 'zebra':
        return await _printZebraLabel(labelData);
      default:
        throw ArgumentError('Unsupported printer brand: $brand');
    }
  }

  static Future<bool> _printEpsonLabel(PrinterLabelData labelData) async {
    try {
      final commands = _buildEpsonLabelCommands(labelData);
      final printJob = EpsonPrintJob(commands: commands);

      // Print multiple labels based on quantity setting
      for (int i = 0; i < labelData.quantity; i++) {
        await EpsonPrinter.printReceipt(printJob);

        // Small delay between prints to avoid overwhelming the printer
        if (i < labelData.quantity - 1) {
          await Future.delayed(const Duration(milliseconds: 200));
        }
      }

      return true;
    } catch (e) {
      print('Epson label print failed: $e');
      return false;
    }
  }

  static List<EpsonPrintCommand> _buildEpsonLabelCommands(
    PrinterLabelData labelData,
  ) {
    final List<EpsonPrintCommand> commands = [];

    // Use SDK centering for all elements to match barcode centering
    // Set center alignment for all text elements
    commands.add(
      EpsonPrintCommand(
        type: EpsonCommandType.text,
        parameters: {'align': 'center'},
      ),
    );

    // Set bold style for product name
    commands.add(
      EpsonPrintCommand(
        type: EpsonCommandType.textStyle,
        parameters: {
          'reverse': 'false',
          'underline': 'false',
          'bold': 'true',
          'color': '1',
        },
      ),
    );

    // Product name (centered at top, bold)
    commands.add(
      EpsonPrintCommand(
        type: EpsonCommandType.text,
        parameters: {'data': labelData.productName.trim() + '\n'},
      ),
    );

    // Reset text style to normal
    commands.add(
      EpsonPrintCommand(
        type: EpsonCommandType.textStyle,
        parameters: {
          'reverse': 'false',
          'underline': 'false',
          'bold': 'false',
          'color': '1',
        },
      ),
    );

    // Price (centered under product name)
    commands.add(
      EpsonPrintCommand(
        type: EpsonCommandType.text,
        parameters: {'data': labelData.price.trim() + '\n'},
      ),
    );

    // Size/Color (centered under price)
    commands.add(
      EpsonPrintCommand(
        type: EpsonCommandType.text,
        parameters: {'data': labelData.colorSize.trim() + '\n'},
      ),
    );

    // Barcode (center alignment already set)
    commands.add(
      EpsonPrintCommand(
        type: EpsonCommandType.barcode,
        parameters: {
          'data': labelData.barcode.trim(),
          'type': 'CODE128_AUTO',
          'hri': 'below',
          'width': 2,
          'height': 35,
          'font': 'A',
        },
      ),
    );

    // Reset to left alignment after all label content
    commands.add(
      EpsonPrintCommand(
        type: EpsonCommandType.text,
        parameters: {'align': 'left'},
      ),
    );

    commands.add(EpsonPrintCommand(type: EpsonCommandType.cut, parameters: {}));

    return commands;
  }

  static Future<bool> _printZebraLabel(PrinterLabelData labelData) async {
    try {
      // Get actual printer dimensions
      Map<String, dynamic> dimensions;
      try {
        print('Fetching Zebra printer dimensions for label...');
        dimensions = await ZebraPrinter.getPrinterDimensions();
        print('Raw dimensions received: $dimensions');
      } catch (e) {
        print('Failed to get dimensions, using defaults: $e');
        dimensions = {
          'printWidthInDots': 386, // ZD410 default
          'labelLengthInDots': 212, // common label height
          'dpi': 203, // standard Zebra DPI
        };
      }

      final width = dimensions['printWidthInDots'] ?? 386;
      final height = dimensions['labelLengthInDots'] ?? 212;
      final dpi = dimensions['dpi'] ?? 203;

      // Validate dimensions and retry if needed
      if (width < 100 || height < 100) {
        print('Dimensions seem invalid, retrying...');
        await Future.delayed(const Duration(milliseconds: 300));
        try {
          final retryDimensions = await ZebraPrinter.getPrinterDimensions();
          print('Retry dimensions: $retryDimensions');
          final retryWidth = retryDimensions['printWidthInDots'] ?? 386;
          final retryHeight = retryDimensions['labelLengthInDots'] ?? 212;
          final retryDpi = retryDimensions['dpi'] ?? 203;

          print(
            'Using Zebra label dimensions (retry): ${retryWidth}x${retryHeight} @ ${retryDpi}dpi',
          );
          final labelZpl = _generateZebraLabelZPL(
            retryWidth,
            retryHeight,
            retryDpi,
            labelData,
          );

          // Print labels based on quantity
          for (int i = 0; i < labelData.quantity; i++) {
            await ZebraPrinter.sendCommands(
              labelZpl,
              language: ZebraPrintLanguage.zpl,
            );
            if (i < labelData.quantity - 1) {
              await Future.delayed(const Duration(milliseconds: 100));
            }
          }
        } catch (retryError) {
          print('Retry failed, using defaults: $retryError');
          // Fallback to defaults
          final labelZpl = _generateZebraLabelZPL(386, 212, 203, labelData);
          for (int i = 0; i < labelData.quantity; i++) {
            await ZebraPrinter.sendCommands(
              labelZpl,
              language: ZebraPrintLanguage.zpl,
            );
            if (i < labelData.quantity - 1) {
              await Future.delayed(const Duration(milliseconds: 100));
            }
          }
        }
      } else {
        print('Using Zebra label dimensions: ${width}x${height} @ ${dpi}dpi');
        final labelZpl = _generateZebraLabelZPL(width, height, dpi, labelData);

        // Print labels based on quantity
        for (int i = 0; i < labelData.quantity; i++) {
          await ZebraPrinter.sendCommands(
            labelZpl,
            language: ZebraPrintLanguage.zpl,
          );
          if (i < labelData.quantity - 1) {
            await Future.delayed(const Duration(milliseconds: 100));
          }
        }
      }

      return true;
    } catch (e) {
      print('Zebra label print failed: $e');
      return false;
    }
  }

  static Future<bool> _printStarReceipt(PrinterReceiptData receiptData) async {
    try {
      // Calculate printable area based on paper width (default to 58mm)
      // This matches the logic in main.dart for Star printers
      double printableAreaMm = 48.0; // Default for 58mm paper
      
      // Paper width mapping: 38mm->34.5mm, 58mm->48mm, 80mm->72mm
      // For now, we'll use the 58mm default but this could be configurable
      
      print('Star receipt - using printableAreaMm: $printableAreaMm');
      
      // Build structured layout settings to be interpreted by native layers
      // This follows the same pattern as main.dart _printStarReceipt()
      final layoutSettings = {
        'layout': {
          'header': {
            'title': receiptData.storeName,
            'align': 'center',
            'fontSize': 32, // Default header font size from main.dart
            'spacingLines': 1,
          },
          'details': {
            'locationText': receiptData.storeAddress,
            'date': receiptData.date,
            'time': receiptData.time,
            'cashier': receiptData.cashierName ?? '',
            'receiptNum': receiptData.receiptNumber ?? '',
            'lane': receiptData.laneNumber ?? '',
            'footer': receiptData.thankYouMessage ?? 'Thank you for your business!',
            'printableAreaMm': printableAreaMm,
          },
          'items': receiptData.items.map((item) => {
            'quantity': item.quantity.toString(),
            'name': item.itemName,
            'price': item.unitPrice.toStringAsFixed(2),
          }).toList(),
          'image': receiptData.logoBase64 == null
              ? null
              : {
                  'base64': receiptData.logoBase64,
                  'mime': 'image/png',
                  'align': 'center',
                  'width': 200, // Default image width from main.dart
                  'spacingLines': 1,
                },
        },
      };

      final printJob = star.PrintJob(
        content: '',
        settings: layoutSettings,
      );
      
      print('Sending Star receipt to printer...');
      await star.StarPrinter.printReceipt(printJob);
      
      print('Star receipt completed successfully');
      return true;
    } catch (e) {
      print('Star receipt print failed: $e');
      return false;
    }
  }

  static Future<bool> _printZebraReceipt(PrinterReceiptData receiptData) async {
    try {
      // Get actual printer dimensions
      Map<String, dynamic> dimensions;
      try {
        print('Fetching Zebra printer dimensions for receipt...');
        dimensions = await ZebraPrinter.getPrinterDimensions();
        print('Raw dimensions received: $dimensions');
      } catch (e) {
        print('Failed to get dimensions, using defaults: $e');
        dimensions = {
          'printWidthInDots': 386, // ZD410 default
          'labelLengthInDots': 600, // longer for receipts
          'dpi': 203, // standard Zebra DPI
        };
      }

      final width = dimensions['printWidthInDots'] ?? 386;
      final height =
          dimensions['labelLengthInDots'] ??
          600; // Use larger default for receipts
      final dpi = dimensions['dpi'] ?? 203;

      // Validate dimensions and retry if needed
      if (width < 100 || height < 100) {
        print('Dimensions seem invalid, retrying...');
        await Future.delayed(const Duration(milliseconds: 300));
        try {
          final retryDimensions = await ZebraPrinter.getPrinterDimensions();
          print('Retry dimensions: $retryDimensions');
          final retryWidth = retryDimensions['printWidthInDots'] ?? 386;
          final retryHeight = retryDimensions['labelLengthInDots'] ?? 600;
          final retryDpi = retryDimensions['dpi'] ?? 203;

          print(
            'Using Zebra receipt dimensions (retry): ${retryWidth}x${retryHeight} @ ${retryDpi}dpi',
          );
          final receiptZpl = _generateZebraReceiptZPL(
            retryWidth,
            retryHeight,
            retryDpi,
            receiptData,
          );
          await ZebraPrinter.sendCommands(
            receiptZpl,
            language: ZebraPrintLanguage.zpl,
          );
        } catch (retryError) {
          print('Retry failed, using defaults: $retryError');
          // Fallback to defaults
          final receiptZpl = _generateZebraReceiptZPL(
            386,
            600,
            203,
            receiptData,
          );
          await ZebraPrinter.sendCommands(
            receiptZpl,
            language: ZebraPrintLanguage.zpl,
          );
        }
      } else {
        print('Using Zebra receipt dimensions: ${width}x${height} @ ${dpi}dpi');
        final receiptZpl = _generateZebraReceiptZPL(
          width,
          height,
          dpi,
          receiptData,
        );
        await ZebraPrinter.sendCommands(
          receiptZpl,
          language: ZebraPrintLanguage.zpl,
        );
      }

      return true;
    } catch (e) {
      print('Zebra receipt print failed: $e');
      return false;
    }
  }

  /// Generate Zebra ZPL commands for receipt printing
  /// Based on the _generateZebraReceiptZPL method from main.dart
  static String _generateZebraReceiptZPL(
    int width,
    int height,
    int dpi,
    PrinterReceiptData receiptData,
  ) {
    // Format date and time
    final now = receiptData.transactionDate ?? DateTime.now();
    final formattedDate =
        "${_getWeekday(now.weekday)} ${_getMonth(now.month)} ${now.day} ${now.hour}:${now.minute.toString().padLeft(2, '0')} ${now.hour >= 12 ? 'PM' : 'AM'}";

    // Helper function to get character width in dots based on font size and DPI
    int getCharWidthInDots(int fontSize, int dpi) {
      if (fontSize <= 25) {
        return 10; // For smaller fonts like size 25
      } else if (fontSize <= 30) {
        return 12; // For medium fonts like size 30
      } else if (fontSize <= 38) {
        return 20; // For medium fonts like size 38
      } else if (fontSize <= 47) {
        return 24; // For larger fonts like size 47
      } else {
        return (fontSize * 0.5)
            .round(); // For even larger fonts, scale proportionally
      }
    }

    // Calculate centered positions for store name and address
    int storeNameCharWidth = getCharWidthInDots(47, dpi);
    int storeAddressCharWidth = getCharWidthInDots(27, dpi);

    int estimatedStoreNameWidth =
        receiptData.storeName.length * storeNameCharWidth;
    int estimatedStoreAddressWidth =
        receiptData.storeAddress.length * storeAddressCharWidth;

    int storeNameX = (width - estimatedStoreNameWidth) ~/ 2;
    int storeAddressX = (width - estimatedStoreAddressWidth) ~/ 2;

    // Ensure positions don't go negative
    storeNameX = storeNameX.clamp(0, width - estimatedStoreNameWidth);
    storeAddressX = storeAddressX.clamp(0, width - estimatedStoreAddressWidth);

    print(
      '[PrinterBridge] Receipt positioning - Store Name: ($storeNameX,64), Store Address: ($storeAddressX,388)',
    );

    // Build ZPL string dynamically using actual form data with calculated positions
    String receiptZpl =
        '''
^XA
^CF0,47
^FO$storeNameX,64
^FD${receiptData.storeName}^FS
^CF0,27
^FO$storeAddressX,388
^FD${receiptData.storeAddress}^FS''';

    // Add phone if provided (centered)
    if (receiptData.storePhone != null && receiptData.storePhone!.isNotEmpty) {
      int storePhoneCharWidth = getCharWidthInDots(25, dpi);
      int estimatedStorePhoneWidth =
          receiptData.storePhone!.length * storePhoneCharWidth;
      int storePhoneX = (width - estimatedStorePhoneWidth) ~/ 2;
      storePhoneX = storePhoneX.clamp(0, width - estimatedStorePhoneWidth);

      receiptZpl +=
          '''
^CF0,25
^FO$storePhoneX,420
^FD${receiptData.storePhone}^FS''';
    }

    receiptZpl += '''
^CF0,30
^FO20,478
^FD$formattedDate^FS''';

    // Add cashier if provided
    if (receiptData.cashierName != null &&
        receiptData.cashierName!.isNotEmpty) {
      // Position cashier name to avoid cutoff - use right-aligned positioning
      String cashierText = "Cashier: ${receiptData.cashierName}";
      int cashierCharWidth = getCharWidthInDots(30, dpi);
      int estimatedCashierWidth = cashierText.length * cashierCharWidth;
      int cashierX =
          (width - estimatedCashierWidth - 20); // 20 dot right margin
      cashierX = cashierX.clamp(
        20,
        width - estimatedCashierWidth,
      ); // Ensure minimum left margin

      receiptZpl +=
          '''
^CF0,30
^FO$cashierX,478
^FD$cashierText^FS''';
    }

    // Add lane if provided
    if (receiptData.laneNumber != null && receiptData.laneNumber!.isNotEmpty) {
      receiptZpl += '''
^CF0,30
^FO470,526
^FDLane: ${receiptData.laneNumber}^FS''';
    }

    // Add receipt number if provided
    if (receiptData.receiptNumber != null &&
        receiptData.receiptNumber!.isNotEmpty) {
      receiptZpl += '''
^CF0,30
^FO20,530
^FDReceipt No: ${receiptData.receiptNumber}^FS''';
    }

    // Add logo (keeping the existing logo from main.dart)
    receiptZpl += '''
^FO200,132
^GFA,7200,7200,30,!::::::::::::::::::::::::::::::::::::::::::::::gVF03!gTFCJ0!gTFL0!XFCH0RF8L03!:WFEJ07OFEM01!WFK01OFCN0!VFCL03NFO01!VF8L01MFEP0!UFCN0MFCP07!:UF8N07LF8I01HFJ07!UFO03LFI01IFCI03!UFI03HFJ0LFI07IFK0!TFEI0IFJ07JFCI0IFEK0!TFCH03HFEJ07JFCH03IFEK07!:TFCH0IFEJ03JF8H07IFEH08H07!TFH01IFE02H03JF8H0JFE03CH07!TFH03JF03H01JFI0KF03EH03!TFH03JFCFC01JFH01MFEH03!SFEH07LFC01JFH01MFEH03!:SFEH07LFCH0JFH01NFH01!SFEH07LFEH0IFEH03NFH01!SFEH0MFEH0IFEH03NFH01!:::SFEH0MFEH0HF9EH03NFH01!SFEH0MFEH0FC0EH03NFH01!SFEH0MFEH0FH0EH03NFH01!SFEH07LFEH0EH0EH03NFH01!SFEH07LFC01CH03H01NFH01!:SFEH07LFCK03H01MFEH03!TFH03LFL01I0MFEH03!TFH03LFL01I0MFCH03!TFH01KFEL018H07LFCH07!TFCH0KFCM08H03LF8H07!:TFCH03JF8M0CH03LFI07!TFEI0IFCN04I0LF8H0!UFH03JFN07H03LFE03!UF81KFEM0380NFC3!UF87LFM0381OF7!:gIFN0C3!gIFN07!gHFEN03!gHFCN01!gHFCO0!:gHFCO03!gHF8O01!gHF8P07!gHF8P03!gHF8Q07!:gHF8R0!gHFES0!gHFES03!gIFT07!gIFCS0!:gIFER03!gJFR07!gJFQ01!gJF8P03!gJFCO01!:gKF8N07!gKFCM03!gKFEM0!gLFCK03!gMFJ07!:gNFH0!!:::::::::::::gFH0!XFCK07!:WFCM01!VFEP0!VFR0!UF8R01!TFET01!:TFCU07!SFEW0!SFCW01!SFY03!RFCg0!:RF8g03!RFgH07!QFEgH01!QFCgI03!QFgJ01!:PFEgK07XFC!PFCgL0XF0!PFCgL07VF80!MFgP01UFCH0!LFgR0UFCH0!:KFC03FCgN01UFC0!KF03HFCgO0UFC0!JFE0IF8gO07TFC0!JF81IFgR0SFC0!JF83IFgS03QFC0!:JF0IFEgT01PFC0!IFC1IFCgU03OFC0!IF81IFCgV07NFC0!IF83IFgX0NFC0!IF03IFgX03MFC0!:IF07HFEgX01MFC0!IF07HFEgY03LFC0!HFE07HFEh0LFC0!HFE07HFEh07KFC0!HFE07HFEhG07JFC0!:HFE07HFEhH03IFC0!HFC0IFEhH01IFC0!HFC0JFhI0IFC0!HFC07IFhI07HFC0!HFC07IFChH07HFC0!:HFC07IFEhH07HFC0!HFC07JFU078gK03HFC0!HFC07JF8T07gL03HFC0!HFE07KFQ07E04gM0HFC0!HFE07KFCN01HFE04gM07FC0!:HFE03LFEM0IFEgO03FC0!HFE03NFE07FE0IFEgO01FC0!IF03NFE0HFE0IFEgO01FC0!IF01NFE0HFE0IFEgP0FC0!IF80NFC1HFE0IFEgP03C0!:IF80NFC1HFE0IFEgP01C0!IFC03MF83HFE0IFEgQ0C0!IFC01MF8IFE0IFEgQ0C0!JFH0MF0IFE07HFEgQ040!JF807KFC1IFE07HFEgQ040!:JFC03KF83IFE07HFCgS0!JFEH0KF07JF03HF8gS0!KFH03IFC3KFH0HFgT03!JFCI03FC07KF8gX0!JF8L01LFCI0CgT03HF:JF83CI01NF8078gO03E3!JF1HF8I0QF8gK07!JF3HFEJ03OF8gH07!JF3IFCK0NF8Y07!IFC7JFM0KF8W03!:JF7JFCgL03!PFgJ07!PFCgK0!QFgM0!QFEgN07RFC!:SFK07HF8gG0OFC0!gNFCgJ03!gRFg07!gTF8V0!gVFCQ03!:!:::::::^FS
^FO44,574^GB554,1,2,B,0^FS''';

    // Add line items dynamically
    int yPosition = 612;
    for (var item in receiptData.items) {
      receiptZpl +=
          '''
^CF0,30
^FO56,$yPosition
^FD${item.quantity} x ${item.itemName}^FS
^CF0,30
^FO470,$yPosition
^FD\$${item.unitPrice.toStringAsFixed(2)}^FS''';
      yPosition += 56; // Move down for next item
    }

    // Calculate positions for bottom elements after line items
    int bottomLineY = yPosition + 20; // Add some spacing after last item
    int totalY = bottomLineY + 22; // Add spacing after bottom line
    int thankYouY = totalY + 54; // Add spacing after total

    // Calculate minimum required height for the receipt
    int minRequiredHeight = thankYouY + 60; // Add bottom margin

    // Use the larger of the detected height or minimum required height
    int actualReceiptHeight = height > minRequiredHeight
        ? height
        : minRequiredHeight;

    print(
      '[PrinterBridge] Receipt layout - Last item Y: $yPosition, Total Y: $totalY, Thank you Y: $thankYouY',
    );
    print(
      '[PrinterBridge] Receipt height - Detected: $height, Required: $minRequiredHeight, Using: $actualReceiptHeight',
    );

    // Add bottom line at dynamic position
    receiptZpl += '''
^FO44,$bottomLineY^GB554,1,2,B,0^FS''';

    // Add total (centered) at dynamic position
    final total = receiptData.calculatedTotal;
    int totalCharWidth = getCharWidthInDots(35, dpi);
    String totalText = "Total: \$${total.toStringAsFixed(2)}";
    int estimatedTotalWidth = totalText.length * totalCharWidth;
    int totalX = (width - estimatedTotalWidth) ~/ 2;
    totalX = totalX.clamp(20, width - estimatedTotalWidth - 20); // Add margins

    receiptZpl +=
        '''
^CF0,35
^FO$totalX,$totalY
^FD$totalText^FS''';

    // Add thank you message (centered) at dynamic position
    String thankYouMsg =
        receiptData.thankYouMessage ?? 'Thank you for shopping with us!';
    int thankYouCharWidth = getCharWidthInDots(30, dpi);
    int estimatedThankYouWidth = thankYouMsg.length * thankYouCharWidth;
    int thankYouX = (width - estimatedThankYouWidth) ~/ 2;
    thankYouX = thankYouX.clamp(0, width - estimatedThankYouWidth);

    receiptZpl +=
        '''
^CF0,30
^FO$thankYouX,$thankYouY
^FD$thankYouMsg^FS''';

    // Set the label length to accommodate the full receipt if needed
    if (actualReceiptHeight > height) {
      receiptZpl =
          '''
^XA
^LL$actualReceiptHeight
''' +
          receiptZpl.substring(4); // Replace ^XA with ^XA^LL command
    }

    receiptZpl += '''
^XZ''';

    return receiptZpl;
  }

  static String _generateZebraLabelZPL(
    int width,
    int height,
    int dpi,
    PrinterLabelData labelData,
  ) {
    // Extract label content from the data object
    final productName = labelData.productName;
    final colorSize = labelData.colorSize;
    final scancode = labelData.barcode;
    final price = labelData.price;

    // Paper details - use actual detected width in dots
    final paperWidthDots = width;

    // Helper function to get character width in dots based on font size and DPI
    int getCharWidthInDots(int fontSize, int dpi) {
      // Based on empirical testing and Zebra font matrices
      // Using a more conservative estimate that matches actual rendering
      if (fontSize <= 25) {
        return 10; // For smaller fonts like size 25
      } else if (fontSize <= 38) {
        return 20; // For medium fonts like size 38
      } else {
        return (fontSize * 0.5)
            .round(); // For larger fonts, scale proportionally
      }
    }

    // Calculate barcode position
    final scancodeLength = scancode.length;
    // Estimate barcode width for Code 128
    // Code 128: Each character takes ~11 modules + start/stop characters
    final totalBarcodeCharacters =
        scancodeLength + 3; // +3 for start, check, and stop characters
    const moduleWidth = 2; // from ^BY2
    final estimatedBarcodeWidth = totalBarcodeCharacters * 11 * moduleWidth;

    // Calculate text widths using font size and DPI
    final productNameCharWidth = getCharWidthInDots(38, dpi);
    final colorSizeCharWidth = getCharWidthInDots(25, dpi);
    final priceCharWidth = getCharWidthInDots(38, dpi);

    final estimatedProductNameWidth = productName.length * productNameCharWidth;
    final estimatedColorSizeWidth = colorSize.length * colorSizeCharWidth;
    final estimatedPriceWidth = price.length * priceCharWidth;

    print(
      'Zebra label font calculations - DPI: $dpi, Font 38: ${productNameCharWidth}dots/char, Font 25: ${colorSizeCharWidth}dots/char',
    );
    print(
      'Zebra label text widths - ProductName: ${estimatedProductNameWidth}dots, ColorSize: ${estimatedColorSizeWidth}dots, Price: ${estimatedPriceWidth}dots',
    );

    // Calculate centered X position for each element
    final barcodeX = ((paperWidthDots - estimatedBarcodeWidth) ~/ 2).clamp(
      0,
      paperWidthDots - estimatedBarcodeWidth,
    );
    final productNameX = (paperWidthDots - estimatedProductNameWidth) ~/ 2;
    final colorSizeX = (paperWidthDots - estimatedColorSizeWidth) ~/ 2;
    final priceX = (paperWidthDots - estimatedPriceWidth) ~/ 2;

    print(
      'Zebra label positions - ProductName: ($productNameX,14), Price: ($priceX,52), ColorSize: ($colorSizeX,90), Barcode: ($barcodeX,124)',
    );

    final labelZpl =
        '''
^XA
^CF0,27
^FO104,150
^FD^FS
^CF0,25
^FO$colorSizeX,90^FD$colorSize^FS
^BY2,3,50
^FO$barcodeX,124^BCN^FD$scancode^FS
^CF0,38
^FO$priceX,52^FD$price^FS
^CF0,38
^FO$productNameX,14^FD$productName^FS
^XZ''';

    return labelZpl;
  }

  /// Helper functions for date formatting (matching main.dart)
  static String _getWeekday(int weekday) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return weekdays[weekday - 1];
  }

  static String _getMonth(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }
}
