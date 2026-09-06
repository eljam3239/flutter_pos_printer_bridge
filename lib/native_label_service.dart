import 'package:flutter/foundation.dart';

import 'printer_bridge.dart';
import 'printer_host.dart';
import 'printer_localizations.dart';

/// A single queued label print request: one product (or variant) and how many
/// labels to print for it.
class LabelPrintJob {
  /// What to print. See [NativeLabelService.printLabels] for the shape.
  final Map<String, dynamic> product;

  final int quantity;

  const LabelPrintJob({
    required this.product,
    required this.quantity,
  });

  /// Human-readable name for progress and error messages.
  String get label {
    final name = product['name']?.toString();
    return (name != null && name.isNotEmpty) ? name : 'product';
  }
}

/// A connected label printer plus the per-print arguments its brand needs.
///
/// Exists so a batch connects once and prints many: [PrinterBridge.printLabel]
/// takes Epson's width as an argument rather than reading it from config, so
/// that value has to survive alongside the connection for the whole batch.
class _LabelPrinterSession {
  final SavedPrinter printer;
  final String? epsonWidth;

  const _LabelPrinterSession(this.printer, this.epsonWidth);
}

/// Label printing against the operator's configured default label printer.
///
/// The counterpart to [NativeReceiptService], and the same shape: resolve the
/// default printer, prime brand configuration in the order each vendor's SDK
/// requires, connect, print. The difference is batching — labels are printed
/// in runs (twelve of one variant, then six of another), so the connection and
/// configuration happen once and every label in the queue reuses them.
class NativeLabelService {
  static PrinterRegistry get _registry => PrinterRegistry.instance;

  /// Get available label printers
  static List<SavedPrinter> getLabelPrinters() {
    return _registry.savedPrinters
        .where((printer) => printer.isLabel && printer.isActive)
        .toList();
  }

  /// Check if any label printers are available
  static bool get hasLabelPrinters => getLabelPrinters().isNotEmpty;

  /// Check if default label printer is available
  static bool get hasDefaultLabelPrinter =>
      _registry.getDefaultLabelPrinter() != null;

  /// Debug method: Print current label printer configuration
  static void debugPrintConfiguration() {
    debugPrint('NativeLabelService: === LABEL PRINTER CONFIGURATION DEBUG ===');

    final allPrinters = _registry.savedPrinters;
    final labelPrinters = getLabelPrinters();
    final defaultPrinter = _registry.getDefaultLabelPrinter();

    debugPrint('NativeLabelService: Total saved printers: ${allPrinters.length}');
    debugPrint('NativeLabelService: Label printers: ${labelPrinters.length}');
    debugPrint(
        'NativeLabelService: Default label printer: ${defaultPrinter?.userGivenName ?? 'NONE'}');

    debugPrint('NativeLabelService: All label printers:');
    for (int i = 0; i < labelPrinters.length; i++) {
      final printer = labelPrinters[i];
      debugPrint(
          'NativeLabelService:   [$i] ${printer.userGivenName} (${printer.brand}) '
          'default=${printer.isDefault} active=${printer.isActive}');
      debugPrint('NativeLabelService:       settings=${printer.settings}');
    }
    debugPrint('NativeLabelService: === END DEBUG ===');
  }

  /// Print [numOfLabels] copies of a single product's label.
  static Future<bool> printLabel({
    required Map<String, dynamic> product,
    required int numOfLabels,
    VoidCallback? onSuccess,
    VoidCallback? onError,
  }) {
    return printLabels(
      jobs: [LabelPrintJob(product: product, quantity: numOfLabels)],
      onSuccess: onSuccess,
      onError: onError,
    );
  }

  /// Print a queue of labels using the default label printer.
  ///
  /// The printer is connected and configured once, then every job prints
  /// sequentially so labels come out grouped per product rather than
  /// interleaved.
  ///
  /// Each job's `product` map is read as:
  ///
  /// ```jsonc
  /// {
  ///   "name": "Wool Scarf — Charcoal / M",
  ///   "price": "39.50",          // rendered with a leading $
  ///   "variant": "Charcoal / M", // optional; printed under the name
  ///   "barcode": "0123456789012"
  /// }
  /// ```
  ///
  /// [onProgress] reports `(labelsPrinted, totalLabels)` after each label.
  /// Returns true only if every queued label printed successfully; the batch
  /// stops at the first failure rather than continuing to feed stock into a
  /// printer that is jammed or out of labels.
  static Future<bool> printLabels({
    required List<LabelPrintJob> jobs,
    VoidCallback? onSuccess,
    VoidCallback? onError,
    void Function(int printed, int total)? onProgress,
  }) async {
    try {
      // Drop empty jobs so a zero quantity row never reaches the printer
      final queue = jobs.where((job) => job.quantity > 0).toList();
      final totalLabels = queue.fold<int>(0, (sum, job) => sum + job.quantity);

      if (queue.isEmpty) {
        debugPrint('NativeLabelService: No labels queued - nothing to print');
        onError?.call();
        return false;
      }

      debugPrint(
          'NativeLabelService: Starting label printing for $totalLabels label(s) '
          'across ${queue.length} job(s)...');

      final session = await _connectDefaultLabelPrinter();
      if (session == null) {
        onError?.call();
        return false;
      }

      final defaultPrinter = session.printer;
      int printed = 0;
      bool printSuccess = true;

      for (final job in queue) {
        // Each physical label carries quantity 1; the job's quantity is how
        // many identical labels to emit, not a number printed on the label.
        final labelData = mapProductToLabelData(job.product);
        debugPrint(
            'NativeLabelService: Label data for "${job.label}": '
            '${labelData.productName}, price: ${labelData.price}, barcode: ${labelData.barcode}');

        for (int i = 0; i < job.quantity; i++) {
          debugPrint(
              'NativeLabelService: Printing label ${i + 1} of ${job.quantity} for '
              '"${job.label}" (${printed + 1} of $totalLabels overall)...');
          printSuccess = await PrinterBridge.printLabel(
            defaultPrinter.brand,
            labelData,
            epsonWidth: session.epsonWidth,
          );

          if (!printSuccess) {
            debugPrint(
                'NativeLabelService: Label printing failed on label ${i + 1} for "${job.label}"');
            break;
          }

          printed++;
          onProgress?.call(printed, totalLabels);
        }

        if (!printSuccess) break;
      }

      if (printSuccess) {
        debugPrint(
            'NativeLabelService: All $totalLabels label(s) printed successfully on ${defaultPrinter.userGivenName}');
        onSuccess?.call();
        return true;
      }

      debugPrint(
          'NativeLabelService: Label printing failed after $printed of $totalLabels label(s)');
      PrinterFeedback.report(langCon.defaultLabelPrintFail);
      onError?.call();
      return false;
    } catch (e) {
      debugPrint('NativeLabelService: Label printing error: $e');
      PrinterFeedback.report(langCon.defaultLabelPrintFail);
      onError?.call();
      return false;
    }
  }

  /// Connect to the designated default label printer and apply its saved
  /// brand-specific settings. Returns null (after reporting) when unavailable.
  ///
  /// Note the ordering, which differs per vendor and is the whole reason this
  /// is one function: Star's paper width must be set before [PrinterBridge]
  /// opens the connection, Zebra's dimensions only make sense after it, and
  /// Epson's width is carried out to each print call instead.
  static Future<_LabelPrinterSession?> _connectDefaultLabelPrinter() async {
    final defaultPrinter = _registry.getDefaultLabelPrinter();

    if (defaultPrinter == null) {
      debugPrint(
          'NativeLabelService: No default label printer found - printing cannot proceed');
      PrinterFeedback.report(langCon.noDefaultLabelPrinter);
      return null;
    }

    debugPrint(
        'NativeLabelService: Using designated label printer: '
        '${defaultPrinter.userGivenName} (${defaultPrinter.brand})');
    debugPrint(
        'NativeLabelService: interface=${defaultPrinter.interface}, address=${defaultPrinter.address}');

    // Star: paper width must be primed before the connection opens.
    if (defaultPrinter.brand.toLowerCase() == 'star' &&
        defaultPrinter.settings.containsKey('paperWidth')) {
      final raw = defaultPrinter.settings['paperWidth'] as String? ?? '58mm';
      final paperWidthMm = int.tryParse(raw.replaceAll('mm', '')) ?? 58;
      PrinterBridge.starConfig.setPaperWidthMm(paperWidthMm);
      debugPrint(
          'NativeLabelService: Loaded Star paper width from saved settings: ${paperWidthMm}mm');
    }

    debugPrint('NativeLabelService: Attempting connection to ${defaultPrinter.userGivenName}...');
    final isConnected = await PrinterBridge.connect(
      defaultPrinter.brand,
      defaultPrinter.interface,
      defaultPrinter.address,
    );

    if (!isConnected) {
      debugPrint(
          'NativeLabelService: Failed to connect to designated label printer ${defaultPrinter.userGivenName}');
      debugPrint(
          'NativeLabelService: Check printer power, network connection, and address settings');
      PrinterFeedback.report(langCon.defaultLabelPrintFail);
      return null;
    }

    debugPrint('NativeLabelService: Successfully connected to ${defaultPrinter.userGivenName}');

    // Zebra: dimensions load after connecting. Flat and nested
    // (`detectedDimensions`) shapes both appear depending on wizard version.
    if (defaultPrinter.brand.toLowerCase() == 'zebra') {
      if (defaultPrinter.settings.containsKey('printWidthInDots') ||
          defaultPrinter.settings.containsKey('detectedDimensions')) {
        PrinterBridge.zebraConfig.fromMap(defaultPrinter.settings);
        debugPrint('NativeLabelService: Loaded Zebra dimensions from saved settings');
      }
    }

    // Epson: width travels to each print call rather than into config.
    String? epsonWidth;
    if (defaultPrinter.brand.toLowerCase() == 'epson' &&
        defaultPrinter.settings.containsKey('paperWidth')) {
      epsonWidth = defaultPrinter.settings['paperWidth'] as String?;
      debugPrint('NativeLabelService: Loaded Epson paper width from saved settings: $epsonWidth');
    }

    return _LabelPrinterSession(defaultPrinter, epsonWidth);
  }

  /// Builds a [PrinterLabelData] from a product map.
  ///
  /// An example adapter, like [NativeReceiptService.mapTransactionToReceiptData]
  /// — see [printLabels] for the map shape, or construct [PrinterLabelData]
  /// directly from your own model.
  static PrinterLabelData mapProductToLabelData(Map<String, dynamic> product) {
    final price = product['price']?.toString() ?? '0.00';
    return PrinterLabelData(
      productName: product['name']?.toString() ?? 'Unknown Product',
      price: '\$$price',
      colorSize: product['variant']?.toString() ?? '',
      barcode: product['barcode']?.toString() ?? '',
      quantity: 1,
    );
  }

  /// Test print on a saved label printer of [brand].
  ///
  /// Used by settings and edit screens, where the printer already exists in
  /// the registry. Pass [interface] and [address] to target one specific saved
  /// printer; omit them to use any active label printer of that brand.
  ///
  /// For the discovery wizard — where nothing is saved yet — use
  /// [testPrintFromWizard] instead.
  static Future<bool> testPrint({
    required String brand,
    String? interface,
    String? address,
    Map<String, int>? dimensions,
    String? epsonWidth,
  }) async {
    try {
      debugPrint('NativeLabelService: Test label print for saved $brand printer');

      final candidates = _registry.savedPrinters.where((p) =>
          p.brand.toLowerCase() == brand.toLowerCase() &&
          p.isLabel &&
          p.isActive &&
          (interface == null || p.interface == interface) &&
          (address == null || p.address == address));

      final savedPrinter = candidates.isEmpty ? null : candidates.first;
      if (savedPrinter == null) {
        debugPrint('NativeLabelService: No saved $brand label printer found');
        return false;
      }

      if (savedPrinter.brand.toLowerCase() == 'star' &&
          savedPrinter.settings.containsKey('paperWidth')) {
        final raw = savedPrinter.settings['paperWidth'] as String? ?? '58mm';
        final paperWidthMm = int.tryParse(raw.replaceAll('mm', '')) ?? 58;
        PrinterBridge.starConfig.setPaperWidthMm(paperWidthMm);
        debugPrint('NativeLabelService: Set Star paper width to ${paperWidthMm}mm');
      }

      // Explicit arguments win over saved settings, so a caller testing a
      // value the operator has not committed yet sees that value.
      dimensions ??= _savedZebraDimensions(savedPrinter);
      if (savedPrinter.brand.toLowerCase() == 'epson' &&
          epsonWidth == null &&
          savedPrinter.settings.containsKey('paperWidth')) {
        epsonWidth = savedPrinter.settings['paperWidth'] as String?;
      }

      debugPrint('NativeLabelService: Connecting to ${savedPrinter.userGivenName}...');
      final isConnected = await PrinterBridge.connect(
        savedPrinter.brand,
        savedPrinter.interface,
        savedPrinter.address,
      );

      if (!isConnected) {
        debugPrint('NativeLabelService: Connection failed');
        return false;
      }

      final success = await PrinterBridge.printLabel(
        brand,
        _testLabelData,
        dimensions: dimensions,
        epsonWidth: epsonWidth,
      );
      debugPrint(success
          ? 'NativeLabelService: Test label printed'
          : 'NativeLabelService: Print failed');
      return success;
    } catch (e) {
      debugPrint('NativeLabelService: Test label error: $e');
      return false;
    }
  }

  /// Reads [printer]'s saved Zebra dimensions, in either storage shape.
  static Map<String, int>? _savedZebraDimensions(SavedPrinter printer) {
    if (printer.brand.toLowerCase() != 'zebra') return null;

    Map<String, dynamic>? dims;
    if (printer.settings.containsKey('printWidthInDots')) {
      dims = printer.settings;
    } else if (printer.settings['detectedDimensions'] is Map<String, dynamic>) {
      dims = printer.settings['detectedDimensions'] as Map<String, dynamic>;
    }
    if (dims == null || !dims.containsKey('printWidthInDots')) return null;

    debugPrint(
        'NativeLabelService: Loaded Zebra dimensions from ${printer.userGivenName} settings');
    return {
      'printWidthInDots': (dims['printWidthInDots'] as num).toInt(),
      'labelLengthInDots': (dims['labelLengthInDots'] as num).toInt(),
      'dpi': (dims['dpi'] as num).toInt(),
    };
  }

  /// Test print from a discovery-wizard configuration page.
  ///
  /// Takes raw detected values and consults neither the registry nor saved
  /// settings: at this point the operator is still deciding, and the whole
  /// point is to print with what is on screen rather than what was stored.
  static Future<bool> testPrintFromWizard({
    required String brand,
    required String interface,
    required String address,
    String? epsonWidth, // e.g. '80mm'
    int? starWidthMm, // e.g. 58
    Map<String, int>? zebraDimensions, // {printWidthInDots, labelLengthInDots, dpi}
  }) async {
    try {
      debugPrint('NativeLabelService: Wizard test label: brand=$brand, interface=$interface');

      if (brand.toLowerCase() == 'star' && starWidthMm != null) {
        PrinterBridge.starConfig.setPaperWidthMm(starWidthMm);
      }

      debugPrint('NativeLabelService: Connecting to $brand at $address via $interface...');
      final isConnected = await PrinterBridge.connect(brand, interface, address);

      if (!isConnected) {
        debugPrint('NativeLabelService: Connection failed');
        return false;
      }

      final success = await PrinterBridge.printLabel(
        brand,
        _testLabelData,
        dimensions: zebraDimensions,
        epsonWidth: epsonWidth,
      );
      debugPrint(success
          ? 'NativeLabelService: Wizard test label printed'
          : 'NativeLabelService: Print failed');
      return success;
    } catch (e) {
      debugPrint('NativeLabelService: Wizard test label error: $e');
      return false;
    }
  }

  /// Sample label exercising every field a real label uses, so a test print
  /// reveals a truncated name or an unscannable barcode.
  static PrinterLabelData get _testLabelData => PrinterLabelData(
        productName: 'Test Product Label',
        price: '\$29.99',
        colorSize: 'Medium Blue',
        barcode: '1234567890',
        quantity: 1,
      );
}
