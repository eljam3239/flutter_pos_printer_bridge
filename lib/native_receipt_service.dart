import 'package:flutter/foundation.dart';

import 'printer_bridge.dart';
import 'printer_host.dart';
import 'printer_localizations.dart';

/// Receipt printing against the operator's configured default printer.
///
/// This is the layer between "a transaction happened" and [PrinterBridge].
/// [PrinterBridge] knows how to render a [PrinterReceiptData] on three vendors'
/// SDKs; it deliberately knows nothing about which printer to use or how that
/// printer was configured. That is this service's job:
///
///  1. resolve the default receipt printer, failing loudly when none is set
///  2. prime the brand's configuration *before* connecting — each vendor wants
///     its paper geometry at a different point in the lifecycle
///  3. connect, print, and report failure through [PrinterFeedback]
///
/// Step 2 is the part worth reading. The three SDKs disagree about when
/// geometry can be set: Star's paper width must be pushed into
/// [PrinterBridge.starConfig] *before* the connection is opened, Zebra's label
/// dimensions can only be loaded *after* (the connection is what makes the
/// saved values meaningful), and Epson's width is not configuration at all —
/// it is an argument threaded through to the print call. Getting this ordering
/// wrong produces receipts that are silently the wrong width rather than an
/// error, which is why it is centralized here instead of at each call site.
class NativeReceiptService {
  static PrinterRegistry get _registry => PrinterRegistry.instance;

  static double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int _asInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  /// Get available receipt printers
  static List<SavedPrinter> getReceiptPrinters() {
    return _registry.savedPrinters
        .where((printer) => printer.isReceipt && printer.isActive)
        .toList();
  }

  /// Check if any receipt printers are available
  static bool get hasReceiptPrinters => getReceiptPrinters().isNotEmpty;

  /// Check if default receipt printer is available
  static bool get hasDefaultReceiptPrinter =>
      _registry.getDefaultReceiptPrinter() != null;

  /// Debug method: Print current printer configuration for troubleshooting
  static void debugPrintConfiguration() {
    debugPrint('NativeReceiptService: === PRINTER CONFIGURATION DEBUG ===');

    final allPrinters = _registry.savedPrinters;
    final receiptPrinters = getReceiptPrinters();
    final defaultPrinter = _registry.getDefaultReceiptPrinter();

    debugPrint('NativeReceiptService: Total saved printers: ${allPrinters.length}');
    debugPrint('NativeReceiptService: Receipt printers: ${receiptPrinters.length}');
    debugPrint(
        'NativeReceiptService: Default receipt printer: ${defaultPrinter?.userGivenName ?? 'NONE'}');

    debugPrint('NativeReceiptService: All receipt printers:');
    for (int i = 0; i < receiptPrinters.length; i++) {
      final printer = receiptPrinters[i];
      debugPrint(
          'NativeReceiptService:   [$i] ${printer.userGivenName} (${printer.brand}) '
          'default=${printer.isDefault} active=${printer.isActive}');
      debugPrint('NativeReceiptService:       settings=${printer.settings}');
    }
    debugPrint('NativeReceiptService: === END DEBUG ===');
  }

  /// Print gift receipt with PrinterBridge integration
  /// Convenience method for printing gift receipts specifically
  static Future<bool> printGiftReceipt(
    Map<String, dynamic> transaction, {
    VoidCallback? onSuccess,
    VoidCallback? onError,
  }) {
    return printReceipt(
      transaction,
      onSuccess: onSuccess,
      onError: onError,
      isGiftReceipt: true,
    );
  }

  /// Print a receipt for [transaction] on the default receipt printer.
  ///
  /// Requires a default receipt printer to be set — there is deliberately no
  /// fallback to "some other printer". A receipt silently emerging from the
  /// stockroom label printer is worse than a receipt that did not print, and
  /// the operator gets told either way via [PrinterFeedback].
  ///
  /// See [mapTransactionToReceiptData] for the shape of [transaction].
  static Future<bool> printReceipt(
    Map<String, dynamic> transaction, {
    VoidCallback? onSuccess,
    VoidCallback? onError,
    bool isGiftReceipt = false,
  }) async {
    try {
      debugPrint(
          'NativeReceiptService: Printing ${isGiftReceipt ? 'gift ' : ''}receipt');

      // Check for default receipt printer - fail immediately if not set
      final defaultPrinter = _registry.getDefaultReceiptPrinter();
      if (defaultPrinter == null) {
        debugPrint('NativeReceiptService: No default receipt printer configured');
        PrinterFeedback.report(langCon.noDefaultReceiptPrinter);
        onError?.call();
        return false;
      }

      // A transaction may carry its own logo (a receipt reprinted months later
      // should show the branding it was issued under, not today's), otherwise
      // fall back to the host's current organization logo.
      String? logoBase64;
      try {
        final displayFormat = transaction['display_format'];
        final transactionLogo = displayFormat is Map
            ? displayFormat['org_logo']?.toString()
            : null;
        logoBase64 = await PrinterLogoSource.get(
          url: (transactionLogo != null && transactionLogo.isNotEmpty)
              ? transactionLogo
              : null,
        );
      } catch (e) {
        debugPrint('NativeReceiptService: Failed to get organization logo: $e');
      }

      final receiptData = mapTransactionToReceiptData(
        transaction,
        logoBase64: logoBase64,
        isGiftReceipt: isGiftReceipt,
      );

      debugPrint(
          'NativeReceiptService: Printing with default receipt printer: '
          '${defaultPrinter.userGivenName} (${defaultPrinter.brand})');
      final success = await _printWithDefaultPrinter(receiptData, defaultPrinter);
      if (success) {
        debugPrint(
            'NativeReceiptService: ${isGiftReceipt ? 'Gift r' : 'R'}eceipt printed successfully');
        onSuccess?.call();
        return true;
      }
      debugPrint(
          'NativeReceiptService: Print failed on default printer ${defaultPrinter.userGivenName}');
      onError?.call();
      return false;
    } catch (e) {
      debugPrint('NativeReceiptService: Receipt printing error: $e');
      onError?.call();
      return false;
    }
  }

  /// Print a standalone card-terminal transaction slip (Merchant or Client
  /// copy) — no order or line items involved, just the transaction record.
  ///
  /// Requires a default receipt printer to be set, same as [printReceipt].
  /// See [PrinterPaymentMetadata.fromMap] for the shape of [metadata].
  static Future<bool> printTerminalReceipt({
    required Map<String, dynamic> metadata,
    required String saleContext,
    required String receiptFor,
    bool isDeclined = false,
    VoidCallback? onSuccess,
    VoidCallback? onError,
  }) async {
    try {
      final defaultPrinter = _registry.getDefaultReceiptPrinter();
      if (defaultPrinter == null) {
        debugPrint('NativeReceiptService: No default receipt printer configured');
        PrinterFeedback.report(langCon.noDefaultReceiptPrinter);
        onError?.call();
        return false;
      }

      // There is no transaction here to pull a per-receipt logo from, so this
      // always uses the host's current organization logo.
      String? logoBase64;
      try {
        logoBase64 = await PrinterLogoSource.get();
      } catch (e) {
        debugPrint('NativeReceiptService: Failed to get organization logo: $e');
      }

      final store = StoreIdentity.current;
      final terminalData = PrinterTerminalReceiptData(
        storeName: store.displayName,
        storeAddress: store.displayAddress,
        logoBase64: logoBase64,
        metadata: PrinterPaymentMetadata.fromMap(metadata),
        saleContext: saleContext,
        receiptFor: receiptFor,
        isDeclined: isDeclined,
      );

      final success = await _printTerminalReceiptWithDefaultPrinter(
          terminalData, defaultPrinter);
      if (success) {
        debugPrint('NativeReceiptService: Terminal receipt printed successfully');
        onSuccess?.call();
        return true;
      }
      debugPrint(
          'NativeReceiptService: Terminal print failed on default printer ${defaultPrinter.userGivenName}');
      onError?.call();
      return false;
    } catch (e) {
      debugPrint('NativeReceiptService: Terminal receipt printing error: $e');
      onError?.call();
      return false;
    }
  }

  /// Convert a stored payment type to its localized display name.
  static String _getPaymentTypeDisplayName(String paymentType) {
    switch (paymentType.toLowerCase()) {
      case 'card':
        return langCon.card;
      case 'cheque':
        return langCon.cheque;
      case 'cash':
        return langCon.cash;
      case 'credit':
        return langCon.credit;
      case 'debit':
        return langCon.debit;
      case 'giftcard':
        return langCon.giftCard;
      case 'storecredit':
        return langCon.storeCredit;
      case 'loyalty':
      case 'loyaltypoints':
        return langCon.loyaltyPoints;
      case 'none':
        return 'None';
      default:
        return paymentType; // Fallback to original if no translation
    }
  }

  // --- Brand configuration ---------------------------------------------------

  /// Pushes [printer]'s saved Star paper width into [PrinterBridge.starConfig].
  ///
  /// Must run *before* connecting: the width participates in the column
  /// calculation the Star SDK performs at connection time.
  static void _primeStarConfig(SavedPrinter printer) {
    if (printer.brand.toLowerCase() != 'star') return;

    // Two settings shapes are in the wild: older records store an int
    // `paperWidthMm`, newer ones a string `paperWidth` like "58mm". Both are
    // read rather than migrated, so a printer configured under either version
    // keeps working.
    int paperWidthMm = 58;
    if (printer.settings.containsKey('paperWidthMm')) {
      // (num).toInt() rather than a cast: JSON round-trips may widen to double.
      paperWidthMm = (printer.settings['paperWidthMm'] as num?)?.toInt() ?? 58;
    } else if (printer.settings.containsKey('paperWidth')) {
      final raw = printer.settings['paperWidth'] as String? ?? '58mm';
      paperWidthMm = int.tryParse(raw.replaceAll('mm', '')) ?? 58;
    }

    PrinterBridge.starConfig.setPaperWidthMm(paperWidthMm);
    debugPrint(
        'NativeReceiptService: Set Star paper width to ${paperWidthMm}mm for ${printer.userGivenName}');
  }

  /// Epson's paper width is a print-call argument, not global configuration.
  static String? _epsonWidthFor(SavedPrinter printer) {
    if (printer.brand.toLowerCase() != 'epson') return null;
    if (!printer.settings.containsKey('paperWidth')) return null;
    final width = printer.settings['paperWidth'] as String? ?? '80mm';
    debugPrint(
        'NativeReceiptService: Loaded Epson paper width from saved settings: $width');
    return width;
  }

  /// Loads [printer]'s saved Zebra dimensions. Must run *after* connecting.
  static void _loadZebraDimensions(SavedPrinter printer) {
    if (printer.brand.toLowerCase() != 'zebra') return;
    // Flat and nested (`detectedDimensions`) shapes both appear, depending on
    // which version of the discovery wizard wrote the record.
    if (printer.settings.containsKey('printWidthInDots') ||
        printer.settings.containsKey('detectedDimensions')) {
      PrinterBridge.zebraConfig.fromMap(printer.settings);
      debugPrint('NativeReceiptService: Loaded Zebra dimensions from saved settings');
    }
  }

  /// The printer's own configured receipt language, independent of the app's.
  static String _printLanguageFor(SavedPrinter printer) =>
      printer.settings['printLanguage'] as String? ?? 'en';

  /// Print with the specified default printer only - no fallback
  static Future<bool> _printWithDefaultPrinter(
      PrinterReceiptData receiptData, SavedPrinter defaultPrinter) async {
    try {
      debugPrint(
          'NativeReceiptService: Printing with default receipt printer: '
          '${defaultPrinter.userGivenName} (${defaultPrinter.brand})');

      _primeStarConfig(defaultPrinter);
      final epsonWidth = _epsonWidthFor(defaultPrinter);

      final isConnected = await PrinterBridge.connect(
        defaultPrinter.brand,
        defaultPrinter.interface,
        defaultPrinter.address,
      );

      if (!isConnected) {
        debugPrint(
            'NativeReceiptService: Failed to connect to default printer ${defaultPrinter.userGivenName}');
        PrinterFeedback.report(langCon.defaultReceiptPrintFail);
        return false;
      }

      debugPrint(
          'NativeReceiptService: Connected to ${defaultPrinter.userGivenName}, attempting print...');
      _loadZebraDimensions(defaultPrinter);

      final success = await PrinterBridge.printReceipt(
        defaultPrinter.brand,
        receiptData,
        epsonWidth: epsonWidth,
        printLanguage: _printLanguageFor(defaultPrinter),
      );

      if (!success) {
        debugPrint(
            'NativeReceiptService: Print failed on default printer ${defaultPrinter.userGivenName}');
        PrinterFeedback.report(langCon.defaultReceiptPrintFail);
        return false;
      }

      debugPrint(
          'NativeReceiptService: Successfully printed with ${defaultPrinter.userGivenName}');
      return true;
    } catch (e) {
      debugPrint(
          'NativeReceiptService: Error with default printer ${defaultPrinter.userGivenName}: $e');
      PrinterFeedback.report(langCon.defaultReceiptPrintFail);
      return false;
    }
  }

  /// Print a terminal slip with the specified default printer only - no
  /// fallback. Mirrors [_printWithDefaultPrinter]'s brand-config-priming +
  /// connect + print pattern.
  static Future<bool> _printTerminalReceiptWithDefaultPrinter(
      PrinterTerminalReceiptData terminalData,
      SavedPrinter defaultPrinter) async {
    try {
      _primeStarConfig(defaultPrinter);
      final epsonWidth = _epsonWidthFor(defaultPrinter);

      final isConnected = await PrinterBridge.connect(
        defaultPrinter.brand,
        defaultPrinter.interface,
        defaultPrinter.address,
      );

      if (!isConnected) {
        debugPrint(
            'NativeReceiptService: Failed to connect to default printer ${defaultPrinter.userGivenName}');
        PrinterFeedback.report(langCon.defaultReceiptPrintFail);
        return false;
      }

      _loadZebraDimensions(defaultPrinter);

      final success = await PrinterBridge.printTerminalReceipt(
        defaultPrinter.brand,
        terminalData,
        epsonWidth: epsonWidth,
        printLanguage: _printLanguageFor(defaultPrinter),
      );

      if (!success) {
        debugPrint(
            'NativeReceiptService: Terminal print failed on default printer ${defaultPrinter.userGivenName}');
        PrinterFeedback.report(langCon.defaultReceiptPrintFail);
        return false;
      }

      return true;
    } catch (e) {
      debugPrint(
          'NativeReceiptService: Error printing terminal receipt with ${defaultPrinter.userGivenName}: $e');
      PrinterFeedback.report(langCon.defaultReceiptPrintFail);
      return false;
    }
  }

  // --- Transaction mapping ---------------------------------------------------

  /// Builds a [PrinterReceiptData] from a transaction map.
  ///
  /// This is an *example* adapter. Every POS backend describes a sale
  /// differently, so rather than impose a model, the service layer accepts a
  /// plain map in the shape below and hosts adapt their own schema to it — or
  /// skip this method entirely and construct [PrinterReceiptData] directly.
  ///
  /// ```jsonc
  /// {
  ///   "order_no": "1042",
  ///   "order_date": "2026-09-05T14:31:00Z",   // ISO 8601
  ///   "lane_no": 2,
  ///   "cashier_name": "Sam",
  ///   "store_location": "Queen St. West",
  ///   "store_location_address": "412 Queen St W, Toronto",
  ///   "store_organization_name": "Alpine Goods",
  ///   "store_organization_footer": "Returns accepted within 30 days",
  ///   "display_format": { "org_logo": "https://…" },  // optional override
  ///
  ///   "order_components": [
  ///     // type: "purchase" (default) | "exchange" | "trade-in"
  ///     // a negative product_qty marks a returned item
  ///     { "product_name": "Wool Scarf", "product_qty": 2,
  ///       "product_subtotal": 79.00, "type": "purchase" }
  ///   ],
  ///
  ///   "order_tax_breakdown": [ { "tax_name": "HST", "tax_amount": 10.27 } ],
  ///   "order_subtotal": 79.00,
  ///   "order_discount": 0.00,
  ///   "order_total": 89.27,
  ///
  ///   "order_payments": [
  ///     // amount is signed: negative for a refund
  ///     // metadata is optional; when present the receipt renders a full
  ///     // card/EMV block instead of a one-line method → amount entry
  ///     { "payment_type": "card", "payment_amount": 89.27,
  ///       "metadata": { /* see PrinterPaymentMetadata.fromMap */ } }
  ///   ]
  /// }
  /// ```
  ///
  /// Gift receipts omit prices and payments entirely — the recipient should be
  /// able to exchange an item without learning what was paid for it.
  static PrinterReceiptData mapTransactionToReceiptData(
    Map<String, dynamic> transaction, {
    String? logoBase64,
    bool isGiftReceipt = false,
  }) {
    // Line items fall into three buckets, distinguished by type and sign:
    // regular purchases, returns (negative quantity), and exchanges/trade-ins
    // which offset the total rather than adding to it.
    final items = <PrinterLineItem>[];
    final returnItems = <PrinterReturnLineItem>[];
    final exchangeItems = <PrinterLineItem>[];

    final components = transaction['order_components'];
    if (components is List) {
      for (final component in components) {
        if (component is! Map) continue;

        final rawQty = _asInt(component['product_qty'], fallback: 1);
        // A zero quantity is a data error, not a free item; treat it as one.
        final qty = rawQty == 0 ? 1 : rawQty.abs();
        final name = component['product_name']?.toString() ?? 'Unknown Item';
        final type = component['type']?.toString() ?? 'purchase';
        final subtotal = _asDouble(component['product_subtotal']);
        final unitPrice = qty > 0 ? subtotal / qty : subtotal;

        if (type == 'exchange' || type == 'trade-in') {
          exchangeItems.add(PrinterLineItem(
            itemName: name,
            quantity: qty,
            unitPrice: unitPrice,
            totalPrice: subtotal,
          ));
        } else if (rawQty < 0) {
          returnItems.add(PrinterReturnLineItem(
            itemName: name,
            quantity: qty,
            unitPrice: unitPrice.abs(),
          ));
        } else {
          items.add(PrinterLineItem(
            itemName: name,
            quantity: qty,
            unitPrice: unitPrice,
            totalPrice: subtotal,
          ));
        }
      }
    }

    // Tax names are data, not an enum: jurisdictions differ (HST/GST/PST/VAT)
    // and a store may be subject to several at once.
    final taxes = <String, double>{};
    final taxBreakdown = transaction['order_tax_breakdown'];
    if (taxBreakdown is List) {
      for (final tax in taxBreakdown) {
        if (tax is! Map) continue;
        final name = tax['tax_name']?.toString();
        if (name == null || name.isEmpty) continue;
        taxes[name] = (taxes[name] ?? 0) + _asDouble(tax['tax_amount']);
      }
    }

    final payments = <PrinterPayment>[];
    final orderPayments = transaction['order_payments'];
    if (!isGiftReceipt && orderPayments is List) {
      for (final payment in orderPayments) {
        if (payment is! Map) continue;
        final metadata = payment['metadata'];
        payments.add(PrinterPayment(
          method: _getPaymentTypeDisplayName(
              payment['payment_type']?.toString() ?? ''),
          amount: _asDouble(payment['payment_amount']),
          metadata: metadata is Map
              ? PrinterPaymentMetadata.fromMap(
                  Map<String, dynamic>.from(metadata))
              : null,
        ));
      }
    }

    final orderDate =
        DateTime.tryParse(transaction['order_date']?.toString() ?? '');
    final date = orderDate ?? DateTime.now();

    final store = StoreIdentity.current;
    final storeName = transaction['store_organization_name']?.toString() ??
        transaction['store_location']?.toString() ??
        store.displayName;
    final storeAddress =
        transaction['store_location_address']?.toString() ??
            store.displayAddress;
    final footer = transaction['store_organization_footer']?.toString() ??
        store.organizationFooter ??
        langCon.backupStoreLocationFooter;

    return PrinterReceiptData(
      storeName: storeName,
      storeAddress: storeAddress,
      date: '${date.year}-${_two(date.month)}-${_two(date.day)}',
      time: '${_two(date.hour)}:${_two(date.minute)}',
      cashierName: transaction['cashier_name']?.toString(),
      receiptNumber: transaction['order_no']?.toString(),
      laneNumber: transaction['lane_no']?.toString(),
      items: items,
      returnItems: returnItems.isEmpty ? null : returnItems,
      exchangeItems: exchangeItems.isEmpty ? null : exchangeItems,
      thankYouMessage: footer,
      logoBase64: logoBase64,
      transactionDate: date,
      receiptTitle: isGiftReceipt ? langCon.giftReceipt : langCon.receipt,
      isGiftReceipt: isGiftReceipt,
      // Gift receipts carry no monetary summary at all.
      subtotal: isGiftReceipt ? null : _asDouble(transaction['order_subtotal']),
      discounts: isGiftReceipt ? null : _asDouble(transaction['order_discount']),
      taxes: isGiftReceipt || taxes.isEmpty ? null : taxes,
      total: isGiftReceipt ? null : _asDouble(transaction['order_total']),
      payments: payments.isEmpty ? null : payments,
    );
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}
