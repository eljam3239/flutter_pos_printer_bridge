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
        if (maxLeft < 1) return (left + right).substring(0, effectiveCharsPerLine);
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
      final qtyWidth = effectiveCharsPerLine >= 40 ? 4 : 3; // e.g. '99x' for narrow paper
      final priceWidth = effectiveCharsPerLine >= 40 ? 8 : 6; // Shorter price field for narrow paper
      
      final qtyStr = qty.length > (qtyWidth - 1) ? qty.substring(0, qtyWidth - 1) : qty;
      final qtyField = (qtyStr + 'x').padRight(qtyWidth);
      
      // Remaining width for name = total - qtyWidth - priceWidth
      final nameWidth = effectiveCharsPerLine - qtyWidth - priceWidth;
      String nameTrunc = name;
      if (nameTrunc.length > nameWidth) nameTrunc = nameTrunc.substring(0, nameWidth);
      
      // Ensure price has '$' prefix
      final formattedPrice = price.startsWith('\$') ? price : '\$$price';
      final priceField = formattedPrice.padLeft(priceWidth);
      
      return qtyField + nameTrunc.padRight(nameWidth) + priceField;
    }

    // Store title/header
    String title = receiptData.storeName.trim();
    if (title.isNotEmpty) {
      // Use SDK centering like labels instead of manual padding
      cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'align': 'center' }));
      // Wrap title text to respect the selected paper width
      final wrappedTitleLines = wrapText(title, effectiveCharsPerLine);
      for (String line in wrappedTitleLines) {
        cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'data': line + '\n' }));
      }
      // Reset to left alignment after title
      cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'align': 'left' }));
    }

    // Store address
    if (receiptData.storeAddress.trim().isNotEmpty) {
      cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'align': 'center' }));
      // Wrap location text to respect the selected paper width
      final wrappedLocationLines = wrapText(receiptData.storeAddress.trim(), effectiveCharsPerLine);
      for (String line in wrappedLocationLines) {
        cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'data': line + '\n' }));
      }
      cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'align': 'left' }));
    }

    // Centered 'Receipt'
    cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'align': 'center' }));
    cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'data': '\nReceipt\n' }));
    cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'align': 'left' }));

    // Date Time (left) vs Cashier (right) - center the whole line using SDK
    final dateTime = '${receiptData.date.trim()} ${receiptData.time.trim()}';
    final cashierStr = receiptData.cashierName != null 
        ? 'Cashier: ${receiptData.cashierName!.trim()}' 
        : 'Cashier: N/A';
    cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'align': 'center' }));
    cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'data': leftRight(dateTime, cashierStr) + '\n' }));
    cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'align': 'left' }));

    // Receipt # vs Lane - center the whole line using SDK
    final recLine = receiptData.receiptNumber != null 
        ? 'Receipt: ${receiptData.receiptNumber!.trim()}' 
        : 'Receipt: N/A';
    final laneLine = receiptData.laneNumber != null 
        ? 'Lane: ${receiptData.laneNumber!.trim()}' 
        : 'Lane: N/A';
    cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'align': 'center' }));
    cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'data': leftRight(recLine, laneLine) + '\n' }));
    cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'align': 'left' }));

    // Blank line
    cmds.add(EpsonPrintCommand(type: EpsonCommandType.feed, parameters: { 'line': 1 }));

    // Horizontal line - center using SDK
    cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'align': 'center' }));
    cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'data': horizontalLine() + '\n' }));
    cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'align': 'left' }));

    // Items - center each item line using SDK
    for (final item in receiptData.items) {
      cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'align': 'center' }));
      cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 
        'data': qtyNamePrice(item.quantity.toString(), item.itemName, item.totalPrice.toStringAsFixed(2)) + '\n' 
      }));
      cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'align': 'left' }));
    }

    // Second horizontal line - center using SDK
    cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'align': 'center' }));
    cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'data': horizontalLine() + '\n' }));
    cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'align': 'left' }));

    // Footer message
    if (receiptData.thankYouMessage != null && receiptData.thankYouMessage!.trim().isNotEmpty) {
      cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'align': 'center' }));
      // Wrap footer text to respect the selected paper width
      final wrappedFooterLines = wrapText(receiptData.thankYouMessage!.trim(), effectiveCharsPerLine);
      for (String line in wrappedFooterLines) {
        cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'data': line + '\n' }));
      }
      cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'align': 'left' }));
    }

    // End feeds + cut
    cmds.add(EpsonPrintCommand(type: EpsonCommandType.feed, parameters: { 'line': 2 }));
    cmds.add(EpsonPrintCommand(type: EpsonCommandType.cut, parameters: {}));
    return cmds;
  }

  /// Print a label using the connected printer of the specified brand
  /// Returns true if print successful
  static Future<bool> printLabel(String brand, PrinterLabelData labelData) async {
    switch (brand.toLowerCase()) {
      case 'epson':
        return await _printEpsonLabel(labelData);
      case 'star':
        throw UnimplementedError('Star label printing not implemented yet');
      case 'zebra':
        throw UnimplementedError('Zebra label printing not implemented yet');
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

  static List<EpsonPrintCommand> _buildEpsonLabelCommands(PrinterLabelData labelData) {
    final List<EpsonPrintCommand> commands = [];
    
    // Use SDK centering for all elements to match barcode centering
    // Set center alignment for all text elements
    commands.add(EpsonPrintCommand(
      type: EpsonCommandType.text,
      parameters: {'align': 'center'}
    ));
    
    // Set bold style for product name
    commands.add(EpsonPrintCommand(
      type: EpsonCommandType.textStyle,
      parameters: {
        'reverse': 'false',
        'underline': 'false', 
        'bold': 'true',
        'color': '1'
      }
    ));
    
    // Product name (centered at top, bold)
    commands.add(EpsonPrintCommand(
      type: EpsonCommandType.text,
      parameters: {'data': labelData.productName.trim() + '\n'}
    ));
    
    // Reset text style to normal
    commands.add(EpsonPrintCommand(
      type: EpsonCommandType.textStyle,
      parameters: {
        'reverse': 'false',
        'underline': 'false',
        'bold': 'false', 
        'color': '1'
      }
    ));
    
    // Price (centered under product name)
    commands.add(EpsonPrintCommand(
      type: EpsonCommandType.text,
      parameters: {'data': labelData.price.trim() + '\n'}
    ));
    
    // Size/Color (centered under price)
    commands.add(EpsonPrintCommand(
      type: EpsonCommandType.text,
      parameters: {'data': labelData.colorSize.trim() + '\n'}
    ));
    
    // Barcode (center alignment already set)
    commands.add(EpsonPrintCommand(
      type: EpsonCommandType.barcode,
      parameters: {
        'data': labelData.barcode.trim(),
        'type': 'CODE128_AUTO',
        'hri': 'below',
        'width': 2,
        'height': 35,
        'font': 'A',
      }
    ));
    
    // Reset to left alignment after all label content
    commands.add(EpsonPrintCommand(
      type: EpsonCommandType.text,
      parameters: {'align': 'left'}
    ));
    
    commands.add(EpsonPrintCommand(
      type: EpsonCommandType.cut,
      parameters: {}
    ));
    
    return commands;
  }
}