# Flutter POS Printer Bridge

A comprehensive Flutter application demonstrating cross-platform thermal receipt and label printing using **Epson**, **Star Micronics**, and **Zebra** printer SDKs in a single unified interface. This app showcases multi-brand printer discovery, connection management, and advanced printing features across iOS and Android platforms.

This repository follows Flutter's federated [plugin architecture](https://docs.flutter.dev/packages-and-plugins/developing-packages#federated-plugins) and combines three separate printer SDK wrappers into a unified POS printing solution.

## Features

- **Multi-brand printer support** (Epson TM Series, Star TSP/mPOP Series, Zebra ZD/ZQ Series)
- **Cross-platform printer discovery** (TCP/LAN, USB, Bluetooth/BLE)
- **Automatic paper width detection** with manual override
- **Receipt printing** with dynamic formatting based on paper width
- **Label printing** with barcode generation and text styling
- **Multi-label printing** with quantity control
- **Logo/image printing** support
- **Cash drawer integration**
- **Dynamic ZPL generation** for Zebra printers
- **Unified API** across all three printer brands

## Getting Started

### Prerequisites

- Flutter SDK (latest stable)
- iOS development: Xcode 14+
- Android development: Android Studio with SDK 21+
- Physical thermal printer from supported brands

Install Flutter and its dependencies [here](https://docs.flutter.dev/get-started/quick) to run this code in an emulator or physical device.

### Installation

1. Clone the repository
```bash
git clone git@github.com:eljam3239/flutter_pos_printer_bridge.git
cd flutter_pos_printer_bridge
```

2. Install Flutter dependencies
```bash
flutter pub get
```

### SDK Setup

#### Epson Setup
1. Download the Epson ePOS SDK from [Epson Support](https://support.epson.net/setupnavi/?PINF=swlist&OSC=WS&LG2=EN&MKN=TM-m30II)
2. **iOS**: Add `libepos2.xcframework` and `libeposeasyselect.xcframework` to `packages/epson_printer_ios/ios/Frameworks`
3. **Android**: Add `ePOS2.jar` and `ePOSEasySelect.jar` to `packages/epson_printer_android/android/libs` and native libraries to `jniLibs`

#### Star Micronics Setup
1. Download the StarXpand SDKs:
   - [iOS SDK](https://github.com/star-micronics/StarXpand-SDK-iOS)
   - [Android SDK](https://github.com/star-micronics/StarXpand-SDK-Android)
2. **iOS**: Copy `StarIO10.xcframework` to `packages/star_printer_ios/ios/`
3. **Android**: Follow the [Android integration guide](https://github.com/star-micronics/StarXpand-SDK-Android?tab=readme-ov-file#installation)

#### Zebra Setup
1. Download the Link-OS Multiplatform SDKs from [Zebra Support](https://www.zebra.com/us/en/support-downloads/software/printer-software/link-os-multiplatform-sdk.html)
2. **iOS**: Add `ZSDK_API.xcframework` to `packages/zebra_printer_ios/ios/Frameworks`
3. **Android**: Add `ZSDK_ANDROID_API.jar` to `packages/zebra_printer_android/android/libs`

### Running the Application

```bash
flutter run
```

## Unified Printing API

### Printer Brand Selection

The app provides a unified interface for selecting printer brands:

```dart
enum PrinterBrand {
  epson('Epson', 'TM Series & Compatible'),
  star('Star Micronics', 'TSP & mPOP Series'),
  zebra('Zebra', 'ZD & ZQ Series');
}
```

### Discovery Workflow

All brands support unified discovery with automatic interface detection:

```dart
Future<void> _discoverPrinters() async {
  switch (_selectedBrand) {
    case PrinterBrand.epson:
      // Multi-interface discovery: TCP, Bluetooth, USB
      await _discoverEpsonPrinters();
      break;
    case PrinterBrand.star:
      // StarXpand discovery
      await _discoverStarPrinters();
      break;
    case PrinterBrand.zebra:
      // Link-OS comprehensive discovery
      await _discoverZebraAll();
      break;
  }
}
```

### Connection Management

Unified connection handling with automatic cleanup:

```dart
Future<void> _connectToPrinter() async {
  // Force disconnect from current printer if switching
  if (_isConnected) {
    await _disconnectFromPrinter();
  }
  
  switch (_selectedBrand) {
    case PrinterBrand.epson:
      await EpsonPrinter.connect(epsonSettings);
      break;
    case PrinterBrand.star:
      await StarPrinter.connect(starSettings);
      break;
    case PrinterBrand.zebra:
      await ZebraPrinter.connect(zebraSettings);
      // Auto-fetch printer dimensions
      await _fetchZebraDimensions();
      break;
  }
}
```

## Brand-Specific Integration Guides

## Epson Integration

### Core Models

#### EpsonPrintCommand
```dart
EpsonPrintCommand(
  type: EpsonCommandType.text,
  parameters: {
    'data': 'Hello World\n',
    'align': 'center'
  }
)
```

#### Command Types
- `EpsonCommandType.text` - Print text
- `EpsonCommandType.barcode` - Print barcodes  
- `EpsonCommandType.feed` - Line feeds
- `EpsonCommandType.cut` - Cut paper
- `EpsonCommandType.image` - Print images

### Paper Width Detection

```dart
String detectedWidth = await EpsonPrinter.detectPaperWidth();
// Returns: '58mm', '60mm', '70mm', '76mm', or '80mm'
```

### Receipt Printing

```dart
List<EpsonPrintCommand> _buildReceiptCommands() {
  return [
    EpsonPrintCommand(
      type: EpsonCommandType.text,
      parameters: {'align': 'center'}
    ),
    EpsonPrintCommand(
      type: EpsonCommandType.text,
      parameters: {'data': 'RECEIPT\n'}
    ),
    EpsonPrintCommand(
      type: EpsonCommandType.barcode,
      parameters: {
        'data': '123456789',
        'type': 'CODE128_AUTO',
        'hri': 'below'
      }
    ),
    EpsonPrintCommand(type: EpsonCommandType.cut, parameters: {}),
  ];
}
```

## Star Micronics Integration

### Core Models

#### PrintJob
```dart
final printJob = star.PrintJob(
  content: '',
  settings: {
    'layout': {
      'header': {
        'title': 'Store Name',
        'align': 'center',
        'fontSize': 32,
      },
      'details': {
        'printableAreaMm': 72.0, // Paper width
        'date': '12/17/2025',
        'cashier': 'John Doe',
      },
      'items': [
        {
          'quantity': '2',
          'name': 'Coffee', 
          'price': '3.50'
        }
      ],
      'barcode': {
        'content': '123456789',
        'symbology': 'code128',
        'height': 4,
      }
    }
  }
);
```

### Connection Settings
```dart
final settings = star.StarConnectionSettings(
  interfaceType: star.StarInterfaceType.lan,
  identifier: '192.168.1.100',
  timeout: 15000,
);
```

### Label Printing
```dart
// Paper width affects layout
Map<int, String> paperSpecs = {
  38: 'vertical_centered',
  58: 'mixed', 
  80: 'horizontal'
};
```

## Zebra Integration

### Core Models

#### LabelData
```dart
LabelData(
  productName: "T-Shirt",
  colorSize: "Small Turquoise", 
  scancode: "123456789",
  price: "\$5.00",
)
```

#### ReceiptData
```dart
ReceiptData(
  storeName: "Coffee Shop",
  storeAddress: "123 Main St",
  items: [
    ReceiptLineItem(quantity: 2, itemName: "Latte", unitPrice: 4.50),
  ],
  cashierName: "John",
  transactionDate: DateTime.now(),
)
```

#### ConnectedPrinter
```dart
ConnectedPrinter(
  discoveredPrinter: selectedPrinter,
  printWidthInDots: 639,
  labelLengthInDots: 1015, 
  dpi: 203,
  connectedAt: DateTime.now(),
)
```

### Discovery Methods
```dart
// Auto discovery (recommended)
final printers = await ZebraPrinter.discoverNetworkPrintersAuto();

// Specific interface discovery
final btPrinters = await ZebraPrinter.discoverBluetoothPrinters();
final usbPrinters = await ZebraPrinter.discoverUsbPrinters(); // Android only
```

### Dynamic ZPL Generation

```dart
Future<String> _generateLabelZPL(int width, int height, int dpi, LabelData labelData) async {
  // Calculate positions based on actual printer dimensions
  int productNameCharWidth = getCharWidthInDots(38, dpi);
  int estimatedWidth = labelData.productName.length * productNameCharWidth;
  int centeredX = (width - estimatedWidth) ~/ 2;
  
  return '''
^XA
^CF0,38
^FO$centeredX,14^FD${labelData.productName}^FS
^BY2,3,50
^FO100,124^BCN^FD${labelData.scancode}^FS
^XZ''';
}
```

### SGD Parameter Management
```dart
// Read printer configuration
final printWidth = await ZebraPrinter.getSgdParameter('ezpl.print_width');

// Set printer configuration
await ZebraPrinter.setSgdParameter('ezpl.print_width', '386');
```

## Tested Hardware Compatibility

### Star Micronics
| Device      | TSP100iv | TSP100ivsk | mPop | mC-Label2 | TSP100iii | mC_Print3 | TSP100iiiBI | TSP650ii |
|-------------|----------|------------|------|-----------|-----------|-----------|-------------|----------|
| iOS         | LAN      | LAN, BT    | BT   | LAN, BT, USB | LAN    | LAN, BT, USB | BT       | BT       |
| Android     | LAN      | LAN, BT, USB | BT, USB | LAN, BT, USB | LAN | LAN, BT, USB | BT       | BT       |

### Epson
| Device      | TM-m30III | Cash Drawer |
|-------------|-----------|-------------|
| iOS         | LAN, BT, USB | Yes       |
| Android     | LAN, BT, USB | Yes       |

### Zebra  
| Device      | ZD421    | ZD410    |
|-------------|----------|----------|
| iOS         | TCP      | TCP, BT Classic |
| Android     | TCP, BTLE, USB | TCP, BT Classic, BTLE |

## Platform-Specific Considerations

### iOS Limitations
- **Epson**: USB connection disables Bluetooth discovery until app restart
- **Star**: USB connection requires power cycle for Bluetooth reconnection
- **Zebra**: Limited BTLE support, direct MAC pairing required

### Android Permissions
```dart
// Required permissions in AndroidManifest.xml
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
```

### Permission Handling
```dart
Future<void> _checkPermissions() async {
  if (Platform.isAndroid) {
    final status = await Permission.bluetoothConnect.status;
    if (!status.isGranted) {
      await Permission.bluetoothConnect.request();
    }
  }
}
```

## Error Handling & Troubleshooting

### Connection Issues
```dart
Future<void> _handleConnectionError(Exception e) async {
  final errorMessage = e.toString().toLowerCase();
  
  if (errorMessage.contains('timeout')) {
    // Network timeout - check connection
    await _reconnectPrinter();
  } else if (errorMessage.contains('paper')) {
    // Paper issues - guide user
    _showPaperError();
  } else if (errorMessage.contains('bluetooth')) {
    // Bluetooth pairing issues
    _showBluetoothPairingGuide();
  }
}
```

### Common Issues & Solutions

#### Bluetooth Connection Problems
- **Star/Epson**: Ensure printer is in pairing mode and paired in device settings
- **Zebra**: Use direct MAC address connection for BTLE devices
- **All brands**: Power cycle printer if switching between interfaces

#### USB Interface Switching
- **iOS**: USB connection may disable Bluetooth until app restart
- **Android**: Remove cable and power cycle printer to enable Bluetooth
- **Zebra**: Use SDK disconnect before interface switching

#### Paper Width Detection
- **Epson**: Automatic detection on connection for 58mm/80mm paper
- **Star**: Manual selection based on printer model specifications
- **Zebra**: SGD parameter reading with manual override options

## Advanced Features

### Multi-Label Printing with Quantity Control
```dart
// Unified quantity control across all brands
Future<void> _printMultipleLabels(int quantity) async {
  for (int i = 0; i < quantity; i++) {
    switch (_selectedBrand) {
      case PrinterBrand.epson:
        await _printEpsonLabel();
        break;
      case PrinterBrand.star:
        await _printStarLabel();
        break;
      case PrinterBrand.zebra:
        await _printZebraLabel();
        break;
    }
    
    if (i < quantity - 1) {
      await Future.delayed(Duration(milliseconds: 100));
    }
  }
}
```

### Cash Drawer Integration
```dart
Future<void> _openCashDrawer() async {
  switch (_selectedBrand) {
    case PrinterBrand.epson:
      await EpsonPrinter.openCashDrawer();
      break;
    case PrinterBrand.star:
      await star.StarPrinter.openCashDrawer();
      break;
    case PrinterBrand.zebra:
      // Zebra cash drawer via ZPL command
      await ZebraPrinter.sendCommands('^XA^FO0,0^XZ', language: ZebraPrintLanguage.zpl);
      break;
  }
}
```

### Image Printing Support
```dart
// Base64 image printing (Star example)
'image': {
  'base64': imageBase64String,
  'mime': 'image/png',
  'align': 'center',
  'width': 256,
}
```

## Contributing

Contributions are appreciated and encouraged! The core objective is maintaining a unified Flutter API for discovering, connecting to, and printing from thermal receipt printers across multiple brands.

### Development Guidelines
- Maintain consistent API across all printer brands
- Follow federated plugin architecture patterns
- Test across multiple printer models and platforms
- Document platform-specific behaviors and limitations

## Additional Resources

For brand-specific implementation details:
- [Epson ePOS SDK Documentation](https://download4.epson.biz/sec_pubs/pos/reference_en/)
- [Star StarXpand SDK](https://github.com/star-micronics/StarXpand-SDK-iOS)
- [Zebra Link-OS SDK](https://techdocs.zebra.com/link-os/)
- [ZPL Programming Guide](https://www.zebra.com/content/dam/support-dam/en/documentation/unrestricted/guide/software/zpl-zbi2-pg-en.pdf)
