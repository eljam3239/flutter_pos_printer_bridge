import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:epson_printer/epson_printer.dart';
import 'package:star_printer/star_printer.dart';
void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'POS Printer Bridge',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color.fromARGB(255, 15, 126, 52)),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'POS Printer Bridge'),
    );
  }
}

// Enum for printer brands
enum PrinterBrand {
  epson('Epson', 'TM Series & Compatible'),
  star('Star Micronics', 'TSP & mPOP Series'),
  zebra('Zebra', 'ZD & ZQ Series');

  const PrinterBrand(this.displayName, this.description);
  final String displayName;
  final String description;
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  // Printer brand selection
  PrinterBrand? _selectedBrand;
  
  // Common printer state
  List<String> _discoveredPrinters = [];
  bool _isConnected = false;
  String _printerStatus = 'Unknown';
  String? _selectedPrinter;
  bool _openDrawerAfterPrint = true;
  bool _isDiscovering = false; // Epson: prevent concurrent discoveries
  bool _usbWasConnectedThisSession = false; // iOS: track USB use disabling BT on device
  String _nativeDiscoveryState = 'idle'; // Epson native discovery state
  Timer? _statePollTimer; // iOS discovery state polling timer
  
  // Receipt content controllers
  final TextEditingController _headerController = TextEditingController();
  final TextEditingController _detailsController = TextEditingController();
  final TextEditingController _itemsController = TextEditingController();
  final TextEditingController _footerController = TextEditingController();
  final TextEditingController _logoBase64Controller = TextEditingController();
  
  // POS style receipt fields (inspired by both implementations)
  String _headerTitle = "My Store";
  String _locationText = '123 Main Street, City, State';
  String _date = '02/10/2025';
  String _time = '2:39 PM';
  String _cashier = 'Cashier';
  String _receiptNum = '12345';
  String _lane = '1';
  String _footer = 'Thank you for your business!';
  
  // Item fields
  String _itemQuantity = '1';
  String _itemName = 'Sample Item';
  String _itemPrice = '9.99';
  int _itemRepeat = 3;
  
  // Receipt layout settings
  int _posCharsPerLine = 48; // 80mm paper common width
  String? _logoBase64;
  
  // Additional fields from Star implementation
  int _headerFontSize = 32;
  int _headerSpacingLines = 1;
  int _imageWidthPx = 200;
  int _imageSpacingLines = 1;

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    _checkAndRequestPermissions();
    // Epson iOS: poll native discovery state to keep _nativeDiscoveryState fresh
    if (Platform.isIOS) {
      _startDiscoveryStatePolling();
    }
  }

  void _initializeControllers() {
    _headerController.text = _headerTitle + '\n' + _locationText;
    _detailsController.text = 'Order: $_receiptNum\nDate: $_date $_time\nCashier: $_cashier\nLane: $_lane';
    _itemsController.text = '${_itemQuantity}x $_itemName @$_itemPrice';
    _footerController.text = _footer;
  }

  @override
  void dispose() {
    _headerController.dispose();
    _detailsController.dispose();
    _itemsController.dispose();
    _footerController.dispose();
    _logoBase64Controller.dispose();
    _statePollTimer?.cancel();
    super.dispose();
  }

  // Poll Epson native discovery state on iOS for better orchestration feedback
  void _startDiscoveryStatePolling() {
    _statePollTimer?.cancel();
    _statePollTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      try {
        final state = await EpsonPrinter.getDiscoveryState();
        final nativeState = (state['state'] as String?) ?? 'unknown';
        final usbFlag = state['usbWasConnectedThisSession'] == true;
        if (!mounted) return;
        setState(() {
          _nativeDiscoveryState = nativeState;
          // Once USB flagged true this session, keep it true on iOS
          if (Platform.isIOS && (usbFlag || _usbWasConnectedThisSession)) {
            _usbWasConnectedThisSession = true;
          } else {
            _usbWasConnectedThisSession = usbFlag;
          }
        });
      } catch (_) {
        // ignore polling errors
      }
    });
  }

  Future<void> _checkAndRequestPermissions() async {
    if (Platform.isAndroid) {
      final bluetoothStatus = await Permission.bluetoothConnect.status;
      final bluetoothScanStatus = await Permission.bluetoothScan.status;

      if (!bluetoothStatus.isGranted || !bluetoothScanStatus.isGranted) {
        final results = await [
          Permission.bluetoothConnect,
          Permission.bluetoothScan,
          Permission.location,
        ].request();

        if (results[Permission.bluetoothConnect]?.isGranted != true ||
            results[Permission.bluetoothScan]?.isGranted != true) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Bluetooth permissions are required for printer discovery'),
                duration: Duration(seconds: 5),
              ),
            );
          }
        }
      }
    }
  }

  // Placeholder methods that will be wired to specific printer implementations later
  Future<void> _discoverPrinters() async {
    if (_selectedBrand == null) {
      _showBrandSelectionSnackBar();
      return;
    }

    // Enforce Epson rule: do not run discovery while connected
    if (_selectedBrand == PrinterBrand.epson && _isConnected) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Disconnect from Epson printer before discovering new devices')),
      );
      return;
    }

    // Clear previous discovery results and reset state
    setState(() {
      _discoveredPrinters = <String>[];
      _selectedPrinter = null;
    });

    try {
      switch (_selectedBrand!) {
        case PrinterBrand.epson:
          await _discoverEpsonPrintersStaged();
          break;
        case PrinterBrand.star:
          try {
            print('DEBUG: Starting printer discovery...');
            
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
              _discoveredPrinters = List<String>.from(printers); // Create growable list
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
          break;
        case PrinterBrand.zebra:
          // TODO: Implement Zebra discovery when available
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Zebra printer discovery not yet implemented')),
          );
          break;
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Discovery failed: $e')),
      );
    }
  }

  // Epson discovery orchestrator: LAN -> Bluetooth -> USB with iOS-specific behavior
  Future<void> _discoverEpsonPrintersStaged() async {
    // Prevent concurrent discoveries (both local flag and native state)
    if (_isDiscovering || _nativeDiscoveryState != 'idle') {
      debugPrint('Epson discovery already in progress or native state not idle ($_nativeDiscoveryState)');
      return;
    }

    // Warn if still connected
    if (_isConnected) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please disconnect from printer before discovering new printers'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    // Prime native state once before starting (best-effort)
    try {
      final native = await EpsonPrinter.getDiscoveryState();
      _nativeDiscoveryState = (native['state'] as String?) ?? 'idle';
      if (_nativeDiscoveryState != 'idle') return; // bail if native busy
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _isDiscovering = true;
    });

    // Inform user
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Discovering printers (LAN${Platform.isIOS ? ', USB' : ', Bluetooth, USB'})...')),
    );

    final List<String> snapshot = [];
    int totalFound = 0;

    // Discover LAN printers first
    try {
      final lanPrinters = await EpsonPrinter.discoverPrinters();
      snapshot.addAll(lanPrinters);
      totalFound += lanPrinters.length;
      debugPrint('Epson LAN discovery found ${lanPrinters.length}');
    } catch (e) {
      debugPrint('Epson LAN discovery error: $e');
    }

    // Small delay to let SDK clean up between discoveries
    await Future.delayed(const Duration(milliseconds: 500));

    // Discover Bluetooth unless iOS had USB this session (printer disables BT radio)
    if (!(Platform.isIOS && _usbWasConnectedThisSession)) {
      try {
        if (Platform.isAndroid) {
          final bluetoothConnectStatus = await Permission.bluetoothConnect.status;
          final bluetoothScanStatus = await Permission.bluetoothScan.status;
          if (!bluetoothConnectStatus.isGranted || !bluetoothScanStatus.isGranted) {
            await _checkAndRequestPermissions();
          }
        }
        final btPrinters = await EpsonPrinter.discoverBluetoothPrinters();
        snapshot.addAll(btPrinters);
        totalFound += btPrinters.length;
        debugPrint('Epson Bluetooth discovery found ${btPrinters.length}');
      } catch (e) {
        debugPrint('Epson Bluetooth discovery error: $e');
      }
    } else {
      debugPrint('iOS: Skipping Epson Bluetooth discovery - USB used this session');
    }

    // Small delay before USB
    await Future.delayed(const Duration(milliseconds: 500));

    // Discover USB printers last
    try {
      final usbPrinters = await EpsonPrinter.discoverUsbPrinters();
      if (Platform.isIOS && usbPrinters.isNotEmpty) {
        _usbWasConnectedThisSession = true; // mark session flag
        debugPrint('iOS: USB discovered - Bluetooth hardware now disabled on printer');
      }
      snapshot.addAll(usbPrinters);
      totalFound += usbPrinters.length;
      debugPrint('Epson USB discovery found ${usbPrinters.length}');
    } catch (e) {
      debugPrint('Epson USB discovery error: $e');
    }

    // iOS filter: if USB was ever connected, hide BT/BLE entries
    if (Platform.isIOS && _usbWasConnectedThisSession) {
      snapshot.removeWhere((p) => p.startsWith('BT:') || p.startsWith('BLE:'));
    }

    if (!mounted) return;
    setState(() {
      _isDiscovering = false;
      _discoveredPrinters = List<String>.from(snapshot);
      if (_selectedPrinter == null || !_discoveredPrinters.contains(_selectedPrinter)) {
        _selectedPrinter = _discoveredPrinters.isNotEmpty ? _discoveredPrinters.first : null;
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Discovery complete! Found $totalFound total printers')),
    );
  }

  Future<void> _connectToPrinter() async {
    if (_selectedBrand == null) {
      _showBrandSelectionSnackBar();
      return;
    }

    if (_selectedPrinter == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a printer first.')),
      );
      return;
    }

    try {
      switch (_selectedBrand!) {
        case PrinterBrand.epson:
          if (_discoveredPrinters.isEmpty) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No printers discovered. Please discover printers first.')),
            );
            return;
          }
          if (_selectedPrinter == null) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Please select a printer first.')),
            );
            return;
          }

          try {
            if (_isConnected) {
              await EpsonPrinter.disconnect();
              setState(() => _isConnected = false);
              await Future.delayed(const Duration(milliseconds: 500));
            }

            final printerString = _selectedPrinter!;
            final lastColonIndex = printerString.lastIndexOf(':');
            String target = lastColonIndex != -1
                ? printerString.substring(0, lastColonIndex)
                : printerString;

            EpsonPortType interfaceType;
            final macRegex = RegExp(r'^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$');
            if (target.startsWith('TCP:') || target.startsWith('TCPS:')) {
              interfaceType = EpsonPortType.tcp;
            } else if (target.startsWith('BT:')) {
              interfaceType = EpsonPortType.bluetooth;
            } else if (target.startsWith('BLE:')) {
              interfaceType = EpsonPortType.bluetoothLe;
            } else if (target.startsWith('USB:')) {
              interfaceType = EpsonPortType.usb;
            } else if (macRegex.hasMatch(target)) {
              interfaceType = EpsonPortType.bluetooth;
              target = 'BT:$target';
            } else {
              interfaceType = EpsonPortType.tcp;
            }

            final settings = EpsonConnectionSettings(
              portType: interfaceType,
              identifier: target,
              timeout: interfaceType == EpsonPortType.bluetoothLe ? 30000 : 15000,
            );

            await EpsonPrinter.connect(settings);
            setState(() => _isConnected = true);
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Connected to: ${_selectedPrinter!.split(':').last}')),
            );
          } catch (e) {
            setState(() => _isConnected = false);
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Connection failed: $e')),
            );
          }
          break;
        case PrinterBrand.star:
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
          break;
        case PrinterBrand.zebra:
          // TODO: Implement Zebra connection when available
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Zebra printer connection not yet implemented')),
          );
          break;
      }
    } catch (e) {
      setState(() => _isConnected = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connection failed: $e')),
      );
    }
  }

  Future<void> _printReceipt() async {
    if (_selectedBrand == null) {
      _showBrandSelectionSnackBar();
      return;
    }

    if (!_isConnected) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please connect to a printer first')),
      );
      return;
    }

    try {
      switch (_selectedBrand!) {
        case PrinterBrand.epson:
          await _printEpsonReceipt();
          break;
        case PrinterBrand.star:
          await _printStarReceipt();
          break;
        case PrinterBrand.zebra:
          // TODO: Implement Zebra printing when available
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Zebra printer printing not yet implemented')),
          );
          break;
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Print failed: $e')),
      );
    }
  }

  Future<void> _printEpsonReceipt() async {
    // Use POS style receipt building (like epsonmain.dart)
    final commands = _buildEpsonPosReceiptCommands();
    
    if (commands.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('POS receipt has no content.')),
      );
      return;
    }

    final printJob = EpsonPrintJob(commands: commands);
    await EpsonPrinter.printReceipt(printJob);

    if (_openDrawerAfterPrint && _isConnected) {
      try {
        await EpsonPrinter.openCashDrawer();
      } catch (_) {}
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_openDrawerAfterPrint ? 'Epson POS receipt sent and drawer opened' : 'Epson POS receipt sent successfully')),
    );
  }

  Future<void> _printStarReceipt() async {
    print('DEBUG: Print receipt button pressed');
    
    print('DEBUG: Creating print job...');
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
        },
        'items': List.generate(_itemRepeat, (index) => {
          'quantity': _itemQuantity,
          'name': _itemName,
          'price': _itemPrice,
        }),
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
      content: '',
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
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_openDrawerAfterPrint 
          ? 'Star print job sent and drawer opened' 
          : 'Star print job sent successfully')),
    );
  }

  // Build EpsonPrintCommand list for POS style receipt (from epsonmain.dart)
  List<EpsonPrintCommand> _buildEpsonPosReceiptCommands() {
    final List<EpsonPrintCommand> cmds = [];

    int _estimatePrinterDots() {
      // Rough heuristic mapping from characters-per-line to dot width.
      if (_posCharsPerLine <= 32) return 384;   // 58mm common
      if (_posCharsPerLine <= 42) return 512;   // 72mm or dense 58mm fonts
      if (_posCharsPerLine <= 48) return 576;   // 80mm Font A
      if (_posCharsPerLine <= 56) return 640;   // Some 3" models
      if (_posCharsPerLine <= 64) return 832;   // 80mm Font B / high density
      return 576; // fallback
    }
    final printerWidthDots = _estimatePrinterDots();

    String title = _headerTitle.trim();
    if (title.isNotEmpty) {
      // Make header larger by adding spacing and emphasis
      cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'data': _center('$title') + '\n' }));
      if (_logoBase64 != null && _logoBase64!.isNotEmpty) {
        // Persist logo to temp file for native side
        try {
          final bytes = base64Decode(_logoBase64!);
          // NOTE: Synchronous write acceptable for small logo; could be pre-written earlier.
          final tmpDir = Directory.systemTemp;
          final file = File('${tmpDir.path}/epson_logo_${DateTime.now().millisecondsSinceEpoch}.png');
          file.writeAsBytesSync(bytes, flush: true);
          cmds.add(EpsonPrintCommand(type: EpsonCommandType.image, parameters: {
            'imagePath': file.path,
            'printerWidth': printerWidthDots,
            'targetWidth': _imageWidthPx, // allow native scaling
            'align': 'center',
            'advancedProcessing': false,
          }));
          if (_imageSpacingLines > 0) {
            cmds.add(EpsonPrintCommand(type: EpsonCommandType.feed, parameters: { 'line': _imageSpacingLines }));
          }
        } catch (_) {
          // Fallback marker if file write fails
          cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'data': _center('[LOGO ERR]') + '\n' }));
        }
      }
      if (_headerSpacingLines > 0) {
        cmds.add(EpsonPrintCommand(type: EpsonCommandType.feed, parameters: { 'line': _headerSpacingLines }));
      }
    }

    if (_locationText.trim().isNotEmpty) {
      cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'data': _center(_locationText.trim()) + '\n' }));
    }

    // Centered 'Receipt'
    cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'data': '\n' + _center('Receipt') + '\n' }));

    // Date Time (left) vs Cashier (right)
    final dateTime = '${_date.trim()} ${_time.trim()}';
    final cashierStr = 'Cashier: ${_cashier.trim()}';
    cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'data': _leftRight(dateTime, cashierStr) + '\n' }));

    // Receipt # vs Lane
    final recLine = 'Receipt: ${_receiptNum.trim()}';
    final laneLine = 'Lane: ${_lane.trim()}';
    cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'data': _leftRight(recLine, laneLine) + '\n' }));

    // Blank line
    cmds.add(EpsonPrintCommand(type: EpsonCommandType.feed, parameters: { 'line': 1 }));

    // Horizontal line
    cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'data': _horizontalLine() + '\n' }));

    // Items repeated
    final repeatCount = _itemRepeat;
    for (int i = 0; i < repeatCount; i++) {
      cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'data': _qtyNamePrice(_itemQuantity, _itemName, _itemPrice) + '\n' }));
    }

    // Second horizontal line
    cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'data': _horizontalLine() + '\n' }));

    if (_footer.trim().isNotEmpty) {
      cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'data': _center(_footer.trim()) + '\n' }));
    }

    // End feeds + cut
    cmds.add(EpsonPrintCommand(type: EpsonCommandType.feed, parameters: { 'line': 2 }));
    cmds.add(EpsonPrintCommand(type: EpsonCommandType.cut, parameters: {}));
    return cmds;
  }

  // ===================== POS Receipt Formatting Helpers =====================
  String _center(String text) {
    text = text.trim();
    if (text.isEmpty) return '';
    if (text.length >= _posCharsPerLine) return text;
    final totalPad = _posCharsPerLine - text.length;
    final left = (totalPad / 2).floor();
    final right = totalPad - left;
    return ' ' * left + text + ' ' * right;
  }

  String _horizontalLine() => '-' * _posCharsPerLine;

  String _leftRight(String left, String right) {
    left = left.trim();
    right = right.trim();
    final space = _posCharsPerLine - left.length - right.length;
    if (space < 1) {
      final maxLeft = _posCharsPerLine - right.length - 1;
      if (maxLeft < 1) return (left + right).substring(0, _posCharsPerLine);
      left = left.substring(0, maxLeft);
      return '$left ${right}';
    }
    return left + ' ' * space + right;
  }

  String _qtyNamePrice(String qty, String name, String price) {
    // Layout: qty with 'x' (4 chars) name (left) price (right) within paper width.
    qty = qty.trim();
    name = name.trim();
    price = price.trim();
    const qtyWidth = 4; // e.g. '99x '
    const priceWidth = 8; // enough for large price
    final qtyStr = qty.length > 2 ? qty.substring(0, 2) : qty;
    final qtyField = '${qtyStr} x'.padRight(qtyWidth);
    // Remaining width for name = total - qtyWidth - priceWidth
    final nameWidth = _posCharsPerLine - qtyWidth - priceWidth;
    String nameTrunc = name;
    if (nameTrunc.length > nameWidth) nameTrunc = nameTrunc.substring(0, nameWidth);
    final priceField = price.padLeft(priceWidth);
    return qtyField + nameTrunc.padRight(nameWidth) + priceField;
  }
  // ==========================================================================

  Future<void> _disconnectFromPrinter() async {
    try {
      if (_selectedBrand != null && _isConnected) {
        switch (_selectedBrand!) {
          case PrinterBrand.epson:
            await EpsonPrinter.disconnect();
            break;
          case PrinterBrand.star:
            await StarPrinter.disconnect();
            break;
          case PrinterBrand.zebra:
            // TODO: Wire Zebra disconnect when available
            break;
        }
      }
      
      setState(() => _isConnected = false);
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Disconnected from printer')),
      );
    } catch (e) {
      setState(() => _isConnected = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Disconnect failed: $e')),
      );
    }
  }

  Future<void> _getStatus() async {
    if (_selectedBrand == null) {
      _showBrandSelectionSnackBar();
      return;
    }

    try {
      switch (_selectedBrand!) {
        case PrinterBrand.epson:
          final status = await EpsonPrinter.getStatus();
          setState(() {
            _printerStatus = 'Online: ${status.isOnline}, Status: ${status.status}';
          });
          break;
        case PrinterBrand.star:
          final status = await StarPrinter.getStatus();
          setState(() {
            _printerStatus = 'Online: ${status.isOnline}, Status: ${status.status}';
          });
          break;
        case PrinterBrand.zebra:
          // TODO: Implement Zebra status when available
          setState(() {
            _printerStatus = 'Zebra status not yet implemented';
          });
          break;
      }
    } catch (e) {
      setState(() {
        _printerStatus = 'Error: $e';
      });
    }
  }

  Future<void> _openCashDrawer() async {
    if (_selectedBrand == null) {
      _showBrandSelectionSnackBar();
      return;
    }

    if (!_isConnected) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please connect to a printer first')),
      );
      return;
    }

    try {
      switch (_selectedBrand!) {
        case PrinterBrand.epson:
          await EpsonPrinter.openCashDrawer();
          break;
        case PrinterBrand.star:
          print('DEBUG: Opening cash drawer...');
          await StarPrinter.openCashDrawer();
          print('DEBUG: Cash drawer command sent successfully');
          break;
        case PrinterBrand.zebra:
          // TODO: Implement Zebra cash drawer when available
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Zebra cash drawer not yet implemented')),
          );
          return;
      }
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cash drawer opened')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cash drawer failed: $e')),
      );
    }
  }

  Future<void> _pickLogoImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery, maxWidth: 300);
    if (image == null) return;
    
    try {
      final bytes = await image.readAsBytes();
      final b64 = base64Encode(bytes);
      setState(() {
        _logoBase64 = b64;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Logo pick failed: $e')));
    }
  }

  void _showBrandSelectionSnackBar() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Please select a printer brand first')),
    );
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
          children: [
            // Brand Selection Card
            _buildBrandSelectionCard(),
            const SizedBox(height: 16),
            
            // Printer Connection Card
            _buildConnectionCard(),
            const SizedBox(height: 16),
            
            // Receipt Layout Card - Commented out as we now use POS style for both brands
            // _buildReceiptLayoutCard(),
            // const SizedBox(height: 16),
            
            // POS Style Receipt Card
            _buildPosReceiptCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildBrandSelectionCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.print, color: Theme.of(context).primaryColor),
                const SizedBox(width: 8),
                Text('Select Printer Brand', style: Theme.of(context).textTheme.headlineSmall),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<PrinterBrand>(
              value: _selectedBrand,
              decoration: const InputDecoration(
                labelText: 'Printer Brand',
                border: OutlineInputBorder(),
                helperText: 'Choose your printer manufacturer',
              ),
              items: PrinterBrand.values.map((brand) {
                return DropdownMenuItem(
                  value: brand,
                  child: Text(brand.displayName),
                );
              }).toList(),
              onChanged: (PrinterBrand? newValue) async {
                if (newValue == _selectedBrand) return; // No change
                
                // If currently connected, disconnect first regardless of brand
                if (_isConnected) {
                  try {
                    print('DEBUG: Disconnecting from current printer before brand switch...');
                    await _disconnectFromPrinter();
                    print('DEBUG: Successfully disconnected from current printer');
                    // Add a small delay to ensure disconnect completes
                    await Future.delayed(const Duration(milliseconds: 500));
                  } catch (e) {
                    print('DEBUG: Failed to disconnect when switching brands: $e');
                    // Continue with brand switch even if disconnect fails
                  }
                }
                
                setState(() {
                  _selectedBrand = newValue;
                  // Reset ALL printer state when brand changes
                  _discoveredPrinters = <String>[]; // Create new empty growable list
                  _selectedPrinter = null;
                  _isConnected = false;
                  _printerStatus = 'Unknown';
                });
                
                print('DEBUG: Brand switched to ${newValue?.displayName ?? "None"}. State reset complete.');
              },
            ),
            if (_selectedBrand != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Theme.of(context).primaryColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Selected: ${_selectedBrand!.displayName} - ${_selectedBrand!.description}',
                        style: TextStyle(color: Theme.of(context).primaryColor),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _isConnected ? Icons.wifi : Icons.wifi_off,
                  color: _isConnected ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Text('Printer Connection', style: Theme.of(context).textTheme.headlineSmall),
              ],
            ),
            const SizedBox(height: 16),
            
            // Discovery and Connection buttons
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: (_selectedBrand != null && !(
                            (_selectedBrand == PrinterBrand.epson && _isConnected) ||
                            (_selectedBrand == PrinterBrand.epson && _isDiscovering)
                          )) ? _discoverPrinters : null,
                  icon: const Icon(Icons.search),
                  label: const Text('Discover'),
                ),
                ElevatedButton.icon(
                  onPressed: _selectedBrand != null && _discoveredPrinters.isNotEmpty ? _connectToPrinter : null,
                  icon: const Icon(Icons.link),
                  label: const Text('Connect'),
                ),
                ElevatedButton.icon(
                  onPressed: _isConnected ? _disconnectFromPrinter : null,
                  icon: const Icon(Icons.link_off),
                  label: const Text('Disconnect'),
                ),
                ElevatedButton.icon(
                  onPressed: _selectedBrand != null ? _getStatus : null,
                  icon: const Icon(Icons.info),
                  label: const Text('Status'),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Printer selection dropdown
            if (_discoveredPrinters.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                value: _selectedPrinter,
                decoration: const InputDecoration(
                  labelText: 'Select Printer',
                  border: OutlineInputBorder(),
                ),
                items: _discoveredPrinters.map((printer) {
                  return DropdownMenuItem(
                    value: printer,
                    child: Text(printer),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    _selectedPrinter = newValue;
                  });
                },
              ),
              const SizedBox(height: 8),
            ],
            
            // Status display
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _isConnected ? Colors.green.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    _isConnected ? Icons.check_circle : Icons.error,
                    color: _isConnected ? Colors.green : Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isConnected ? 'Connected: $_printerStatus' : 'Not connected',
                      style: TextStyle(
                        color: _isConnected ? Colors.green : Colors.grey,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Print and cash drawer controls
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: _selectedBrand != null && _isConnected ? _printReceipt : null,
                  icon: const Icon(Icons.print),
                  label: const Text('Print Receipt'),
                ),
                ElevatedButton.icon(
                  onPressed: _selectedBrand != null && _isConnected ? _openCashDrawer : null,
                  icon: const Icon(Icons.point_of_sale),
                  label: const Text('Open Drawer'),
                ),
              ],
            ),
            
            const SizedBox(height: 8),
            
            // Open drawer after print option
            CheckboxListTile(
              title: const Text('Open cash drawer after printing'),
              value: _openDrawerAfterPrint,
              onChanged: (bool? value) {
                setState(() {
                  _openDrawerAfterPrint = value ?? true;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  // Receipt Layout Card method - Commented out as we now use POS style for both brands
  // Widget _buildReceiptLayoutCard() {
  //   return Card(
  //     child: Padding(
  //       padding: const EdgeInsets.all(16.0),
  //       child: Column(
  //         crossAxisAlignment: CrossAxisAlignment.start,
  //         children: [
  //           Row(
  //             children: [
  //               Icon(Icons.receipt_long, color: Theme.of(context).primaryColor),
  //               const SizedBox(width: 8),
  //               Text('Receipt Layout', style: Theme.of(context).textTheme.headlineSmall),
  //             ],
  //           ),
  //           const SizedBox(height: 16),
  //           
  //           TextField(
  //             controller: _headerController,
  //             decoration: const InputDecoration(
  //               labelText: 'Header',
  //               border: OutlineInputBorder(),
  //               helperText: 'Store name, address, etc.',
  //             ),
  //             maxLines: 3,
  //           ),
  //           const SizedBox(height: 12),
  //           
  //           TextField(
  //             controller: _detailsController,
  //             decoration: const InputDecoration(
  //               labelText: 'Details',
  //               border: OutlineInputBorder(),
  //               helperText: 'Order number, date, etc.',
  //             ),
  //             maxLines: 3,
  //           ),
  //           const SizedBox(height: 12),
  //           
  //           TextField(
  //             controller: _itemsController,
  //             decoration: const InputDecoration(
  //               labelText: 'Items',
  //               border: OutlineInputBorder(),
  //               helperText: 'Line items (e.g., "2x Coffee @3.50")',
  //             ),
  //             maxLines: 5,
  //           ),
  //           const SizedBox(height: 12),
  //           
  //           TextField(
  //             controller: _footerController,
  //             decoration: const InputDecoration(
  //               labelText: 'Footer',
  //               border: OutlineInputBorder(),
  //               helperText: 'Thank you message, etc.',
  //             ),
  //             maxLines: 2,
  //           ),
  //           const SizedBox(height: 16),
  //           
  //           Row(
  //             children: [
  //               Expanded(
  //                 child: ElevatedButton.icon(
  //                   onPressed: _pickLogoImage,
  //                   icon: const Icon(Icons.image),
  //                   label: const Text('Pick Logo'),
  //                 ),
  //               ),
  //               const SizedBox(width: 8),
  //               if (_logoBase64 != null)
  //                 Container(
  //                   width: 40,
  //                   height: 40,
  //                   decoration: BoxDecoration(
  //                     border: Border.all(color: Colors.grey),
  //                     borderRadius: BorderRadius.circular(4),
  //                   ),
  //                   child: const Icon(Icons.check, color: Colors.green),
  //                 ),
  //             ],
  //           ),
  //         ],
  //       ),
  //     ),
  //   );
  // }

  Widget _buildPosReceiptCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.point_of_sale, color: Theme.of(context).primaryColor),
                const SizedBox(width: 8),
                Text('POS Style Receipt', style: Theme.of(context).textTheme.headlineSmall),
              ],
            ),
            const SizedBox(height: 16),
            
            // Store info
            TextField(
              decoration: const InputDecoration(
                labelText: 'Store Name',
                border: OutlineInputBorder(),
              ),
              controller: TextEditingController(text: _headerTitle),
              onChanged: (value) => _headerTitle = value,
            ),
            const SizedBox(height: 12),
            
            TextField(
              decoration: const InputDecoration(
                labelText: 'Location',
                border: OutlineInputBorder(),
              ),
              controller: TextEditingController(text: _locationText),
              onChanged: (value) => _locationText = value,
            ),
            const SizedBox(height: 12),
            
            // Receipt details in two columns
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Date',
                      border: OutlineInputBorder(),
                    ),
                    controller: TextEditingController(text: _date),
                    onChanged: (value) => _date = value,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Time',
                      border: OutlineInputBorder(),
                    ),
                    controller: TextEditingController(text: _time),
                    onChanged: (value) => _time = value,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Cashier',
                      border: OutlineInputBorder(),
                    ),
                    controller: TextEditingController(text: _cashier),
                    onChanged: (value) => _cashier = value,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Receipt #',
                      border: OutlineInputBorder(),
                    ),
                    controller: TextEditingController(text: _receiptNum),
                    onChanged: (value) => _receiptNum = value,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Sample item configuration
            Text('Sample Item Configuration', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            
            Row(
              children: [
                Expanded(
                  flex: 1,
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Qty',
                      border: OutlineInputBorder(),
                    ),
                    controller: TextEditingController(text: _itemQuantity),
                    onChanged: (value) => _itemQuantity = value,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Item Name',
                      border: OutlineInputBorder(),
                    ),
                    controller: TextEditingController(text: _itemName),
                    onChanged: (value) => _itemName = value,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Price',
                      border: OutlineInputBorder(),
                    ),
                    controller: TextEditingController(text: _itemPrice),
                    onChanged: (value) => _itemPrice = value,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Item repeat slider
            Row(
              children: [
                const Text('Repeat: '),
                Expanded(
                  child: Slider(
                    value: _itemRepeat.toDouble(),
                    min: 1,
                    max: 10,
                    divisions: 9,
                    label: _itemRepeat.toString(),
                    onChanged: (double value) {
                      setState(() {
                        _itemRepeat = value.round();
                      });
                    },
                  ),
                ),
                Text('$_itemRepeat times'),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Footer
            TextField(
              decoration: const InputDecoration(
                labelText: 'Footer Message',
                border: OutlineInputBorder(),
              ),
              controller: TextEditingController(text: _footer),
              onChanged: (value) => _footer = value,
            ),
            
            const SizedBox(height: 16),
            
            // Logo Image section
            Text('Receipt Logo', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _pickLogoImage,
                    icon: const Icon(Icons.image),
                    label: const Text('Pick Logo Image'),
                  ),
                ),
                const SizedBox(width: 8),
                if (_logoBase64 != null)
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(Icons.check, color: Colors.green),
                  ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Paper width configuration
            Text('Paper Configuration', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Characters per line: '),
                Expanded(
                  child: Slider(
                    value: _posCharsPerLine.toDouble(),
                    min: 32,
                    max: 64,
                    divisions: 8,
                    label: _posCharsPerLine.toString(),
                    onChanged: (double value) {
                      setState(() {
                        _posCharsPerLine = value.round();
                      });
                    },
                  ),
                ),
                Text('$_posCharsPerLine'),
              ],
            ),
            Text(
              'Common: 32 (58mm), 48 (80mm Font A), 64 (80mm Font B)',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
