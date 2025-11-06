import 'package:flutter/material.dart';
import 'package:star_printer/star_printer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io' show Platform;
import 'package:flutter/services.dart' show rootBundle;
import 'dart:convert' show base64Encode;
import 'package:image_picker/image_picker.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'Star Printer Demo'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;
  List<String> _discoveredPrinters = [];
  bool _isConnected = false;
  String _printerStatus = 'Unknown';
  String? _selectedPrinter; // Add selected printer tracking
  bool _openDrawerAfterPrint = true; // Option to auto-open drawer after printing
  
  // Label printer paper width selector
  int _labelPaperWidthMm = 58; // Default to 58mm
  int _labelQuantity = 1; // Number of labels to print

  // Receipt layout controls (for integration into POS app)
  String _headerTitle = "Wendy's";
  int _headerFontSize = 32; // header-sized font
  int _headerSpacingLines = 1; // blank lines after header
  String? _logoBase64; // small centered image (base64-encoded PNG)
  int _imageWidthPx = 200; // width in pixels for the small image
  int _imageSpacingLines = 1; // blank lines after image
  late final TextEditingController _headerController;
  // Receipt detail fields
  String _locationText = '67 LeBron James avenue, Cleveland, OH';
  String _date = '02/10/2025';
  String _time = '2:39 PM';
  String _cashier = 'Eli';
  String _receiptNum = '67676969';
  String _lane = '1';
  String _footer = 'Thank you for shopping with us! Have a nice day!';
  // Single item input (repeat pattern)
  String _itemQuantity = '1';
  String _itemName = 'Orange';
  String _itemPrice = '5.00';
  String _itemRepeat = '3';
  late final TextEditingController _locationController;
  late final TextEditingController _dateController;
  late final TextEditingController _timeController;
  late final TextEditingController _cashierController;
  late final TextEditingController _receiptNumController;
  late final TextEditingController _laneController;
  late final TextEditingController _footerController;
  late final TextEditingController _itemQuantityController;
  late final TextEditingController _itemNameController;
  late final TextEditingController _itemPriceController;
  late final TextEditingController _itemRepeatController;

  // A tiny 32x32 black square PNG as a sample logo (base64)
  // You can replace this with your own base64-encoded PNG at runtime
  static const String _sampleLogoBase64 =
      'iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAAKElEQVRYhe3PsQkAIAwAsTgv//+sA0hJr4YqXoQAAAC4g0g3iQAAAPw3gqA6n9K2ylgAAAAASUVORK5CYII=';

  @override
  void initState() {
    super.initState();
    _headerController = TextEditingController(text: _headerTitle);
    _locationController = TextEditingController(text: _locationText);
    _dateController = TextEditingController(text: _date);
    _timeController = TextEditingController(text: _time);
    _cashierController = TextEditingController(text: _cashier);
    _receiptNumController = TextEditingController(text: _receiptNum);
    _laneController = TextEditingController(text: _lane);
    _footerController = TextEditingController(text: _footer);
  _itemQuantityController = TextEditingController(text: _itemQuantity);
  _itemNameController = TextEditingController(text: _itemName);
  _itemPriceController = TextEditingController(text: _itemPrice);
  _itemRepeatController = TextEditingController(text: _itemRepeat);
    _checkAndRequestPermissions();
    _loadFrogAsset();
  }

  @override
  void dispose() {
    _headerController.dispose();
    _locationController.dispose();
    _dateController.dispose();
    _timeController.dispose();
    _cashierController.dispose();
    _receiptNumController.dispose();
    _laneController.dispose();
    _footerController.dispose();
  _itemQuantityController.dispose();
  _itemNameController.dispose();
  _itemPriceController.dispose();
  _itemRepeatController.dispose();
    super.dispose();
  }

  Future<void> _checkAndRequestPermissions() async {
    // Only check Bluetooth permissions on Android - iOS handles this differently
    if (Platform.isAndroid) {
      // Check if we need to request Bluetooth permissions
      final bluetoothStatus = await Permission.bluetoothConnect.status;
      final bluetoothScanStatus = await Permission.bluetoothScan.status;
      
      if (!bluetoothStatus.isGranted || !bluetoothScanStatus.isGranted) {
        print('DEBUG: Bluetooth permissions not granted, requesting...');
        
        // Request permissions
        final results = await [
          Permission.bluetoothConnect,
          Permission.bluetoothScan,
          Permission.location, // Also needed for Bluetooth discovery on some devices
        ].request();
        
        results.forEach((permission, status) {
          print('DEBUG: Permission $permission: $status');
        });
        
        if (results[Permission.bluetoothConnect]?.isGranted == true) {
          print('DEBUG: Bluetooth permissions granted');
        } else {
          print('DEBUG: Bluetooth permissions still denied');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Bluetooth permissions are required for printer discovery. Please enable them in settings.'),
                duration: Duration(seconds: 5),
              ),
            );
          }
        }
      } else {
        print('DEBUG: Bluetooth permissions already granted');
      }
    } else {
      // iOS - Bluetooth permissions are handled automatically by the system
      print('DEBUG: Running on iOS - Bluetooth permissions handled by system');
    }
  }

  void _incrementCounter() {
    setState(() {
      _counter++;
    });
  }

  Future<void> _loadFrogAsset() async {
    try {
      // Load the PNG bytes for the frog image declared in pubspec
      final bytes = await rootBundle.load('lib/frog pic.png');
      // Base64-encode for transport to native; we explicitly mark as PNG
      final b64 = base64Encode(bytes.buffer.asUint8List());
      setState(() {
        _logoBase64 = b64;
        _imageWidthPx = 256; // a reasonable default width for 80mm paper
      });
      print('DEBUG: Loaded frog asset, bytes=${bytes.lengthInBytes}');
    } catch (e) {
      print('DEBUG: Failed to load frog asset: $e');
    }
  }

  Future<void> _pickReceiptImage() async {
    // Support iOS & Android; silently ignore on other platforms
    if (!(Platform.isIOS || Platform.isAndroid)) {
      print('DEBUG: Image picking not supported on this platform');
      return;
    }
    try {
      // Optional Android permission (may be unnecessary on newer Android photo picker API)
      if (Platform.isAndroid) {
        try {
          final storageStatus = await Permission.storage.status;
          if (storageStatus.isDenied) {
            final result = await Permission.storage.request();
            if (!result.isGranted) {
              print('DEBUG: Storage permission denied (continuing, picker may still work).');
            }
          }
        } catch (permErr) {
          print('DEBUG: Storage permission check threw (ignoring): $permErr');
        }
      }
      final picker = ImagePicker();
      final XFile? file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (file == null) {
        print('DEBUG: Image pick cancelled');
        return;
      }
      final bytes = await file.readAsBytes();
      // Heuristic: decide target width based on original width if decodable via instantiateImageCodec (optional improvement)
      // For simplicity, set width relative to size: if > 1000px wide, scale to 384 else 256 else 200.
      int suggestedWidth = 200;
      try {
        // We can try to decode dimensions via Image.memory in a detached way later; keep simple now.
        if (bytes.lengthInBytes > 4000000) {
          suggestedWidth = 384;
        } else if (bytes.lengthInBytes > 1000000) {
          suggestedWidth = 320;
        } else if (bytes.lengthInBytes > 300000) {
          suggestedWidth = 256;
        }
      } catch (_) {}
      final b64 = base64Encode(bytes);
      setState(() {
        _logoBase64 = b64;
        _imageWidthPx = suggestedWidth;
      });
      print('DEBUG: Picked image size=${bytes.lengthInBytes} bytes, suggestedWidth=$suggestedWidth platform=${Platform.isIOS ? 'iOS' : 'Android'}');
    } catch (e) {
      print('DEBUG: Failed to pick image: $e');
    }
  }

  Future<void> _discoverPrinters() async {
    try {
      print('DEBUG: Starting printer discovery...');
      print('DEBUG: Looking for printers on network. TSP100 should be at 10.20.30.125');
      
      // Check permissions first - only on Android
      if (Platform.isAndroid) {
        final bluetoothConnectStatus = await Permission.bluetoothConnect.status;
        final bluetoothScanStatus = await Permission.bluetoothScan.status;
        
        if (!bluetoothConnectStatus.isGranted || !bluetoothScanStatus.isGranted) {
          print('DEBUG: Bluetooth permissions not granted, requesting again...');
          await _checkAndRequestPermissions();
          
          // Check again after request
          final newBluetoothConnectStatus = await Permission.bluetoothConnect.status;
          if (!newBluetoothConnectStatus.isGranted) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Bluetooth permissions required. Please enable in Android Settings > Apps > test_star > Permissions'),
                  action: SnackBarAction(
                    label: 'Open Settings',
                    onPressed: () => openAppSettings(),
                  ),
                  duration: const Duration(seconds: 8),
                ),
              );
            }
            return;
          }
        }
      }
      
      final printers = await StarPrinter.discoverPrinters();
      print('DEBUG: Discovery result: $printers');
      setState(() {
        _discoveredPrinters = printers;
        // Auto-select first printer if none selected or if current selection is no longer available
        if (_selectedPrinter == null || !printers.contains(_selectedPrinter)) {
          _selectedPrinter = printers.isNotEmpty ? printers.first : null;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Found ${printers.length} printers')),
      );
    } catch (e) {
      print('DEBUG: Discovery error: $e');
      String message = 'Discovery failed: $e';
      
      if (e.toString().contains('BLUETOOTH_PERMISSION_DENIED')) {
        message = 'Bluetooth permissions required. Please grant permissions and try again.';
      } else if (e.toString().contains('BLUETOOTH_UNAVAILABLE')) {
        message = 'Bluetooth is not available or disabled. Please enable Bluetooth.';
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Future<void> _connectToPrinter() async {
    if (_discoveredPrinters.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No printers discovered. Please discover printers first.')),
      );
      return;
    }

    if (_selectedPrinter == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a printer first.')),
      );
      return;
    }

    try {
      // Disconnect from current printer if connected
      if (_isConnected) {
        print('DEBUG: Disconnecting from current printer before new connection...');
        await StarPrinter.disconnect();
        setState(() {
          _isConnected = false;
        });
        // Small delay to ensure clean disconnect
        await Future.delayed(const Duration(milliseconds: 500));
      }
      
      final printerString = _selectedPrinter!; // Use selected printer instead of first
      
      // Parse the printer string to determine interface type
      StarInterfaceType interfaceType;
      String identifier;
      
      if (printerString.startsWith('LAN:')) {
        interfaceType = StarInterfaceType.lan;
        // Extract just the identifier part (MAC address or IP), ignore model info
        final parts = printerString.substring(4).split(':');
        identifier = parts[0]; // Take first part before any model info
      } else if (printerString.startsWith('BT:')) {
        interfaceType = StarInterfaceType.bluetooth;
        final parts = printerString.substring(3).split(':');
        identifier = parts[0]; // Take first part before any model info
      } else if (printerString.startsWith('BLE:')) {
        interfaceType = StarInterfaceType.bluetoothLE;
        final parts = printerString.substring(4).split(':');
        identifier = parts[0]; // Take first part before any model info
      } else if (printerString.startsWith('USB:')) {
        interfaceType = StarInterfaceType.usb;
        final parts = printerString.substring(4).split(':');
        identifier = parts[0]; // Take first part before any model info
      } else {
        interfaceType = StarInterfaceType.lan;
        identifier = printerString.split(':')[0]; // Take first part
      }
      
      print('DEBUG: Connecting to $interfaceType printer: $identifier (Selected: $printerString)');
      
      final settings = StarConnectionSettings(
        interfaceType: interfaceType,
        identifier: identifier,
      );
      await StarPrinter.connect(settings);
      setState(() {
        _isConnected = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connected to: ${_selectedPrinter!.split(':').last}')), // Show printer model
      );
    } catch (e) {
      print('DEBUG: Connection error: $e');
      setState(() {
        _isConnected = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connection failed: $e')),
      );
    }
  }

  Future<void> _printLabel() async {
    print('DEBUG: Print label button pressed');
    
    try {
      print('DEBUG: Creating label print job for $_labelQuantity label(s)...');
      
      // Calculate printable area based on paper width
      // 38mm -> 34.5mm printable, 58mm -> 48mm printable, 80mm -> 72mm printable
      double printableAreaMm;
      String layoutType;
      
      if (_labelPaperWidthMm == 38) {
        printableAreaMm = 34.5;
        layoutType = 'vertical_centered';  // Everything vertical and centered for narrow labels
      } else if (_labelPaperWidthMm == 58) {
        printableAreaMm = 48.0;
        layoutType = 'mixed';  // Mixed layout with some horizontal elements
      } else {
        printableAreaMm = 72.0;
        layoutType = 'horizontal';  // Full horizontal layout for wide labels
      }
      
      print('DEBUG: _labelPaperWidthMm = $_labelPaperWidthMm, printableAreaMm = $printableAreaMm');
      
      // All centered content for narrow labels
      final productName = _itemName.isNotEmpty ? _itemName : 'PRODUCT NAME';
      final category = '';  // or get from a field
      final price = _itemPrice.isNotEmpty ? _itemPrice : '0.00';
      final scancode = '0123456789';  // Barcode data
      final size = 'Small';
      final color = 'Blush Floral';

      
      // Label layout based on paper width
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
            'symbology': 'code128',  // Using CODE128 as requested
            'height': 4,  // Very compact barcode height (90% shorter than default ~50)
            'printHRI': true,  // Don't print numbers below barcode to save vertical space
          },
        },
      };
      
      final labelContent = ''; //'''
// $productName
// $qty | Green
// \$$price
// ''';

      final printJob = PrintJob(
        content: labelContent,
        settings: labelSettings,
      );
      
      bool shownPaperHoldWarning = false;
      
      // Print multiple labels
      for (int i = 0; i < _labelQuantity; i++) {
        print('DEBUG: Sending label ${i + 1} of $_labelQuantity to printer...');
        
        final printStartTime = DateTime.now();
        
        try {
          // Try to print the label
          await StarPrinter.printReceipt(printJob);
          
          final printDuration = DateTime.now().difference(printStartTime);
          print('DEBUG: Label ${i + 1} completed in ${printDuration.inMilliseconds}ms');
          
          // Small delay between prints to prevent buffer overflow
          if (i < _labelQuantity - 1) {
            await Future.delayed(const Duration(milliseconds: 100));
          }
        } catch (e) {
          // Check if this is a paper hold error
          final errorMessage = e.toString().toLowerCase();
          if (errorMessage.contains('holding paper') || errorMessage.contains('paper hold')) {
            if (!shownPaperHoldWarning && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Please remove each label after it prints, or disable "Paper Hold" in your Star App settings'),
                  duration: Duration(seconds: 8),
                ),
              );
              shownPaperHoldWarning = true;
            }
            print('DEBUG: Paper hold detected - waiting for user to remove label ${i + 1}');
            
            // Keep trying to print this label until it succeeds
            bool labelPrinted = false;
            while (!labelPrinted) {
              await Future.delayed(const Duration(milliseconds: 500));
              try {
                await StarPrinter.printReceipt(printJob);
                labelPrinted = true;
                print('DEBUG: Label ${i + 1} printed after paper removal');
              } catch (retryError) {
                // Still holding, keep waiting
                if (!retryError.toString().toLowerCase().contains('holding paper')) {
                  // Different error, rethrow
                  rethrow;
                }
              }
            }
            
            final printDuration = DateTime.now().difference(printStartTime);
            print('DEBUG: Label ${i + 1} completed in ${printDuration.inMilliseconds}ms (including wait time)');
            
            // Small delay between prints
            if (i < _labelQuantity - 1) {
              await Future.delayed(const Duration(milliseconds: 100));
            }
          } else {
            // Different error, rethrow
            rethrow;
          }
        }
      }
      
      print('DEBUG: All $_labelQuantity label(s) printed successfully');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$_labelQuantity label(s) printed successfully')),
        );
      }
    } catch (e) {
      print('DEBUG: Label print failed with error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to print label: $e')),
        );
      }
    }
  }

  Future<void> _printReceipt() async {
    print('DEBUG: Print receipt button pressed');
    
    try {
      print('DEBUG: Creating print job...');
      
      // Calculate printable area for receipts too (same logic as labels)
      double printableAreaMm;
      if (_labelPaperWidthMm == 38) {
        printableAreaMm = 34.5;
      } else if (_labelPaperWidthMm == 58) {
        printableAreaMm = 48.0;
      } else {
        printableAreaMm = 72.0;
      }
      
      print('DEBUG: Receipt - _labelPaperWidthMm = $_labelPaperWidthMm, printableAreaMm = $printableAreaMm');
      
      // Build structured layout settings to be interpreted by native layers
      final layoutSettings = {
        'layout': {
          'header': {
            'title': _headerTitle,
            'align': 'center',
            'fontSize': _headerFontSize,
            'spacingLines': _headerSpacingLines,
          },
              'details': {
                'locationText': _locationText,
                'date': _date,
                'time': _time,
                'cashier': _cashier,
                'receiptNum': _receiptNum,
                'lane': _lane,
                'footer': _footer,
                'printableAreaMm': printableAreaMm,  // Add printable area for receipts too
              },
          'items': [
            {
              'quantity': _itemQuantity,
              'name': _itemName,
              'price': _itemPrice,
              'repeat': _itemRepeat,
            }
          ],
          'image': _logoBase64 == null
              ? null
              : {
                  'base64': _logoBase64,
                  'mime': 'image/png',
                  'align': 'center',
                  'width': _imageWidthPx,
                  'spacingLines': _imageSpacingLines,
                },
        },
      };

      final printJob = PrintJob(
        content: ''
//         '''
//            .--._.--.
//           ( O     O )
//           /   . .   \\
//          .\`._______.\'.\`
//         /(           )\\
//       _/  \\  \\   /  /  \\_
//    .~   \`  \\  \\ /  /  \'   ~.
//   {    -.   \\  V  /   .-    }
// _ _\`.    \\  |  |  |  /    .\'\_ _
// >_       _} |  |  | {_       _<
//  /. - ~ ,_-\'  .^.  \`-_, ~ - .\\
//          \'-\'|/   \\|\`-\`

// Hello Star Printer!
// Counter: $_counter
// Print Test

// ''',
,
        settings: layoutSettings,
      );
      
      print('DEBUG: Sending print job to printer...');
      await StarPrinter.printReceipt(printJob);
      
      print('DEBUG: Print job completed successfully');
      
      // Optionally open cash drawer after successful print
      if (_openDrawerAfterPrint && _isConnected) {
        try {
          print('DEBUG: Auto-opening cash drawer after print...');
          await StarPrinter.openCashDrawer();
          print('DEBUG: Auto cash drawer opened successfully');
        } catch (drawerError) {
          print('DEBUG: Auto cash drawer failed: $drawerError');
          // Don't fail the whole operation if drawer fails
        }
      }
      
      print('DEBUG: Print job completed successfully');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_openDrawerAfterPrint 
            ? 'Print job sent and drawer opened' 
            : 'Print job sent successfully')),
      );
    } catch (e) {
      print('DEBUG: Print failed with error: $e');
      print('DEBUG: Error type: ${e.runtimeType}');
      print('DEBUG: Error details: ${e.toString()}');
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Print failed: $e')),
      );
    }
  }

  Future<void> _disconnectFromPrinter() async {
    try {
      await StarPrinter.disconnect();
      setState(() {
        _isConnected = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Disconnected from printer')),
      );
    } catch (e) {
      print('DEBUG: Disconnect error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Disconnect failed: $e')),
      );
    }
  }

  Future<void> _getStatus() async {
    try {
      final status = await StarPrinter.getStatus();
      setState(() {
        _printerStatus = 'Online: ${status.isOnline}, Status: ${status.status}';
      });
    } catch (e) {
      setState(() {
        _printerStatus = 'Error: $e';
      });
    }
  }

  Future<void> _openCashDrawer() async {
    if (!_isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please connect to a printer first')),
      );
      return;
    }

    try {
      print('DEBUG: Opening cash drawer...');
      await StarPrinter.openCashDrawer();
      print('DEBUG: Cash drawer command sent successfully');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cash drawer opened')),
      );
    } catch (e) {
      print('DEBUG: Cash drawer error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cash drawer failed: $e')),
      );
    }
  }

  Future<void> _testDirectConnection() async {
    try {
      print('DEBUG: Testing direct connection to TSP100 at 10.20.30.125...');
      
      // Disconnect from current printer if connected
      if (_isConnected) {
        await StarPrinter.disconnect();
        setState(() {
          _isConnected = false;
        });
        await Future.delayed(const Duration(milliseconds: 500));
      }
      
      final settings = StarConnectionSettings(
        interfaceType: StarInterfaceType.lan,
        identifier: '10.20.30.125',
      );
      
      await StarPrinter.connect(settings);
      setState(() {
        _isConnected = true;
        // Add to discovered printers list if not already there
        final directPrinter = 'LAN:10.20.30.125:TSP100';
        if (!_discoveredPrinters.contains(directPrinter)) {
          _discoveredPrinters.add(directPrinter);
          _selectedPrinter = directPrinter;
        }
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Direct connection to TSP100 successful!')),
      );
    } catch (e) {
      print('DEBUG: Direct connection failed: $e');
      setState(() {
        _isConnected = false;
      });
      
      String message = 'Direct connection failed: $e';
      if (e.toString().contains('network') || e.toString().contains('timeout')) {
        message = 'Network error: Cannot reach TSP100 at 10.20.30.125. Check if tablet and printer are on same network.';
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: <Widget>[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Counter Demo',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text('You have pushed the button this many times:'),
                    Text(
                      '$_counter',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 16),
                    const SizedBox(height: 16),
                    Text(
                      'Single Item (between horizontal bars)',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Row(children: [
                      SizedBox(
                        width: 70,
                        child: TextField(
                          controller: _itemQuantityController,
                          decoration: const InputDecoration(
                            labelText: 'Qty',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (v) => setState(() => _itemQuantity = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _itemNameController,
                          decoration: const InputDecoration(
                            labelText: 'Item Name',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) => setState(() => _itemName = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 100,
                        child: TextField(
                          controller: _itemPriceController,
                          decoration: const InputDecoration(
                            labelText: 'Price',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (v) => setState(() => _itemPrice = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 80,
                        child: TextField(
                          controller: _itemRepeatController,
                          decoration: const InputDecoration(
                            labelText: 'Repeat',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (v) => setState(() => _itemRepeat = v),
                        ),
                      ),
                    ]),
                    ElevatedButton(
                      onPressed: _incrementCounter,
                      child: const Text('Increment Counter'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Star Printer Controls',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    Text('Discovered Printers: ${_discoveredPrinters.length}'),
                    if (_discoveredPrinters.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text('Select Printer:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedPrinter,
                            hint: const Text('Select a printer'),
                            isExpanded: true,
                            items: _discoveredPrinters.map((printer) {
                              // Extract model name for display
                              final parts = printer.split(':');
                              final model = parts.length > 2 ? parts[2] : 'Unknown';
                              final mac = parts.length > 1 ? parts[1] : 'Unknown';
                              return DropdownMenuItem<String>(
                                value: printer,
                                child: Text('$model (${mac.substring(0, 8)}...)'),
                              );
                            }).toList(),
                            onChanged: (String? newValue) {
                              setState(() {
                                _selectedPrinter = newValue;
                                _isConnected = false; // Reset connection status when changing printer
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_selectedPrinter != null)
                        Text('Selected: ${_selectedPrinter!}', 
                             style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                    ],
                    const SizedBox(height: 16),
                    // Receipt Layout Controls
                    Text(
                      'Receipt Header/Layout',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _headerController,
                      decoration: const InputDecoration(
                        labelText: 'Header Title',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => setState(() => _headerTitle = v),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text('Header Size'),
                        Expanded(
                          child: Slider(
                            value: _headerFontSize.toDouble(),
                            min: 16,
                            max: 48,
                            divisions: 32,
                            label: _headerFontSize.toString(),
                            onChanged: (v) => setState(() => _headerFontSize = v.round()),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Text('Header Spacing (lines): '),
                        Expanded(
                          child: Slider(
                            value: _headerSpacingLines.toDouble(),
                            min: 0,
                            max: 5,
                            divisions: 5,
                            label: _headerSpacingLines.toString(),
                            onChanged: (v) => setState(() => _headerSpacingLines = v.round()),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _logoBase64 = _sampleLogoBase64;
                            });
                          },
                          child: const Text('Use Sample Logo'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _logoBase64 != null
                              ? () {
                                  setState(() => _logoBase64 = null);
                                }
                              : null,
                          child: const Text('Clear Logo'),
                        ),
                        const SizedBox(width: 8),
                        if (Platform.isIOS || Platform.isAndroid)
                          ElevatedButton(
                            onPressed: _pickReceiptImage,
                            child: Text('Pick Image (${Platform.isIOS ? 'iOS' : 'Android'})'),
                          ),
                      ],
                    ),
                    if (_logoBase64 != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Text('Image Width (px): '),
                          Expanded(
                            child: Slider(
                              value: _imageWidthPx.toDouble(),
                              min: 64,
                              max: 576,
                              divisions: 64,
                              label: _imageWidthPx.toString(),
                              onChanged: (v) => setState(() => _imageWidthPx = v.round()),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          const Text('Image Spacing (lines): '),
                          Expanded(
                            child: Slider(
                              value: _imageSpacingLines.toDouble(),
                              min: 0,
                              max: 5,
                              divisions: 5,
                              label: _imageSpacingLines.toString(),
                              onChanged: (v) => setState(() => _imageSpacingLines = v.round()),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      'Receipt Details',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _locationController,
                      decoration: const InputDecoration(
                        labelText: 'Location Text (centered)',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => setState(() => _locationText = v),
                    ),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _dateController,
                          decoration: const InputDecoration(
                            labelText: 'Date',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) => setState(() => _date = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _timeController,
                          decoration: const InputDecoration(
                            labelText: 'Time',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) => setState(() => _time = v),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _cashierController,
                          decoration: const InputDecoration(
                            labelText: 'Cashier',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) => setState(() => _cashier = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _receiptNumController,
                          decoration: const InputDecoration(
                            labelText: 'Receipt No',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) => setState(() => _receiptNum = v),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _laneController,
                          decoration: const InputDecoration(
                            labelText: 'Lane',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) => setState(() => _lane = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _footerController,
                          decoration: const InputDecoration(
                            labelText: 'Footer',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) => setState(() => _footer = v),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 16),
                    Text(
                      'Label Printer Settings',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text('How Big Is Your Label Printer Paper?', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Radio<int>(
                          value: 38,
                          groupValue: _labelPaperWidthMm,
                          onChanged: (int? value) {
                            setState(() {
                              _labelPaperWidthMm = value ?? 58;
                            });
                          },
                        ),
                        const Text('38mm (1.5")'),
                        const SizedBox(width: 16),
                        Radio<int>(
                          value: 58,
                          groupValue: _labelPaperWidthMm,
                          onChanged: (int? value) {
                            setState(() {
                              _labelPaperWidthMm = value ?? 58;
                            });
                          },
                        ),
                        const Text('58mm (2.25")'),
                        const SizedBox(width: 16),
                        Radio<int>(
                          value: 80,
                          groupValue: _labelPaperWidthMm,
                          onChanged: (int? value) {
                            setState(() {
                              _labelPaperWidthMm = value ?? 58;
                            });
                          },
                        ),
                        const Text('80mm (3.15")'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _labelPaperWidthMm == 38 
                          ? 'Printable area: 34.5mm (vertical layout, all centered)'
                          : _labelPaperWidthMm == 58
                              ? 'Printable area: 48mm (mixed layout)'
                              : 'Printable area: 72mm (horizontal layout)',
                      style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    const Text('Number of Labels to Print:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        SizedBox(
                          width: 100,
                          child: TextField(
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Quantity',
                              border: OutlineInputBorder(),
                            ),
                            controller: TextEditingController(text: _labelQuantity.toString()),
                            onChanged: (v) {
                              final qty = int.tryParse(v) ?? 1;
                              setState(() => _labelQuantity = qty.clamp(1, 100));
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Slider(
                            value: _labelQuantity.toDouble(),
                            min: 1,
                            max: 20,
                            divisions: 19,
                            label: _labelQuantity.toString(),
                            onChanged: (v) => setState(() => _labelQuantity = v.round()),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text('Connection Status: ${_isConnected ? "Connected" : "Disconnected"}'),
                    const SizedBox(height: 8),
                    Text('Printer Status: $_printerStatus'),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Checkbox(
                          value: _openDrawerAfterPrint,
                          onChanged: (bool? value) {
                            setState(() {
                              _openDrawerAfterPrint = value ?? true;
                            });
                          },
                        ),
                        const Expanded(
                          child: Text('Auto-open cash drawer after printing'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ElevatedButton(
                          onPressed: _checkAndRequestPermissions,
                          child: const Text('Check Permissions'),
                        ),
                        ElevatedButton(
                          onPressed: _discoverPrinters,
                          child: const Text('Discover Printers'),
                        ),
                        ElevatedButton(
                          onPressed: _testDirectConnection,
                          child: const Text('Test TSP100 Direct'),
                        ),
                        ElevatedButton(
                          onPressed: _selectedPrinter != null && !_isConnected
                              ? _connectToPrinter
                              : null,
                          child: const Text('Connect'),
                        ),
                        ElevatedButton(
                          onPressed: _isConnected ? _disconnectFromPrinter : null,
                          child: const Text('Disconnect'),
                        ),
                        ElevatedButton(
                          onPressed: _printReceipt,
                          child: const Text('Print Receipt'),
                        ),
                        ElevatedButton(
                          onPressed: _printLabel,
                          child: const Text('Print Label'),
                        ),
                        ElevatedButton(
                          onPressed: _getStatus,
                          child: const Text('Get Status'),
                        ),
                        ElevatedButton(
                          onPressed: _isConnected ? _openCashDrawer : null,
                          child: const Text('Open Cash Drawer'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
