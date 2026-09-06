# Flutter POS Printer Bridge

A Flutter application for cross-platform thermal receipt and label printing using **Epson**, **Star Micronics**, and **Zebra** printer SDKs behind a single unified interface. Covers multi-brand discovery, connection management, receipt/label formatting, and cash drawer control across iOS and Android.

This repository follows Flutter's federated [plugin architecture](https://docs.flutter.dev/packages-and-plugins/developing-packages#federated-plugins), combining three printer SDK wrappers into one POS printing solution.

## Features

- **Multi-brand printer support** (Epson TM Series, Star TSP/mPOP Series, Zebra ZD/ZQ Series)
- **Cross-platform discovery** (TCP/LAN, USB, Bluetooth/BLE)
- **Automatic paper width detection** with manual override
- **Receipt printing** with dynamic formatting based on paper width
- **Returns, exchanges/trade-ins, and split payment breakdowns**
- **Gift receipts** with prices suppressed
- **Card terminal slips** with EMV detail (client/merchant copy)
- **Label printing** with barcode generation, text styling, and batch quantity
- **Receipt localization** in English, French, Spanish, and Italian
- **Logo/image printing** and **cash drawer integration**
- **Dynamic ZPL generation** for Zebra printers

---

## Getting Started

### Prerequisites

- Flutter SDK (latest stable) — [install guide](https://docs.flutter.dev/get-started/quick)
- iOS: Xcode 14+
- Android: Android Studio with SDK 21+
- A physical thermal printer from a supported brand

### Installation

```bash
git clone git@github.com:eljam3239/flutter_pos_printer_bridge.git
cd flutter_pos_printer_bridge
flutter pub get
```

### SDK Setup

The vendor SDKs are not redistributable and must be added manually.

**Epson** — download from [Epson Support](https://support.epson.net/setupnavi/?PINF=swlist&OSC=WS&LG2=EN&MKN=TM-m30II)
- iOS: add `libepos2.xcframework` and `libeposeasyselect.xcframework` to `packages/epson/epson_printer_ios/ios/Frameworks`
- Android: add `ePOS2.jar` and `ePOSEasySelect.jar` to `packages/epson/epson_printer_android/android/libs`, and native libraries to `jniLibs`

**Star Micronics** — [iOS SDK](https://github.com/star-micronics/StarXpand-SDK-iOS) · [Android SDK](https://github.com/star-micronics/StarXpand-SDK-Android)
- iOS: copy `StarIO10.xcframework` to `packages/star/star_printer_ios/ios/`
- Android: follow the [integration guide](https://github.com/star-micronics/StarXpand-SDK-Android?tab=readme-ov-file#installation)

**Zebra** — download the Link-OS Multiplatform SDK from [Zebra Support](https://www.zebra.com/us/en/support-downloads/software/printer-software/link-os-multiplatform-sdk.html)
- iOS: add `ZSDK_API.xcframework` to `packages/zebra/zebra_printer_ios/ios/Frameworks`
- Android: add `ZSDK_ANDROID_API.jar` to `packages/zebra/zebra_printer_android/android/libs`

### Running

```bash
flutter run     # demo/test harness
flutter test    # service layer + mapper tests
```

`lib/main.dart` and the `*main.dart` files are a hardware test harness for exercising discovery and printing against real devices — useful for verifying a setup, but not part of the library itself.

---

## Unified Printing API

`PrinterBridge` is the main entry point. Every method takes a brand string and behaves identically across all three.

```dart
// Discover
final printers = await PrinterBridge.discover('star');
// → [{name, model, interface, identifier, ...}, ...]

// Connect
await PrinterBridge.connect('star', 'lan', '192.168.1.100');

// Print
await PrinterBridge.printReceipt('star', receiptData, printLanguage: 'fr');
await PrinterBridge.printLabel('zebra', labelData, dimensions: dims);
await PrinterBridge.printTerminalReceipt('epson', terminalData);

// Peripherals & teardown
await PrinterBridge.openCashDrawer('epson');
await PrinterBridge.disconnect('star');
```

Brand-specific configuration lives in singletons applied before/after connect as each SDK requires:

```dart
PrinterBridge.starConfig.setPaperWidthMm(80);       // before connecting
PrinterBridge.zebraConfig.fromMap(savedSettings);   // after connecting
await PrinterBridge.printReceipt('epson', data, epsonWidth: '80mm'); // per-call
```

### Receipt Data

One model renders on all three brands:

```dart
PrinterReceiptData(
  storeName: 'Alpine Goods',
  storeAddress: '412 Queen St W',
  date: '2026-09-05',
  time: '14:31',
  cashierName: 'Sam',
  receiptNumber: '1042',
  items: [
    PrinterLineItem(itemName: 'Wool Scarf', quantity: 2,
                    unitPrice: 39.50, totalPrice: 79.00),
  ],
  returnItems: [
    PrinterReturnLineItem(itemName: 'Hat', quantity: 1, unitPrice: 20.00),
  ],
  exchangeItems: [...],                       // trade-ins, shown negative
  subtotal: 79.00,
  taxes: {'HST': 10.27, 'GST': 2.00},         // any tax names
  total: 89.27,
  payments: [
    PrinterPayment(method: 'Cash', amount: 40.00),
    PrinterPayment(method: 'Card', amount: 49.27, metadata: cardMetadata),
  ],
  isGiftReceipt: false,
)
```

`PrinterPayment.metadata` is optional. When present, receipt builders render a full card/EMV block (AID, TC/AAC, TVR/TSI, auth code, RRN, batch) instead of a one-line method → amount entry. Display rules that differ by acquirer are flags rather than vendor branches:

```dart
PrinterPaymentMetadata(
  cardBrand: 'VISA', cardMask4: '4242', authCode: 'A1B2C3',
  showEmvTags: true,           // some acquirers' required-field lists omit them
  showAmountBreakdown: false,  // Amount/Subtotal/Total vs a single Total line
)
```

### Labels

```dart
PrinterLabelData(
  productName: 'Wool Scarf',
  price: '\$39.50',
  colorSize: 'Charcoal / M',
  barcode: '0123456789012',
)
```

---

## Service Layer

`NativeReceiptService` and `NativeLabelService` sit above the bridge and handle *which* printer to use and how it was configured. They need four things from the host app — no singletons or framework assumptions:

```dart
// 1. configured printers
PrinterRegistry.instance.addPrinter(SavedPrinter(
  id: 'counter', userGivenName: 'Front Counter',
  brand: 'star', interface: 'tcp', address: '192.168.1.50',
  model: 'TSP100', isReceipt: true, isLabel: false, isDefault: true,
  settings: {'paperWidth': '80mm', 'printLanguage': 'fr'},
));

// 2. store identity for the receipt header/footer
StoreIdentity.current = const StoreIdentity(organizationName: 'Alpine Goods');

// 3. where user-facing failures go
PrinterFeedback.onMessage = (msg) => showSnackBar(msg);

// 4. logo resolution (host owns fetching/caching; the library stays offline)
PrinterLogoSource.resolve = (url) async => await myLogoCache.base64(url);
```

Then:

```dart
await NativeReceiptService.printReceipt(transaction);
await NativeReceiptService.printGiftReceipt(transaction);
await NativeReceiptService.printTerminalReceipt(
  metadata: terminalResponse, saleContext: 'SALE', receiptFor: 'CLIENT');

await NativeLabelService.printLabels(
  jobs: [LabelPrintJob(product: scarf, quantity: 12)],
  onProgress: (printed, total) => updateBar(printed / total),
);
```

`transaction` is a plain `Map<String, dynamic>`. The expected keys are documented on [`mapTransactionToReceiptData`](lib/native_receipt_service.dart) — adapt your own schema to it, or skip the mapper and build `PrinterReceiptData` directly.

There is deliberately no fallback to "some other printer" when no default is set. A receipt emerging from the stockroom label printer is worse than one that didn't print, so the call fails and reports through `PrinterFeedback`.

### Localization

Receipts print in the *printer's* configured language rather than the app's UI language — a bilingual store may run the register in English and print in French. Scoped so a print never affects the rest of the app:

```dart
PrinterLocalizations.current = const PrinterLocalizations('en'); // app default
await PrinterBridge.printReceipt('star', data, printLanguage: 'fr'); // this print only
```

51 receipt strings across `en`, `fr`, `es`, `it`. Unknown codes fall back to English rather than printing blanks.

---

## Brand-Specific Notes

### Epson

Receipts are an ordered command list:

```dart
EpsonPrintCommand(type: EpsonCommandType.text,
                  parameters: {'data': 'RECEIPT\n', 'align': 'center'})
EpsonPrintCommand(type: EpsonCommandType.barcode,
                  parameters: {'data': '123456789', 'type': 'CODE128_AUTO', 'hri': 'below'})
EpsonPrintCommand(type: EpsonCommandType.cut, parameters: {})
```

Types: `text`, `textStyle`, `image`, `barcode`, `qrCode`, `cut`, `feed`, `feedPosition`, `pulse`, `beep`, `layout`. Paper width via `PrinterBridge.detectPaperWidth('epson')` → `'58mm'`–`'80mm'`.

Printing is asynchronous and waits for physical completion. The SDK's `sendData` returns once bytes are queued, not when paper moves, so the wrapper waits on the `onPtrReceive` callback with a 30s timeout — a dropped connection can't hang a sale.

### Star Micronics

Receipts are a nested layout document:

```dart
star.PrintJob(content: '', settings: {
  'layout': {
    'header': {'title': 'Store Name', 'align': 'center', 'fontSize': 32},
    'details': {'printableAreaMm': 72.0, 'date': '...', 'cashier': '...'},
    'items': [{'quantity': '2', 'name': 'Coffee', 'price': '3.50'}],
    'barcode': {'content': '123456789', 'symbology': 'code128', 'height': 4},
  }
});
```

`printableAreaMm` drives column count on the native side, taking precedence over SDK model detection. Note that the mC-Label2 is 300 DPI while most Star printers are 203 — the same paper width yields very different dot counts, so column math resolves DPI per model.

### Zebra

No layout model at all; ZPL is generated directly with dot-level positioning against the printer's real dimensions:

```dart
final dims = await PrinterBridge.getZebraDimensions();
// → {printWidthInDots: 639, labelLengthInDots: 1015, dpi: 203}

// Generating ZPL is separable from printing it, so output can be cached
final zpl = PrinterBridge.generateZebraReceiptZPL(
  dims!['printWidthInDots']!, dims['labelLengthInDots']!, dims['dpi']!,
  receiptData,
);
```

SGD parameters are readable and writable directly:

```dart
final width = await ZebraPrinter.getSgdParameter('ezpl.print_width');
await ZebraPrinter.setSgdParameter('ezpl.print_width', '386');
```

---

## Tested Hardware

### Star Micronics
| Device | TSP100iv | TSP100ivsk | mPop | mC-Label2 | TSP100iii | mC_Print3 | TSP100iiiBI | TSP650ii |
|---|---|---|---|---|---|---|---|---|
| iOS | LAN | LAN, BT | BT | LAN, BT, USB | LAN | LAN, BT, USB | BT | BT |
| Android | LAN | LAN, BT, USB | BT, USB | LAN, BT, USB | LAN | LAN, BT, USB | BT | BT |

### Epson
| Device | TM-m30III | Cash Drawer |
|---|---|---|
| iOS | LAN, BT, USB | Yes |
| Android | LAN, BT, USB | Yes |

### Zebra
| Device | ZD421 | ZD410 |
|---|---|---|
| iOS | TCP | TCP, BT Classic |
| Android | TCP, BTLE, USB | TCP, BT Classic, BTLE |

---

## Platform-Specific Considerations

### iOS Limitations
- **Epson**: USB connection disables Bluetooth discovery until app restart
- **Star**: USB connection requires a power cycle for Bluetooth reconnection
- **Zebra**: limited BTLE support, direct MAC pairing required

### Android Permissions
```xml
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
```

### Threading
Vendor SDK calls that block — discovery teardown retry loops, connection opens, USB cleanup — run on background threads with results marshalled back to the platform thread, since several take seconds and would otherwise trigger ANRs. iOS `EAAccessoryManager` lookups stay on the main thread, as the framework requires.

### Release Builds
- **Zebra/iOS**: the podspec vendors `ZSDK_API.xcframework` rather than the flat `libZSDK_API.a`, which only contains device slices and won't link against Apple Silicon simulators. `-all_load` and disabled dead-code stripping keep symbols reached via ObjC runtime lookup from being stripped.
- **Android**: both Epson and Zebra ship `consumer-rules.pro`, since both SDKs locate classes over JNI and R8 would otherwise strip them.

---

## Troubleshooting

### Bluetooth Connection Problems
- **Star/Epson**: ensure the printer is in pairing mode and paired in device settings
- **Zebra**: use direct MAC address connection for BTLE devices
- **All brands**: power cycle the printer when switching between interfaces

### USB Interface Switching
- **iOS**: USB connection may disable Bluetooth until app restart
- **Android**: remove the cable and power cycle to re-enable Bluetooth
- **Zebra**: call SDK disconnect before switching interfaces

### Paper Width
- **Epson**: automatic detection on connection
- **Star**: set from saved config via `printableAreaMm`; falls back to model detection
- **Zebra**: SGD parameter reading with manual override

---

## Repo Layout

| Path | Contents |
|---|---|
| [`lib/printer_bridge.dart`](lib/printer_bridge.dart) | unified API, receipt/label models, per-brand renderers |
| [`lib/native_receipt_service.dart`](lib/native_receipt_service.dart) · [`native_label_service.dart`](lib/native_label_service.dart) | printer selection, brand config, batching |
| [`lib/printer_host.dart`](lib/printer_host.dart) | `SavedPrinter`, `PrinterRegistry`, `StoreIdentity`, feedback/logo hooks |
| [`lib/printer_localizations.dart`](lib/printer_localizations.dart) | receipt strings, 4 languages |
| [`lib/star_commands.dart`](lib/star_commands.dart) | Star command abstraction |
| [`packages/`](packages/) | 12 federated plugin packages (facade / platform interface / android / ios per brand) |
| [`test/`](test/) | service layer and mapper tests |

## Contributing

Contributions are welcome. The core objective is a unified Flutter API for discovering, connecting to, and printing from thermal printers across multiple brands — a caller shouldn't need to know which brand they're talking to.

- Keep the API consistent across all three brands
- Follow the federated plugin architecture
- Test against multiple printer models and both platforms
- Document platform-specific behaviours and limitations

## Additional Resources

- [Epson ePOS SDK Documentation](https://download4.epson.biz/sec_pubs/pos/reference_en/)
- [Star StarXpand SDK](https://github.com/star-micronics/StarXpand-SDK-iOS)
- [Zebra Link-OS SDK](https://techdocs.zebra.com/link-os/)
- [ZPL Programming Guide](https://www.zebra.com/content/dam/support-dam/en/documentation/unrestricted/guide/software/zpl-zbi2-pg-en.pdf)
