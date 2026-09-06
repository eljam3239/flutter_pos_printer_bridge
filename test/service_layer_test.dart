import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_pos_printer_bridge/native_label_service.dart';
import 'package:flutter_pos_printer_bridge/native_receipt_service.dart';
import 'package:flutter_pos_printer_bridge/printer_host.dart';
import 'package:flutter_pos_printer_bridge/printer_localizations.dart';

SavedPrinter _printer({
  String id = 'p1',
  String brand = 'star',
  bool isReceipt = true,
  bool isLabel = false,
  bool isDefault = true,
  bool isActive = true,
  Map<String, dynamic>? settings,
}) {
  return SavedPrinter(
    id: id,
    userGivenName: 'Counter',
    brand: brand,
    interface: 'tcp',
    address: '192.168.1.50',
    model: 'TSP100',
    isReceipt: isReceipt,
    isLabel: isLabel,
    settings: settings ?? {},
    isDefault: isDefault,
    isActive: isActive,
  );
}

void main() {
  setUp(() {
    PrinterRegistry.instance = PrinterRegistry();
    StoreIdentity.current = const StoreIdentity();
    PrinterLocalizations.current = const PrinterLocalizations('en');
  });

  group('PrinterRegistry', () {
    test('resolves defaults per role, not globally', () {
      final registry = PrinterRegistry.instance
        ..addPrinter(_printer(id: 'receipt', isReceipt: true, isLabel: false))
        ..addPrinter(_printer(
            id: 'label', brand: 'zebra', isReceipt: false, isLabel: true));

      expect(registry.getDefaultReceiptPrinter()?.id, 'receipt');
      expect(registry.getDefaultLabelPrinter()?.id, 'label');
    });

    test('a new default displaces the previous one for that role only', () {
      final registry = PrinterRegistry.instance
        ..addPrinter(_printer(id: 'old', isReceipt: true, isLabel: false))
        ..addPrinter(_printer(
            id: 'label', brand: 'zebra', isReceipt: false, isLabel: true))
        ..addPrinter(_printer(id: 'new', isReceipt: true, isLabel: false));

      expect(registry.getDefaultReceiptPrinter()?.id, 'new');
      // The label printer kept its default flag.
      expect(registry.getDefaultLabelPrinter()?.id, 'label');
    });

    test('inactive printers are never returned as default', () {
      PrinterRegistry.instance.addPrinter(_printer(isActive: false));
      expect(PrinterRegistry.instance.getDefaultReceiptPrinter(), isNull);
    });

    test('re-adding the same id replaces rather than duplicates', () {
      PrinterRegistry.instance
        ..addPrinter(_printer(id: 'p1'))
        ..addPrinter(_printer(id: 'p1'));
      expect(PrinterRegistry.instance.savedPrinters.length, 1);
    });
  });

  group('printing without a default printer', () {
    test('receipt print reports and fails rather than picking any printer', () async {
      // An active receipt printer exists, but none is marked default.
      PrinterRegistry.instance.addPrinter(_printer(isDefault: false));

      String? reported;
      PrinterFeedback.onMessage = (m) => reported = m;
      addTearDown(() => PrinterFeedback.onMessage = null);

      var errored = false;
      final ok = await NativeReceiptService.printReceipt(
        {'order_no': '1'},
        onError: () => errored = true,
      );

      expect(ok, isFalse);
      expect(errored, isTrue);
      expect(reported, PrinterLocalizations.current.noDefaultReceiptPrinter);
    });

    test('label print reports and fails', () async {
      String? reported;
      PrinterFeedback.onMessage = (m) => reported = m;
      addTearDown(() => PrinterFeedback.onMessage = null);

      final ok = await NativeLabelService.printLabel(
        product: {'name': 'Scarf'},
        numOfLabels: 2,
      );

      expect(ok, isFalse);
      expect(reported, PrinterLocalizations.current.noDefaultLabelPrinter);
    });

    test('an empty label queue fails before touching a printer', () async {
      final ok = await NativeLabelService.printLabels(
        jobs: [LabelPrintJob(product: {'name': 'Scarf'}, quantity: 0)],
      );
      expect(ok, isFalse);
    });
  });

  group('mapTransactionToReceiptData', () {
    Map<String, dynamic> transaction() => {
          'order_no': '1042',
          'order_date': '2026-09-05T14:31:00Z',
          'lane_no': 2,
          'cashier_name': 'Sam',
          'store_organization_name': 'Alpine Goods',
          'store_location_address': '412 Queen St W',
          'store_organization_footer': 'Returns within 30 days',
          'order_components': [
            {
              'product_name': 'Wool Scarf',
              'product_qty': 2,
              'product_subtotal': 79.00,
              'type': 'purchase',
            },
            {
              'product_name': 'Returned Hat',
              'product_qty': -1,
              'product_subtotal': -20.00,
              'type': 'purchase',
            },
            {
              'product_name': 'Trade-in Jacket',
              'product_qty': 1,
              'product_subtotal': 15.00,
              'type': 'trade-in',
            },
          ],
          'order_tax_breakdown': [
            {'tax_name': 'HST', 'tax_amount': 10.27},
            {'tax_name': 'GST', 'tax_amount': 2.00},
          ],
          'order_subtotal': 79.00,
          'order_discount': 5.00,
          'order_total': 89.27,
          'order_payments': [
            {'payment_type': 'cash', 'payment_amount': 40.00},
            {
              'payment_type': 'card',
              'payment_amount': 49.27,
              'metadata': {
                'card_brand': 'VISA',
                'card_mask4': '4242',
                'auth_code': 'A1B2C3',
              },
            },
          ],
        };

    test('splits components into purchases, returns and exchanges', () {
      final data = NativeReceiptService.mapTransactionToReceiptData(transaction());

      expect(data.items.map((i) => i.itemName), ['Wool Scarf']);
      expect(data.returnItems!.map((i) => i.itemName), ['Returned Hat']);
      expect(data.exchangeItems!.map((i) => i.itemName), ['Trade-in Jacket']);
    });

    test('derives unit price from subtotal and quantity', () {
      final data = NativeReceiptService.mapTransactionToReceiptData(transaction());
      expect(data.items.single.quantity, 2);
      expect(data.items.single.unitPrice, 39.50);
      expect(data.items.single.totalPrice, 79.00);
    });

    test('return items carry a positive unit price and negative total', () {
      final data = NativeReceiptService.mapTransactionToReceiptData(transaction());
      final returned = data.returnItems!.single;
      expect(returned.unitPrice, 20.00);
      expect(returned.totalPrice, -20.00);
    });

    test('collects the tax breakdown by name', () {
      final data = NativeReceiptService.mapTransactionToReceiptData(transaction());
      expect(data.taxes, {'HST': 10.27, 'GST': 2.00});
    });

    test('maps payments and attaches terminal metadata only where present', () {
      final data = NativeReceiptService.mapTransactionToReceiptData(transaction());

      expect(data.payments!.length, 2);
      expect(data.payments![0].method, PrinterLocalizations.current.cash);
      expect(data.payments![0].metadata, isNull);

      final card = data.payments![1];
      expect(card.method, PrinterLocalizations.current.card);
      expect(card.metadata!.cardBrand, 'VISA');
      expect(card.metadata!.cardMask4, '4242');
      // Defaults hold when the acquirer says nothing about display rules.
      expect(card.metadata!.showEmvTags, isTrue);
      expect(card.metadata!.showAmountBreakdown, isFalse);
    });

    test('gift receipts omit every monetary field', () {
      final data = NativeReceiptService.mapTransactionToReceiptData(
        transaction(),
        isGiftReceipt: true,
      );

      expect(data.isGiftReceipt, isTrue);
      expect(data.subtotal, isNull);
      expect(data.discounts, isNull);
      expect(data.taxes, isNull);
      expect(data.total, isNull);
      expect(data.payments, isNull);
      // Items still print — the recipient needs to know what to exchange.
      expect(data.items, isNotEmpty);
    });

    test('falls back to StoreIdentity when the transaction omits store info', () {
      StoreIdentity.current = const StoreIdentity(
        organizationName: 'Fallback Co',
        locationAddress: '1 Main St',
      );

      final data = NativeReceiptService.mapTransactionToReceiptData({});
      expect(data.storeName, 'Fallback Co');
      expect(data.storeAddress, '1 Main St');
    });

    test('survives a transaction with no components, taxes or payments', () {
      final data = NativeReceiptService.mapTransactionToReceiptData({
        'order_no': '7',
        'order_components': [],
      });

      expect(data.items, isEmpty);
      expect(data.returnItems, isNull);
      expect(data.exchangeItems, isNull);
      expect(data.taxes, isNull);
      expect(data.payments, isNull);
      expect(data.receiptNumber, '7');
    });

    test('treats a zero quantity as one rather than a free item', () {
      final data = NativeReceiptService.mapTransactionToReceiptData({
        'order_components': [
          {'product_name': 'Odd', 'product_qty': 0, 'product_subtotal': 10.00},
        ],
      });
      expect(data.items.single.quantity, 1);
      expect(data.items.single.unitPrice, 10.00);
    });

    test('reads numbers that arrive as strings', () {
      final data = NativeReceiptService.mapTransactionToReceiptData({
        'order_components': [
          {'product_name': 'Str', 'product_qty': '3', 'product_subtotal': '30.00'},
        ],
        'order_total': '30.00',
      });
      expect(data.items.single.quantity, 3);
      expect(data.items.single.unitPrice, 10.00);
      expect(data.total, 30.00);
    });
  });

  group('mapProductToLabelData', () {
    test('maps the documented shape', () {
      final label = NativeLabelService.mapProductToLabelData({
        'name': 'Wool Scarf',
        'price': '39.50',
        'variant': 'Charcoal / M',
        'barcode': '0123456789012',
      });

      expect(label.productName, 'Wool Scarf');
      expect(label.price, r'$39.50');
      expect(label.colorSize, 'Charcoal / M');
      expect(label.barcode, '0123456789012');
      expect(label.quantity, 1);
    });

    test('falls back rather than throwing on an empty product', () {
      final label = NativeLabelService.mapProductToLabelData({});
      expect(label.productName, 'Unknown Product');
      expect(label.price, r'$0.00');
      expect(label.barcode, '');
    });
  });

  group('PrinterLocalizations', () {
    test('withPrintLanguage scopes strings and restores them', () async {
      expect(langCon.receipt, PrinterLocalizations.current.receipt);

      late String inside;
      await PrinterLocalizations.withPrintLanguage('fr', () async {
        inside = langCon.receipt;
      });

      expect(inside, const PrinterLocalizations('fr').receipt);
      expect(langCon.languageCode, 'en');
    });

    test('an unknown language code falls back to English, not blanks', () {
      const unknown = PrinterLocalizations('zz');
      expect(unknown.receipt, const PrinterLocalizations('en').receipt);
      expect(unknown.receipt, isNotEmpty);
    });
  });
}
