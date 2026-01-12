import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:epson_printer/epson_printer.dart';
import 'package:star_printer/star_printer.dart' as star;
import 'package:zebra_printer/zebra_printer.dart';

import 'star_commands.dart';

/// Epson printer configuration
class EpsonConfig {
  String _paperWidth = '80mm'; // Default to 80mm for Epson
  static const List<String> availablePaperWidths = ['58mm', '60mm', '70mm', '76mm', '80mm'];

  /// Get current Epson paper width setting
  String get paperWidth => _paperWidth;

  /// Set Epson paper width (must be one of the available widths)
  void setPaperWidth(String width) {
    if (availablePaperWidths.contains(width)) {
      _paperWidth = width;
      debugPrint('PrinterBridge: Epson paper width set to $width');
    } else {
      debugPrint('PrinterBridge: Invalid paper width $width. Available: $availablePaperWidths');
    }
  }

  /// Get characters per line based on current paper width
  int get charactersPerLine {
    switch (_paperWidth) {
      case '58mm': return 35; // 58mm - more conservative to match real 58mm behavior
      case '60mm': return 34; // 60mm typically 34 chars  
      case '70mm': return 42; // 70mm typically 42 chars
      case '76mm': return 45; // 76mm typically 45 chars
      case '80mm': return 48; // 80mm typically 48 chars
      default: return 48; // Fallback to 80mm
    }
  }
}

/// Star printer configuration
class StarConfig {
  int _paperWidthMm = 58; // Default to 58mm for Star
  static const List<int> availablePaperWidthsMm = [38, 58, 80];

  /// Get current Star paper width setting in mm
  int get paperWidthMm => _paperWidthMm;

  /// Set Star paper width in mm (must be one of the available widths)
  void setPaperWidthMm(int widthMm) {
    if (availablePaperWidthsMm.contains(widthMm)) {
      _paperWidthMm = widthMm;
      debugPrint('PrinterBridge: Star paper width set to ${widthMm}mm');
    } else {
      debugPrint('PrinterBridge: Invalid paper width ${widthMm}mm. Available: $availablePaperWidthsMm');
    }
  }

  /// Get printable area in mm based on current paper width
  double get printableAreaMm {
    switch (_paperWidthMm) {
      case 38: return 34.5; // 38mm paper -> 34.5mm printable
      case 58: return 48.0; // 58mm paper -> 48mm printable  
      case 80: return 72.0; // 80mm paper -> 72mm printable
      default: return 48.0; // Fallback to 58mm
    }
  }

  /// Get layout type based on current paper width
  String get layoutType {
    switch (_paperWidthMm) {
      case 38: return 'vertical_centered'; // Everything vertical and centered for narrow labels
      case 58: return 'mixed'; // Mixed layout with some horizontal elements
      case 80: return 'horizontal'; // Full horizontal layout for wide labels
      default: return 'mixed'; // Fallback to 58mm
    }
  }
}

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

/// Return line item for returns/refunds
class PrinterReturnLineItem {
  final String itemName;
  final int quantity;
  final double unitPrice; // Will be displayed as negative

  PrinterReturnLineItem({
    required this.itemName,
    required this.quantity,
    required this.unitPrice,
  });
  
  /// Calculate total price for this return item (always negative)
  double get totalPrice => -(quantity * unitPrice);
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
  final List<PrinterReturnLineItem>? returnItems;
  final String? thankYouMessage;
  final String? logoBase64;
  final DateTime? transactionDate;
  final String receiptTitle; // New field for customizable receipt title
  final bool isGiftReceipt; // New field for gift receipt mode
  // Financial summary fields
  final double? subtotal;
  final double? discounts;
  final double? hst;
  final double? gst;
  final double? total;
  // Payment methods breakdown
  final Map<String, num>? payments;

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
    this.returnItems,
    this.thankYouMessage,
    this.logoBase64,
    this.transactionDate,
    this.receiptTitle = 'Store Receipt',
    this.isGiftReceipt = false, // Default to regular receipt
    // Financial summary parameters
    this.subtotal,
    this.discounts,
    this.hst,
    this.gst,
    this.total,
    // Payment methods parameter
    this.payments,
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
  /// Epson printer configuration
  static final EpsonConfig epsonConfig = EpsonConfig();
  
  /// Star printer configuration
  static final StarConfig starConfig = StarConfig();
  
  /// Cached Zebra printer dimensions to avoid repeated API calls
  static Map<String, int>? _cachedZebraDimensions;

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
      debugPrint('Epson LAN discovery error: $e');
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
      debugPrint('Epson Bluetooth discovery error: $e');
    }

    // Small delay before USB
    await Future.delayed(const Duration(milliseconds: 500));

    // Stage 3: USB discovery
    try {
      final usbPrinters = await EpsonPrinter.discoverUsbPrinters();
      allPrinters.addAll(usbPrinters);
    } catch (e) {
      debugPrint('Epson USB discovery error: $e');
    }

    // Convert to hybrid format
    return allPrinters.map((raw) => _parseEpsonPrinter(raw)).toList();
  }

  static Future<List<Map<String, String>>> _discoverStarPrinters() async {
    try {
      debugPrint('Discovering Star printers...');
      final printers = await star.StarPrinter.discoverPrinters();
      debugPrint('Star discovery found ${printers.length} printers');
      
      // Convert to hybrid format
      return printers.map((raw) => _parseStarPrinter(raw)).toList();
    } catch (e) {
      debugPrint('Star discovery error: $e');
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
        debugPrint(
          'Zebra network discovery found ${networkPrinters.length} printers',
        );
      } catch (e) {
        debugPrint('Zebra network discovery failed: $e');
      }

      // Bluetooth discovery (works on all platforms)
      try {
        final bluetoothPrinters =
            await ZebraPrinter.discoverBluetoothPrinters();
        allPrinters.addAll(bluetoothPrinters);
        debugPrint(
          'Zebra Bluetooth discovery found ${bluetoothPrinters.length} printers',
        );
      } catch (e) {
        debugPrint('Zebra Bluetooth discovery failed: $e');
      }

      // USB discovery (Android only)
      if (!Platform.isIOS) {
        try {
          final usbPrinters = await ZebraPrinter.discoverUsbPrinters();
          allPrinters.addAll(usbPrinters);
          debugPrint('Zebra USB discovery found ${usbPrinters.length} printers');
        } catch (e) {
          debugPrint('Zebra USB discovery failed: $e');
        }
      }
    } catch (e) {
      debugPrint('Zebra discovery failed: $e');
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
      debugPrint('Epson connection failed: $e');
      return false;
    }
  }

  /// Detect paper width for Epson printers
  /// Returns detected width string (e.g., '58mm', '80mm') or null if detection fails
  /// Also automatically updates EpsonConfig.paperWidth if detection succeeds
  static Future<String?> detectPaperWidth(String brand) async {
    if (brand.toLowerCase() != 'epson') {
      debugPrint('Paper width detection only supported for Epson printers');
      return null;
    }

    try {
      String detectedWidth = await EpsonPrinter.detectPaperWidth();
      debugPrint('PrinterBridge: Detected paper width: $detectedWidth');
      
      // Auto-update the EpsonConfig if detected width is valid
      if (EpsonConfig.availablePaperWidths.contains(detectedWidth)) {
        PrinterBridge.epsonConfig.setPaperWidth(detectedWidth);
        debugPrint('PrinterBridge: Auto-updated paper width setting to $detectedWidth');
      }
      
      return detectedWidth;
    } catch (e) {
      debugPrint('PrinterBridge: Paper width detection failed: $e');
      return null;
    }
  }

  /// Get Zebra printer dimensions (width, height, DPI, etc.)
  /// Returns cached dimensions if available, otherwise fetches fresh data
  /// Only works for Zebra printers - returns null for other brands
  static Future<Map<String, int>?> getZebraDimensions({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedZebraDimensions != null) {
      debugPrint('PrinterBridge: Using cached Zebra dimensions');
      return Map<String, int>.from(_cachedZebraDimensions!);
    }

    try {
      debugPrint('PrinterBridge: Fetching fresh Zebra dimensions...');
      final dimensions = await ZebraPrinter.getPrinterDimensions();
      
      // Cache the dimensions for future use
      _cachedZebraDimensions = Map<String, int>.from(dimensions);
      
      debugPrint('PrinterBridge: Zebra dimensions cached: $_cachedZebraDimensions');
      return Map<String, int>.from(_cachedZebraDimensions!);
    } catch (e) {
      debugPrint('PrinterBridge: Failed to get Zebra dimensions: $e');
      return null;
    }
  }

  /// Set Zebra printer label length in dots
  /// Also clears cached dimensions to force refresh on next access
  /// Only works for Zebra printers
  static Future<bool> setZebraLabelLength(int lengthInDots) async {
    try {
      debugPrint('PrinterBridge: Setting Zebra label length to $lengthInDots dots');
      await ZebraPrinter.setLabelLength(lengthInDots);
      
      // Clear cached dimensions since we changed the label length
      _cachedZebraDimensions = null;
      debugPrint('PrinterBridge: Cleared cached dimensions after label length change');
      
      return true;
    } catch (e) {
      debugPrint('PrinterBridge: Failed to set Zebra label length: $e');
      return false;
    }
  }

  /// Set Zebra printer dimensions using width and height in inches
  /// Automatically converts to dots based on DPI and clears cache
  /// Only works for Zebra printers
  static Future<bool> setZebraDimensions({
    required double widthInches,
    required double heightInches,
    int? dpi,
  }) async {
    try {
      // Get current DPI if not provided
      final currentDimensions = await getZebraDimensions();
      final effectiveDpi = dpi ?? currentDimensions?['dpi'] ?? 203;
      
      // Convert inches to dots
      final widthInDots = (widthInches * effectiveDpi).round();
      final heightInDots = (heightInches * effectiveDpi).round();
      
      debugPrint('PrinterBridge: Setting Zebra dimensions to ${widthInches}" x ${heightInches}" ($widthInDots x $heightInDots dots @ ${effectiveDpi}dpi)');
      
      // Set print width via SGD parameter
      await ZebraPrinter.setSgdParameter('ezpl.print_width', widthInDots.toString());
      
      // Set label length via both methods for maximum compatibility
      await ZebraPrinter.setLabelLength(heightInDots);
      await ZebraPrinter.setSgdParameter('ezpl.label_length_max', heightInches.toString());
      
      // Clear cached dimensions to force refresh
      _cachedZebraDimensions = null;
      debugPrint('PrinterBridge: Zebra dimensions set successfully');
      
      return true;
    } catch (e) {
      debugPrint('PrinterBridge: Failed to set Zebra dimensions: $e');
      return false;
    }
  }

  /// Clear cached Zebra dimensions (useful after printer reconnection)
  static void clearZebraDimensionCache() {
    _cachedZebraDimensions = null;
    debugPrint('PrinterBridge: Zebra dimension cache cleared');
  }

  /// Generate ZPL commands for Zebra receipt printing
  /// This allows generating ZPL separately from printing for caching/reuse
  static String generateZebraReceiptZPL(
    int width,
    int height,
    int dpi,
    PrinterReceiptData receiptData,
  ) {
    return _generateZebraReceiptZPL(width, height, dpi, receiptData);
  }

  /// Generate ZPL commands for Zebra label printing
  /// This allows generating ZPL separately from printing for caching/reuse
  static String generateZebraLabelZPL(
    int width,
    int height,
    int dpi,
    PrinterLabelData labelData,
  ) {
    return _generateZebraLabelZPL(width, height, dpi, labelData);
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
      
      debugPrint('PrinterBridge: Connecting to Star $interfaceType printer: $identifier');
      
      final settings = star.StarConnectionSettings(
        interfaceType: interfaceType,
        identifier: identifier,
      );
      
      await star.StarPrinter.connect(settings);
      debugPrint('PrinterBridge: Star connection successful');
      
      return true;
    } catch (e) {
      debugPrint('PrinterBridge: Star connection failed: $e');
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

      debugPrint(
        'Connecting to Zebra printer: $connectionString via ${interface.toUpperCase()}',
      );
      await ZebraPrinter.connect(settings);
      debugPrint('Zebra connection successful');

      // Clear cached dimensions to ensure fresh data after new connection
      clearZebraDimensionCache();

      // Add small delay to ensure connection is fully established
      await Future.delayed(const Duration(milliseconds: 500));

      return true;
    } catch (e) {
      debugPrint('Zebra connection failed: $e');
      return false;
    }
  }

  static Future<bool> _disconnectEpsonPrinter() async {
    try {
      await EpsonPrinter.disconnect();
      return true;
    } catch (e) {
      debugPrint('Epson disconnect failed: $e');
      return false;
    }
  }

  static Future<bool> _disconnectStarPrinter() async {
    try {
      await star.StarPrinter.disconnect();
      return true;
    } catch (e) {
      debugPrint('Star disconnect failed: $e');
      return false;
    }
  }

  static Future<bool> _disconnectZebraPrinter() async {
    try {
      await ZebraPrinter.disconnect();
      return true;
    } catch (e) {
      debugPrint('Zebra disconnect failed: $e');
      return false;
    }
  }

  /// Print a receipt using the connected printer of the specified brand
  /// Returns true if print successful
  /// For Zebra printers, dimensions parameter (width, height, dpi) is recommended to avoid internal API calls
  static Future<bool> printReceipt(
    String brand,
    PrinterReceiptData receiptData, {
    Map<String, int>? dimensions,
  }) async {
    switch (brand.toLowerCase()) {
      case 'epson':
        return _printEpsonReceipt(receiptData);
      case 'star':
        return _printStarReceipt(receiptData);
      case 'zebra':
        return _printZebraReceipt(receiptData, dimensions);
      default:
        throw ArgumentError('Unsupported brand: $brand');
    }
  }

  /// Open cash drawer for the specified brand
  /// Returns true if successful
  static Future<bool> openCashDrawer(String brand) async {
    switch (brand.toLowerCase()) {
      case 'epson':
        return _openEpsonCashDrawer();
      case 'star':
        return _openStarCashDrawer();
      case 'zebra':
        return _openZebraCashDrawer();
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
        debugPrint('Epson receipt has no content');
        return false;
      }

      final printJob = EpsonPrintJob(commands: commands);
      await EpsonPrinter.printReceipt(printJob);

      return true;
    } catch (e) {
      debugPrint('Epson receipt print failed: $e');
      return false;
    }
  }

  static List<EpsonPrintCommand> _buildEpsonReceiptCommands(
    PrinterReceiptData receiptData,
  ) {
    final List<EpsonPrintCommand> cmds = [];

    // Calculate the correct characters per line based on detected paper width
    final effectiveCharsPerLine = PrinterBridge.epsonConfig.charactersPerLine;

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

      // final formattedPrice = price.startsWith('\$') ? price : '\$$price';
      final priceField = price.padLeft(priceWidth);

      return qtyField + nameTrunc.padRight(nameWidth) + priceField;
    }

    String qtyName(String qty, String name) {
      // Layout for gift receipts: qty (3) name (left) - no price
      qty = qty.trim();
      name = name.trim();

      // Adjust qty width for narrower paper
      final qtyWidth = effectiveCharsPerLine >= 40 ? 4 : 3;
      
      final qtyStr = qty.length > (qtyWidth - 1)
          ? qty.substring(0, qtyWidth - 1)
          : qty;
      final qtyField = (qtyStr + 'x').padRight(qtyWidth);

      // Remaining width for name = total - qtyWidth (no price field for gift receipts)
      final nameWidth = effectiveCharsPerLine - qtyWidth;
      String nameTrunc = name;
      if (nameTrunc.length > nameWidth)
        nameTrunc = nameTrunc.substring(0, nameWidth);

      return qtyField + nameTrunc;
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

    

    // Add logo image if provided (matching main.dart implementation)
    if (receiptData.logoBase64 != null && receiptData.logoBase64!.isNotEmpty) {
      // Persist logo to temp file for native side
      try {
        final bytes = base64Decode(receiptData.logoBase64!);
        // NOTE: Synchronous write acceptable for small logo; could be pre-written earlier.
        final tmpDir = Directory.systemTemp;
        final file = File('${tmpDir.path}/epson_logo_${DateTime.now().millisecondsSinceEpoch}.png');
        file.writeAsBytesSync(bytes, flush: true);
        
        // Estimate printer width in dots for different paper sizes
        int estimatePrinterDots() {
          final paperWidth = PrinterBridge.epsonConfig.paperWidth;
          switch (paperWidth) {
            case '58mm': return 384;   // 58mm
            case '60mm': return 424;   // 60mm  
            case '70mm': return 495;   // 70mm
            case '76mm': return 536;   // 76mm
            case '80mm': return 576;   // 80mm
            default: return 576; // fallback to 80mm
          }
        }
        final printerWidthDots = estimatePrinterDots();

        cmds.add(EpsonPrintCommand(type: EpsonCommandType.image, parameters: {
          'imagePath': file.path,
          'printerWidth': printerWidthDots,
          'targetWidth': 200, // Default image width
          'align': 'center',
          'advancedProcessing': false,
        }));
        
        // Add spacing after image
        cmds.add(EpsonPrintCommand(type: EpsonCommandType.feed, parameters: { 'line': 1 }));
      } catch (e) {
        // Fallback marker if file write fails
        debugPrint('PrinterBridge: Image processing failed: $e');
        cmds.add(
          EpsonPrintCommand(
            type: EpsonCommandType.text,
            parameters: {'align': 'center'},
          ),
        );
        cmds.add(
          EpsonPrintCommand(
            type: EpsonCommandType.text,
            parameters: {'data': '[LOGO ERR]\n'},
          ),
        );
        cmds.add(
          EpsonPrintCommand(
            type: EpsonCommandType.text,
            parameters: {'align': 'left'},
          ),
        );
      }
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
        parameters: {'data': '\n${receiptData.receiptTitle}\n'},
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

    // Items - center each item line using SDK for regular receipts, left-align for gift receipts
    for (final item in receiptData.items) {
      cmds.add(
        EpsonPrintCommand(
          type: EpsonCommandType.text,
          parameters: {'align': receiptData.isGiftReceipt ? 'left' : 'center'},
        ),
      );
      cmds.add(
        EpsonPrintCommand(
          type: EpsonCommandType.text,
          parameters: {
            'data': receiptData.isGiftReceipt
                ? qtyName(item.quantity.toString(), item.itemName) + '\n'
                : qtyNamePrice(
                    item.quantity.toString(),
                    item.itemName,
                    item.totalPrice.toStringAsFixed(2),
                  ) + '\n',
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

    // Return items section
    if (receiptData.returnItems != null && receiptData.returnItems!.isNotEmpty) {
      // Add whitespace
      cmds.add(
        EpsonPrintCommand(type: EpsonCommandType.feed, parameters: {'line': 1}),
      );
      
      // "Returns" header (left-aligned)
      cmds.add(
        EpsonPrintCommand(
          type: EpsonCommandType.text,
          parameters: {'data': 'Returns\n'},
        ),
      );
      
      // Print return items with negative prefix - center for regular receipts, left-align for gift receipts
      for (final returnItem in receiptData.returnItems!) {
        cmds.add(
          EpsonPrintCommand(
            type: EpsonCommandType.text,
            parameters: {'align': receiptData.isGiftReceipt ? 'left' : 'center'},
          ),
        );
        cmds.add(
          EpsonPrintCommand(
            type: EpsonCommandType.text,
            parameters: {
              'data': receiptData.isGiftReceipt
                  ? '${returnItem.quantity} x ${returnItem.itemName}\n'
                  : leftRight(
                      '${returnItem.quantity} x ${returnItem.itemName}',
                      '-${returnItem.unitPrice.toStringAsFixed(2)}',
                    ) + '\n',
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
    
    // Financial summary section (skip for gift receipts)
    if (!receiptData.isGiftReceipt && 
        (receiptData.subtotal != null || receiptData.discounts != null || 
         receiptData.hst != null || receiptData.gst != null || receiptData.total != null)) {
      
      cmds.add(
        EpsonPrintCommand(
          type: EpsonCommandType.text,
          parameters: {'align': 'center'},
        ),
      );
      
      // Add each financial line with left-right alignment
      if (receiptData.subtotal != null) {
        cmds.add(
          EpsonPrintCommand(
            type: EpsonCommandType.text,
            parameters: {'data': leftRight('Subtotal', '${receiptData.subtotal!.toStringAsFixed(2)}') + '\n'},
          ),
        );
      }
      
      if (receiptData.discounts != null){ //} && receiptData.discounts! > 0) {
        cmds.add(
          EpsonPrintCommand(
            type: EpsonCommandType.text,
            parameters: {'data': leftRight('Discounts', '${receiptData.discounts!.toStringAsFixed(2)}') + '\n'},
          ),
        );
      }
      
      if (receiptData.hst != null && receiptData.hst! > 0) {
        cmds.add(
          EpsonPrintCommand(
            type: EpsonCommandType.text,
            parameters: {'data': leftRight('HST', '${receiptData.hst!.toStringAsFixed(2)}') + '\n'},
          ),
        );
      }
      
      if (receiptData.gst != null && receiptData.gst! > 0) {
        cmds.add(
          EpsonPrintCommand(
            type: EpsonCommandType.text,
            parameters: {'data': leftRight('GST', '${receiptData.gst!.toStringAsFixed(2)}') + '\n'},
          ),
        );
      }
      
      if (receiptData.total != null) {
        cmds.add(
          EpsonPrintCommand(
            type: EpsonCommandType.text,
            parameters: {'data': leftRight('Total', '${receiptData.total!.toStringAsFixed(2)}') + '\n'},
          ),
        );
      }
      
      cmds.add(
        EpsonPrintCommand(
          type: EpsonCommandType.text,
          parameters: {'align': 'left'},
        ),
      );
      
      // Third horizontal line after financial summary
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
      
      // Payment methods section
      if (receiptData.payments != null && receiptData.payments!.isNotEmpty) {
        // Add centered "Payment Method" header
        cmds.add(
          EpsonPrintCommand(
            type: EpsonCommandType.text,
            parameters: {'align': 'center'},
          ),
        );
        cmds.add(
          EpsonPrintCommand(
            type: EpsonCommandType.text,
            parameters: {'data': 'Payment Method\n'},
          ),
        );
        cmds.add(
          EpsonPrintCommand(
            type: EpsonCommandType.text,
            parameters: {'align': 'left'},
          ),
        );
        
        // Add each payment method with left-right alignment
        receiptData.payments!.forEach((method, amount) {
          cmds.add(
            EpsonPrintCommand(
              type: EpsonCommandType.text,
              parameters: {'data': leftRight(method, '${amount.toStringAsFixed(2)}') + '\n'},
            ),
          );
        });
      }
    }

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
  /// For Zebra printers, dimensions parameter (width, height, dpi) is recommended to avoid internal API calls
  static Future<bool> printLabel(
    String brand,
    PrinterLabelData labelData, {
    Map<String, int>? dimensions,
  }) async {
    switch (brand.toLowerCase()) {
      case 'epson':
        return await _printEpsonLabel(labelData);
      case 'star':
        return await _printStarLabel(labelData);
      case 'zebra':
        return await _printZebraLabel(labelData, dimensions);
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
      debugPrint('Epson label print failed: $e');
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

  static Future<bool> _printZebraLabel(PrinterLabelData labelData, [Map<String, int>? dimensions]) async {
    try {
      // Use provided dimensions or fall back to cached/fresh dimensions
      Map<String, int>? effectiveDimensions = dimensions;
      if (effectiveDimensions == null) {
        debugPrint('PrinterBridge: No dimensions provided, fetching from cache/API...');
        effectiveDimensions = await getZebraDimensions();
      }
      
      final width = effectiveDimensions?['printWidthInDots'] ?? 386;
      final height = effectiveDimensions?['labelLengthInDots'] ?? 212;
      final dpi = effectiveDimensions?['dpi'] ?? 203;

      debugPrint('PrinterBridge: Using Zebra label dimensions: ${width}x${height} @ ${dpi}dpi');
      
      // Generate ZPL once for all labels
      final labelZpl = _generateZebraLabelZPL(width, height, dpi, labelData);
      
      // Print all labels with the same ZPL
      for (int i = 0; i < labelData.quantity; i++) {
        await ZebraPrinter.sendCommands(labelZpl, language: ZebraPrintLanguage.zpl);
        if (i < labelData.quantity - 1) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }

      return true;
    } catch (e) {
      debugPrint('Zebra label print failed: $e');
      return false;
    }
  }

  // Cash drawer methods for each brand
  static Future<bool> _openEpsonCashDrawer() async {
    try {
      await EpsonPrinter.openCashDrawer();
      return true;
    } catch (e) {
      debugPrint('Epson cash drawer failed: $e');
      return false;
    }
  }

  static Future<bool> _openStarCashDrawer() async {
    try {
      await star.StarPrinter.openCashDrawer();
      return true;
    } catch (e) {
      debugPrint('Star cash drawer failed: $e');
      return false;
    }
  }

  static Future<bool> _openZebraCashDrawer() async {
    try {
      // TODO: Implement Zebra cash drawer support
      debugPrint('Zebra cash drawer not yet implemented');
      return false;
    } catch (e) {
      debugPrint('Zebra cash drawer failed: $e');
      return false;
    }
  }

  static Future<bool> _printStarReceipt(PrinterReceiptData receiptData) async {
    try {
      final printableAreaMm = PrinterBridge.starConfig.printableAreaMm;
      final paperWidthMm = PrinterBridge.starConfig.paperWidthMm;
      debugPrint('Star receipt - using ${paperWidthMm}mm paper (command-based approach)');
      
      // Build commands in Dart - all layout logic lives here
      final commands = _buildStarReceiptCommands(receiptData);
      
      debugPrint('Star receipt - built ${commands.length} commands');
      
      // Also build legacy layout settings for graphics-only printers (TSP100IIIW)
      // These printers need createDetailsImage() which renders everything as ONE image
      final layoutSettings = {
        'layout': {
          'header': {
            'title': receiptData.storeName,
            'align': 'center',
            'fontSize': 32,
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
            'receiptTitle': receiptData.receiptTitle,
            'isGiftReceipt': receiptData.isGiftReceipt,
            if (!receiptData.isGiftReceipt) ...{
              'subtotal': receiptData.subtotal?.toStringAsFixed(2),
              'discounts': receiptData.discounts?.toStringAsFixed(2), 
              'hst': receiptData.hst?.toStringAsFixed(2),
              'gst': receiptData.gst?.toStringAsFixed(2),
              'total': receiptData.total?.toStringAsFixed(2),
              'payments': receiptData.payments?.map((method, amount) => 
                MapEntry(method, amount.toStringAsFixed(2))),
            },
          },
          'items': receiptData.items.map((item) => <String, dynamic>{
            'quantity': item.quantity.toString(),
            'name': item.itemName,
            if (!receiptData.isGiftReceipt) 'price': item.unitPrice.toStringAsFixed(2),
          }).toList(),
          'returnItems': receiptData.returnItems?.map((returnItem) => <String, dynamic>{
            'quantity': returnItem.quantity.toString(),
            'name': returnItem.itemName,
            if (!receiptData.isGiftReceipt) 'price': returnItem.unitPrice.toStringAsFixed(2),
          }).toList(),
          'image': receiptData.logoBase64 == null
              ? null
              : {
                  'base64': receiptData.logoBase64,
                  'mime': 'image/png',
                  'align': 'center',
                  'width': 200,
                  'spacingLines': 1,
                },
        },
      };
      
      final printJob = star.PrintJob(
        content: '',
        commands: commands.map((cmd) => cmd.toMap()).toList(),
        settings: layoutSettings, // Include legacy settings for graphics-only printer fallback
      );
      
      debugPrint('Sending Star receipt to printer...');
      await star.StarPrinter.printReceipt(printJob);
      
      debugPrint('Star receipt completed successfully');
      return true;
    } catch (e) {
      debugPrint('Star receipt print failed: $e');
      return false;
    }
  }

  /// Build Star print commands from universal receipt data
  /// All receipt layout logic lives here in Dart
  static List<StarPrintCommand> _buildStarReceiptCommands(PrinterReceiptData receiptData) {
    final List<StarPrintCommand> cmds = [];
    final paperWidthMm = PrinterBridge.starConfig.paperWidthMm;
    final isNarrowPaper = paperWidthMm <= 58; // 58mm or 38mm paper

    // 1. HEADER - Store name (centered, large)
    if (receiptData.storeName.isNotEmpty) {
      cmds.add(StarPrintCommand.text(
        '${receiptData.storeName}\n',
        align: StarAlignment.center,
        bold: true,
        magnificationWidth: 2,
        magnificationHeight: 2,
      ));
      cmds.add(StarPrintCommand.feed(1));
    }

    // 2. LOGO IMAGE (if provided)
    if (receiptData.logoBase64 != null && receiptData.logoBase64!.isNotEmpty) {
      cmds.add(StarPrintCommand.image(
        receiptData.logoBase64!,
        width: 200,
        align: StarAlignment.center,
      ));
      cmds.add(StarPrintCommand.feed(1));
    }

    // 3. STORE ADDRESS (centered)
    if (receiptData.storeAddress.isNotEmpty) {
      cmds.add(StarPrintCommand.text(
        '${receiptData.storeAddress}\n',
        align: StarAlignment.center,
      ));
    }

    // 4. STORE PHONE (centered, if provided)
    if (receiptData.storePhone != null && receiptData.storePhone!.isNotEmpty) {
      cmds.add(StarPrintCommand.text(
        '${receiptData.storePhone}\n',
        align: StarAlignment.center,
      ));
    }

    cmds.add(StarPrintCommand.feed(1));

    // 5. RECEIPT TITLE (centered)
    cmds.add(StarPrintCommand.text(
      '${receiptData.receiptTitle}\n',
      align: StarAlignment.center,
      bold: true,
    ));

    // 6. DATE/TIME and CASHIER
    final dateTimeStr = '${receiptData.date} ${receiptData.time}';
    final cashierStr = receiptData.cashierName != null && receiptData.cashierName!.isNotEmpty
        ? 'Cashier: ${receiptData.cashierName}'
        : '';
    
    if (isNarrowPaper) {
      // Narrow paper (58mm/38mm): each field on its own line
      if (dateTimeStr.trim().isNotEmpty) {
        cmds.add(StarPrintCommand.text('$dateTimeStr\n'));
      }
      
      if (cashierStr.isNotEmpty) {
        cmds.add(StarPrintCommand.text('$cashierStr\n'));
      }
    } else {
      // Wide paper (80mm): date/time and cashier on same line
      if (dateTimeStr.trim().isNotEmpty || cashierStr.isNotEmpty) {
        cmds.add(StarPrintCommand.textLeftRight(dateTimeStr, cashierStr));
      }
    }

    // 7. RECEIPT NUMBER and LANE
    final receiptNumStr = receiptData.receiptNumber != null && receiptData.receiptNumber!.isNotEmpty
        ? 'Receipt No: ${receiptData.receiptNumber}'
        : '';
    final laneStr = receiptData.laneNumber != null && receiptData.laneNumber!.isNotEmpty
        ? 'Lane: ${receiptData.laneNumber}'
        : '';
    
    if (isNarrowPaper) {
      // Narrow paper (58mm/38mm): each field on its own line
      if (receiptNumStr.isNotEmpty) {
        cmds.add(StarPrintCommand.text('$receiptNumStr\n'));
      }
      if (laneStr.isNotEmpty) {
        cmds.add(StarPrintCommand.text('$laneStr\n'));
      }
    } else {
      // Wide paper (80mm): receipt number and lane on same line
      if (receiptNumStr.isNotEmpty || laneStr.isNotEmpty) {
        cmds.add(StarPrintCommand.textLeftRight(receiptNumStr, laneStr));
      }
    }

    cmds.add(StarPrintCommand.feed(1));
    cmds.add(StarPrintCommand.line());

    // 8. LINE ITEMS
    for (final item in receiptData.items) {
      if (receiptData.isGiftReceipt) {
        // Gift receipt: quantity x name only (no price)
        cmds.add(StarPrintCommand.text(
          '${item.quantity} x ${item.itemName}\n',
        ));
      } else {
        // Regular receipt: quantity | name | price columns
        cmds.add(StarPrintCommand.textColumns([
          StarColumn(text: '${item.quantity} x', weight: 1, align: StarAlignment.left),
          StarColumn(text: item.itemName, weight: 5, align: StarAlignment.left),
          StarColumn(text: item.totalPrice.toStringAsFixed(2), weight: 2, align: StarAlignment.right),
        ]));
      }
    }

    // 9. RETURN ITEMS (if any)
    if (receiptData.returnItems != null && receiptData.returnItems!.isNotEmpty) {
      cmds.add(StarPrintCommand.feed(1));
      cmds.add(StarPrintCommand.text('Returns\n', bold: true));
      
      for (final returnItem in receiptData.returnItems!) {
        if (receiptData.isGiftReceipt) {
          cmds.add(StarPrintCommand.text(
            '${returnItem.quantity} x ${returnItem.itemName}\n',
          ));
        } else {
          cmds.add(StarPrintCommand.textColumns([
            StarColumn(text: '${returnItem.quantity} x', weight: 1, align: StarAlignment.left),
            StarColumn(text: returnItem.itemName, weight: 5, align: StarAlignment.left),
            StarColumn(text: '-${returnItem.unitPrice.toStringAsFixed(2)}', weight: 2, align: StarAlignment.right),
          ]));
        }
      }
    }

    cmds.add(StarPrintCommand.line());

    // 10. FINANCIAL SUMMARY (skip for gift receipts)
    if (!receiptData.isGiftReceipt) {
      if (receiptData.subtotal != null) {
        cmds.add(StarPrintCommand.textLeftRight(
          'Subtotal',
          receiptData.subtotal!.toStringAsFixed(2),
        ));
      }
      
      if (receiptData.discounts != null ) {
        cmds.add(StarPrintCommand.textLeftRight(
          'Discounts',
          '-${receiptData.discounts!.toStringAsFixed(2)}',
        ));
      }
      
      if (receiptData.hst != null) {
        cmds.add(StarPrintCommand.textLeftRight(
          'HST',
          receiptData.hst!.toStringAsFixed(2),
        ));
      }
      
      if (receiptData.gst != null) {
        cmds.add(StarPrintCommand.textLeftRight(
          'GST',
          receiptData.gst!.toStringAsFixed(2),
        ));
      }
      if (receiptData.total != null) {
        cmds.add(StarPrintCommand.textLeftRight(
          'Total',
          receiptData.total!.toStringAsFixed(2),
        ));
      }
      
      cmds.add(StarPrintCommand.line());

      // 11. PAYMENT METHODS
      if (receiptData.payments != null && receiptData.payments!.isNotEmpty) {
        cmds.add(StarPrintCommand.text(
          'Payment Method\n',
          align: StarAlignment.center,
        ));
        
        for (final entry in receiptData.payments!.entries) {
          cmds.add(StarPrintCommand.textLeftRight(
            entry.key,
            '${entry.value.toStringAsFixed(2)}',
          ));
        }
        cmds.add(StarPrintCommand.feed(1));
      }
    }

    // 12. THANK YOU MESSAGE
    if (receiptData.thankYouMessage != null && receiptData.thankYouMessage!.isNotEmpty) {
      cmds.add(StarPrintCommand.feed(1));
      cmds.add(StarPrintCommand.text(
        '${receiptData.thankYouMessage}\n',
        align: StarAlignment.center,
      ));
    }

    // 13. FEED AND CUT
    cmds.add(StarPrintCommand.feed(3));
    cmds.add(StarPrintCommand.cut());

    return cmds;
  }

  static Future<bool> _printStarLabel(PrinterLabelData labelData) async {
    try {
      debugPrint('Star label print - Creating label print job for ${labelData.quantity} label(s)...');
      
      // Use StarConfig to get proper printable area and layout type based on configured paper width
      final printableAreaMm = PrinterBridge.starConfig.printableAreaMm;
      final layoutType = PrinterBridge.starConfig.layoutType;
      final paperWidthMm = PrinterBridge.starConfig.paperWidthMm;
      
      debugPrint('Star label - using ${paperWidthMm}mm paper, printableAreaMm: $printableAreaMm, layoutType: $layoutType');
      
      // Extract label content from PrinterLabelData
      final productName = labelData.productName.isNotEmpty ? labelData.productName : 'PRODUCT NAME';
      final category = '';  // Could be extended in PrinterLabelData if needed
      // Strip any existing dollar signs from price to match main.dart behavior
      final rawPrice = labelData.price.isNotEmpty ? labelData.price.replaceAll('\$', '') : '0.00';
      final price = rawPrice.isNotEmpty ? rawPrice : '0.00';
      final scancode = labelData.barcode.isNotEmpty ? labelData.barcode : '0123456789';
      
      // Parse colorSize to extract size and color components
      // colorSize format is typically "Small Turquoise" - split it properly
      final colorSizeComponents = labelData.colorSize.isNotEmpty ? labelData.colorSize.split(' ') : ['Default'];
      final size = colorSizeComponents.isNotEmpty ? colorSizeComponents[0] : '';
      final color = colorSizeComponents.length > 1 ? colorSizeComponents.skip(1).join(' ') : (colorSizeComponents.isNotEmpty ? colorSizeComponents[0] : 'Default Color');
      
      // Label layout settings following the same pattern as main.dart
      final labelSettings = {
        'layout': {
          'header': {
            'title': productName,
            'align': 'center',
            'fontSize': 40,
            'spacingLines': 0,
          },
          'details': {
            'category': category,
            'size': size,
            'color': color,
            'price': price,
            'layoutType': layoutType,  // Tell native code which template to use
            'printableAreaMm': printableAreaMm,  // Pass printable area to native code
          },
          'items': [],
          'image': null,
          'barcode': {
            'content': scancode,
            'symbology': 'code128',  // Using CODE128 as in main.dart
            'height': 4,  // Very compact barcode height
            'printHRI': true,  // Print numbers below barcode
          },
        },
      };
      
      final labelContent = '';

      final printJob = star.PrintJob(
        content: labelContent,
        settings: labelSettings,
      );
      
      bool shownPaperHoldWarning = false;
      
      // Print multiple labels with the same logic as main.dart
      for (int i = 0; i < labelData.quantity; i++) {
        debugPrint('Star label - Sending label ${i + 1} of ${labelData.quantity} to printer...');
        
        final printStartTime = DateTime.now();
        
        try {
          // Try to print the label
          await star.StarPrinter.printReceipt(printJob);
          
          final printDuration = DateTime.now().difference(printStartTime);
          debugPrint('Star label - Label ${i + 1} completed in ${printDuration.inMilliseconds}ms');
          
          // Small delay between prints to prevent buffer overflow
          if (i < labelData.quantity - 1) {
            await Future.delayed(const Duration(milliseconds: 100));
          }
        } catch (e) {
          // Check if this is a paper hold error (same logic as main.dart)
          final errorMessage = e.toString().toLowerCase();
          if (errorMessage.contains('holding paper') || errorMessage.contains('paper hold')) {
            if (!shownPaperHoldWarning) {
              debugPrint('Star label - Paper hold detected - waiting for user to remove labels');
              shownPaperHoldWarning = true;
            }
            debugPrint('Star label - Paper hold detected - waiting for user to remove label ${i + 1}');
            
            // Keep trying to print this label until it succeeds
            bool labelPrinted = false;
            while (!labelPrinted) {
              await Future.delayed(const Duration(milliseconds: 500));
              try {
                await star.StarPrinter.printReceipt(printJob);
                labelPrinted = true;
                debugPrint('Star label - Label ${i + 1} printed after paper removal');
              } catch (retryError) {
                // Still holding, keep waiting
                if (!retryError.toString().toLowerCase().contains('holding paper')) {
                  // Different error, rethrow
                  rethrow;
                }
              }
            }
            
            final printDuration = DateTime.now().difference(printStartTime);
            debugPrint('Star label - Label ${i + 1} completed in ${printDuration.inMilliseconds}ms (including wait time)');
            
            // Small delay between prints
            if (i < labelData.quantity - 1) {
              await Future.delayed(const Duration(milliseconds: 100));
            }
          } else {
            // Different error, rethrow
            rethrow;
          }
        }
      }
      
      debugPrint('Star label - All ${labelData.quantity} label(s) printed successfully');
      return true;
    } catch (e) {
      debugPrint('Star label print failed: $e');
      return false;
    }
  }

  static Future<bool> _printZebraReceipt(PrinterReceiptData receiptData, [Map<String, int>? dimensions]) async {
    try {
      // Use provided dimensions or fall back to cached/fresh dimensions
      Map<String, int>? effectiveDimensions = dimensions;
      if (effectiveDimensions == null) {
        debugPrint('PrinterBridge: No dimensions provided, fetching from cache/API...');
        effectiveDimensions = await getZebraDimensions();
      }
      
      final width = effectiveDimensions?['printWidthInDots'] ?? 386;
      final height = effectiveDimensions?['labelLengthInDots'] ?? 600; // Use larger default for receipts
      final dpi = effectiveDimensions?['dpi'] ?? 203;

      debugPrint('PrinterBridge: Using Zebra receipt dimensions: ${width}x${height} @ ${dpi}dpi');
      
      // Generate and send ZPL
      final receiptZpl = _generateZebraReceiptZPL(width, height, dpi, receiptData);
      await ZebraPrinter.sendCommands(receiptZpl, language: ZebraPrintLanguage.zpl);

      return true;
    } catch (e) {
      debugPrint('Zebra receipt print failed: $e');
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
        "${receiptData.date} ${now.hour}:${now.minute.toString().padLeft(2, '0')}"; //${now.hour >= 12 ? 'PM' : 'AM'}";

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

    debugPrint(
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

    // Add logo if provided (dynamic conversion from base64)
    if (receiptData.logoBase64 != null && receiptData.logoBase64!.isNotEmpty) {
      try {
        debugPrint('[PrinterBridge] Converting logo image to ZPL...');
        final logoZpl = convertImageToZPL(
          receiptData.logoBase64!,
          maxWidth: 400,  // 3x larger than before (was 200)
          maxHeight: 200, // 2x larger than before (was 100)
        );
        
        if (logoZpl.isNotEmpty) {
          // Position logo at same location as hardcoded logo
          receiptZpl += '''
^FO200,132
$logoZpl^FS''';
        } else {
          debugPrint('[PrinterBridge] Logo conversion failed, using placeholder');
          // Fallback: Add a simple text placeholder
          receiptZpl += '''
^CF0,25
^FO200,132
^FD[LOGO]^FS''';
        }
      } catch (e) {
        debugPrint('[PrinterBridge] Logo processing error: $e');
        // Fallback: Add a simple text placeholder
        receiptZpl += '''
^CF0,25
^FO200,132
^FD[LOGO ERR]^FS''';
      }
    }

    // Add separator line
    int lineWidth = width - 40; // 20 dot margin on each side
    receiptZpl += '''
^FO20,574^GB$lineWidth,1,2,B,0^FS''';

    // Add line items dynamically
    int yPosition = 612;
    for (var item in receiptData.items) {
      // For gift receipts, only show quantity and name, no price
      if (receiptData.isGiftReceipt) {
        receiptZpl +=
            '''
^CF0,25
^FO20,$yPosition
^FD${item.quantity} x ${item.itemName}^FS''';
      } else {
        // Calculate right-aligned position for price
        String priceText = "${item.unitPrice.toStringAsFixed(2)}";
        int priceCharWidth = getCharWidthInDots(25, dpi);
        int estimatedPriceWidth = priceText.length * priceCharWidth;
        int priceX = (width - estimatedPriceWidth - 20); // 20 dot right margin
        priceX = priceX.clamp(200, width - estimatedPriceWidth); // Ensure minimum left margin
        
        receiptZpl +=
            '''
^CF0,25
^FO20,$yPosition
^FD${item.quantity} x ${item.itemName}^FS
^CF0,25
^FO$priceX,$yPosition
^FD$priceText^FS''';
      }
      yPosition += 56; // Move down for next item
    }

    // Return items section
    if (receiptData.returnItems != null && receiptData.returnItems!.isNotEmpty) {
      // Add whitespace
      yPosition += 28; // Half spacing for whitespace
      
      // "Returns" header (left-aligned)
      receiptZpl += '''
^CF0,25
^FO20,$yPosition
^FDReturns^FS''';
      yPosition += 56; // Move down for return items
      
      // Print return items with negative prefix (for regular receipts) or just name for gift receipts
      for (var returnItem in receiptData.returnItems!) {
        if (receiptData.isGiftReceipt) {
          // For gift receipts, only show quantity and name, no price
          receiptZpl += '''
^CF0,25
^FO20,$yPosition
^FD${returnItem.quantity} x ${returnItem.itemName}^FS''';
        } else {
          // Calculate right-aligned position for negative price
          String returnPriceText = "-${returnItem.unitPrice.toStringAsFixed(2)}";
          int returnPriceCharWidth = getCharWidthInDots(25, dpi);
          int estimatedReturnPriceWidth = returnPriceText.length * returnPriceCharWidth;
          int returnPriceX = (width - estimatedReturnPriceWidth - 20) - returnPriceCharWidth; // Shift left by one char to align decimal
          returnPriceX = returnPriceX.clamp(200, width - estimatedReturnPriceWidth); // Ensure minimum left margin
          
          receiptZpl += '''
^CF0,25
^FO20,$yPosition
^FD${returnItem.quantity} x ${returnItem.itemName}^FS
^CF0,25
^FO$returnPriceX,$yPosition
^FD$returnPriceText^FS''';
        }
        yPosition += 56; // Move down for next return item
      }
    }

    // Calculate positions for bottom elements after line items
    int bottomLineY = yPosition + 20; // Add some spacing after last item
    int totalY = bottomLineY + 22; // Add spacing after bottom line
    int thankYouY = totalY + 54; // Add spacing after total

    debugPrint(
      '[PrinterBridge] Receipt layout - Last item Y: $yPosition, Total Y: $totalY, Initial thank you Y: $thankYouY',
    );

    // Add bottom line at dynamic position
    receiptZpl += '''
^FO20,$bottomLineY^GB$lineWidth,1,2,B,0^FS''';

    // Financial summary section - only include if not a gift receipt
    if (!receiptData.isGiftReceipt) {
      int currentY = totalY;
      if (receiptData.subtotal != null || receiptData.discounts != null || 
          receiptData.hst != null || receiptData.gst != null || receiptData.total != null) {
        
        // Add each financial line with left-right alignment
        if (receiptData.subtotal != null) {
          String subtotalText = "${receiptData.subtotal!.toStringAsFixed(2)}";
          int subtotalCharWidth = getCharWidthInDots(25, dpi);
          int estimatedSubtotalWidth = subtotalText.length * subtotalCharWidth;
          int subtotalX = (width - estimatedSubtotalWidth - 20);
          subtotalX = subtotalX.clamp(200, width - estimatedSubtotalWidth);
          
          receiptZpl += '''
^CF0,25
^FO20,$currentY
^FDSubtotal^FS
^CF0,25
^FO$subtotalX,$currentY
^FD$subtotalText^FS''';
          currentY += 40;
        }
        
        if (receiptData.discounts != null) {
          String discountText = "${receiptData.discounts!.toStringAsFixed(2)}";
          int discountCharWidth = getCharWidthInDots(25, dpi);
          int estimatedDiscountWidth = discountText.length * discountCharWidth;
          int discountX = (width - estimatedDiscountWidth - 20);
          discountX = discountX.clamp(200, width - estimatedDiscountWidth);
          
          receiptZpl += '''
^CF0,25
^FO20,$currentY
^FDDiscounts^FS
^CF0,25
^FO$discountX,$currentY
^FD$discountText^FS''';
          currentY += 40;
        }
        
        if (receiptData.hst != null && receiptData.hst! > 0) {
          String hstText = "${receiptData.hst!.toStringAsFixed(2)}";
          int hstCharWidth = getCharWidthInDots(25, dpi);
          int estimatedHstWidth = hstText.length * hstCharWidth;
          int hstX = (width - estimatedHstWidth - 20);
          hstX = hstX.clamp(200, width - estimatedHstWidth);
          
          receiptZpl += '''
^CF0,25
^FO20,$currentY
^FDHST^FS
^CF0,25
^FO$hstX,$currentY
^FD$hstText^FS''';
          currentY += 40;
        }
        
        if (receiptData.gst != null && receiptData.gst! > 0) {
          String gstText = "${receiptData.gst!.toStringAsFixed(2)}";
          int gstCharWidth = getCharWidthInDots(25, dpi);
          int estimatedGstWidth = gstText.length * gstCharWidth;
          int gstX = (width - estimatedGstWidth - 20);
          gstX = gstX.clamp(200, width - estimatedGstWidth);
          
          receiptZpl += '''
^CF0,25
^FO20,$currentY
^FDGST^FS
^CF0,25
^FO$gstX,$currentY
^FD$gstText^FS''';
          currentY += 40;
        }
        
        if (receiptData.total != null) {
          String totalText = "${receiptData.total!.toStringAsFixed(2)}";
          int totalCharWidth = getCharWidthInDots(25, dpi);
          int estimatedTotalWidth = totalText.length * totalCharWidth;
          int totalX = (width - estimatedTotalWidth - 20);
          totalX = totalX.clamp(200, width - estimatedTotalWidth);
          
          receiptZpl += '''
^CF0,25
^FO20,$currentY
^FDTotal^FS
^CF0,25
^FO$totalX,$currentY
^FD$totalText^FS''';
          currentY += 40;
        }
        
        // Add third horizontal line after financial summary
        int thirdLineY = currentY + 20;
        receiptZpl += '''
^FO20,$thirdLineY^GB$lineWidth,1,2,B,0^FS''';
        
        // Update thank you position after financial summary
        thankYouY = thirdLineY + 54;
        
        // Add payment methods section if payments exist
        if (receiptData.payments != null && receiptData.payments!.isNotEmpty) {
          int paymentY = thirdLineY + 54;
          
          // Add centered "Payment Method" header
          String paymentHeaderText = "Payment Method";
          int paymentHeaderCharWidth = getCharWidthInDots(25, dpi);
          int estimatedPaymentHeaderWidth = paymentHeaderText.length * paymentHeaderCharWidth;
          int paymentHeaderX = (width - estimatedPaymentHeaderWidth) ~/ 2;
          paymentHeaderX = paymentHeaderX.clamp(20, width - estimatedPaymentHeaderWidth - 20);
          
          receiptZpl += '''
^CF0,25
^FO$paymentHeaderX,$paymentY
^FD$paymentHeaderText^FS''';
          
          paymentY += 40;
          
          // Add each payment method with left-right alignment
          receiptData.payments!.forEach((method, amount) {
            String amountText = "${amount.toStringAsFixed(2)}";
            if (amount < 0) {
              amountText = "-${(-amount).toStringAsFixed(2)}";
            }
            int amountCharWidth = getCharWidthInDots(25, dpi);
            int estimatedAmountWidth = amountText.length * amountCharWidth;
            int amountX = (width - estimatedAmountWidth - 20);
            // For negative numbers, shift left by one character to align decimal points
            if (amount < 0) {
              amountX -= amountCharWidth;
            }
            amountX = amountX.clamp(200, width - estimatedAmountWidth);
            
            receiptZpl += '''
^CF0,25
^FO20,$paymentY
^FD$method^FS
^CF0,25
^FO$amountX,$paymentY
^FD$amountText^FS''';
            paymentY += 40;
          });
          
          // Update thank you position after payment methods
          thankYouY = paymentY + 20;
        }
      }
    } else {
      // For gift receipts, set thank you position closer to bottom line
      thankYouY = bottomLineY + 54;
    }

    // Calculate minimum required height AFTER all dynamic content is added
    int minRequiredHeight = thankYouY + 60; // Add bottom margin

    // Use the larger of the detected height or minimum required height
    int actualReceiptHeight = height > minRequiredHeight
        ? height
        : minRequiredHeight;

    debugPrint(
      '[PrinterBridge] Receipt height - Final thank you Y: $thankYouY, Required: $minRequiredHeight, Using: $actualReceiptHeight',
    );

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
        return 16; // Reduced from 20 to 16 for more accurate centering of font size 38
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

    debugPrint(
      'Zebra label font calculations - DPI: $dpi, Font 38: ${productNameCharWidth}dots/char, Font 25: ${colorSizeCharWidth}dots/char',
    );
    debugPrint(
      'Zebra label text widths - ProductName: ${estimatedProductNameWidth}dots, ColorSize: ${estimatedColorSizeWidth}dots, Price: ${estimatedPriceWidth}dots',
    );

    // Calculate centered X position for each element
    final barcodeX = ((paperWidthDots - estimatedBarcodeWidth) ~/ 2).clamp(
      0,
      paperWidthDots - estimatedBarcodeWidth,
    );
    final productNameX = ((paperWidthDots - estimatedProductNameWidth) ~/ 2).clamp(
      0,
      paperWidthDots - estimatedProductNameWidth,
    );
    final colorSizeX = ((paperWidthDots - estimatedColorSizeWidth) ~/ 2).clamp(
      0,
      paperWidthDots - estimatedColorSizeWidth,
    );
    final priceX = ((paperWidthDots - estimatedPriceWidth) ~/ 2).clamp(
      0,
      paperWidthDots - estimatedPriceWidth,
    );

    debugPrint(
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

  /// Convert base64 image to ZPL ^GF graphic field
  /// Uses threshold conversion for clean black/white output
  /// Auto-scales images to fit Zebra printer memory limits
  static String convertImageToZPL(
    String base64Image, {
    int maxWidth = 400,    // Increased from 200 for larger images
    int maxHeight = 200,   // Increased from 100 for larger images
    int threshold = 128,
  }) {
    try {
      // Decode base64 image
      final imageBytes = base64Decode(base64Image);
      final originalImage = img.decodeImage(imageBytes);
      
      if (originalImage == null) {
        debugPrint('PrinterBridge: Failed to decode image');
        return '';
      }

      // Calculate scaled dimensions to fit within limits while maintaining aspect ratio
      final originalWidth = originalImage.width;
      final originalHeight = originalImage.height;
      
      double scaleX = maxWidth / originalWidth;
      double scaleY = maxHeight / originalHeight;
      double scale = scaleX < scaleY ? scaleX : scaleY; // Use smaller scale to fit both dimensions
      
      final scaledWidth = (originalWidth * scale).round();
      final scaledHeight = (originalHeight * scale).round();
      
      debugPrint('PrinterBridge: Image scaling ${originalWidth}x${originalHeight} -> ${scaledWidth}x${scaledHeight} (scale: ${scale.toStringAsFixed(2)})');
      
      // Resize image if needed
      img.Image resizedImage = originalImage;
      if (scale < 1.0) {
        resizedImage = img.copyResize(originalImage, width: scaledWidth, height: scaledHeight);
      }
      
      // Convert to grayscale for consistent threshold processing
      final grayscaleImage = img.grayscale(resizedImage);
      
      // Apply threshold to convert to pure black and white
      for (int y = 0; y < grayscaleImage.height; y++) {
        for (int x = 0; x < grayscaleImage.width; x++) {
          final pixel = grayscaleImage.getPixel(x, y);
          final luminance = img.getLuminanceRgb(pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt());
          final newColor = luminance >= threshold ? img.ColorRgb8(255, 255, 255) : img.ColorRgb8(0, 0, 0);
          grayscaleImage.setPixel(x, y, newColor);
        }
      }
      
      // Calculate bytes per row (must be multiple of 8 bits)
      final bytesPerRow = ((grayscaleImage.width + 7) ~/ 8);
      final totalBytes = bytesPerRow * grayscaleImage.height;
      
      // Convert to ZPL hex data
      final hexData = StringBuffer();
      for (int y = 0; y < grayscaleImage.height; y++) {
        for (int byteIndex = 0; byteIndex < bytesPerRow; byteIndex++) {
          int byteValue = 0;
          
          // Pack 8 pixels into one byte
          for (int bit = 0; bit < 8; bit++) {
            final x = byteIndex * 8 + bit;
            if (x < grayscaleImage.width) {
              final pixel = grayscaleImage.getPixel(x, y);
              final isBlack = img.getLuminanceRgb(pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()) < threshold;
              if (isBlack) {
                byteValue |= (1 << (7 - bit)); // Set bit for black pixels
              }
            }
          }
          
          // Convert byte to hex (uppercase)
          hexData.write(byteValue.toRadixString(16).toUpperCase().padLeft(2, '0'));
        }
      }
      
      // Build ZPL ^GF command
      // Format: ^GFA,total_bytes,total_bytes,bytes_per_row,data
      final zplCommand = '^GFA,$totalBytes,$totalBytes,$bytesPerRow,${hexData.toString()}';
      
      debugPrint('PrinterBridge: Generated ZPL image ${grayscaleImage.width}x${grayscaleImage.height}, $totalBytes bytes');
      
      return zplCommand;
    } catch (e) {
      debugPrint('PrinterBridge: Image to ZPL conversion failed: $e');
      return '';
    }
  }
}
