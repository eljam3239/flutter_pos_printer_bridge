import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:epson_printer/epson_printer.dart';
import 'package:star_printer/star_printer.dart' as star;
import 'package:zebra_printer/zebra_printer.dart';
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
  
  // Star label printer controls
  int _labelPaperWidthMm = 58; // Default to 58mm
  int _labelQuantity = 1; // Number of labels to print
  
  // Epson label printing controls
  String _epsonLabelPaperWidth = '80mm'; // Default to 80mm for Epson
  final List<String> _availableEpsonPaperWidths = ['58mm', '60mm', '70mm', '76mm', '80mm'];
  int _epsonLabelQuantity = 1;
  
  // Epson label content controllers
  final TextEditingController _epsonLabelProductNameController = TextEditingController();
  final TextEditingController _epsonLabelPriceController = TextEditingController();
  final TextEditingController _epsonLabelSizeColourController = TextEditingController();
  final TextEditingController _epsonLabelScancodeController = TextEditingController();
  
  // Zebra printer specific state
  List<DiscoveredPrinter> _zebraDiscoveredPrinters = [];
  DiscoveredPrinter? _selectedZebraPrinter;
  ConnectedPrinter? _connectedZebraPrinter;
  int _zebraLabelQuantity = 1;
  final TextEditingController _zebraLabelQuantityController = TextEditingController();
  
  // Zebra label content controllers
  final TextEditingController _zebraLabelProductNameController = TextEditingController();
  final TextEditingController _zebraLabelColorSizeController = TextEditingController();
  final TextEditingController _zebraLabelScancodeController = TextEditingController();
  final TextEditingController _zebraLabelPriceController = TextEditingController();
  
  // Zebra receipt form controllers
  final TextEditingController _zebraStoreNameController = TextEditingController();
  final TextEditingController _zebraStoreAddressController = TextEditingController();
  final TextEditingController _zebraStorePhoneController = TextEditingController();
  final TextEditingController _zebraReceiptNumberController = TextEditingController();
  final TextEditingController _zebraCashierNameController = TextEditingController();
  final TextEditingController _zebraLaneNumberController = TextEditingController();
  final TextEditingController _zebraThankYouMessageController = TextEditingController();
  List<Map<String, TextEditingController>> _zebraLineItemControllers = [];
  bool _zebraShowReceiptForm = false;
  
  // MAC address for direct BLE connection (Android only)
  String _zebraMacAddress = '';
  final TextEditingController _zebraMacAddressController = TextEditingController();
  
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
    
    // Initialize Epson label controllers
    _epsonLabelProductNameController.text = 'Sample Product';
    _epsonLabelPriceController.text = '\$5.00';
    _epsonLabelSizeColourController.text = 'Small Turquoise';
    _epsonLabelScancodeController.text = '123456789';
    
    // Initialize Zebra controllers
    _zebraLabelProductNameController.text = 'T-Shirt';
    _zebraLabelColorSizeController.text = 'Small Turquoise';
    _zebraLabelScancodeController.text = '123456789';
    _zebraLabelPriceController.text = '\$5.00';
    
    // Initialize Zebra receipt controllers
    _zebraStoreNameController.text = 'My Store';
    _zebraStoreAddressController.text = '123 Main Street, City, State';
    _zebraStorePhoneController.text = '(555) 123-4567';
    _zebraReceiptNumberController.text = '12345';
    _zebraCashierNameController.text = 'John Doe';
    _zebraLaneNumberController.text = '1';
    _zebraThankYouMessageController.text = 'Thank you for shopping with us!';
    _zebraLabelQuantityController.text = _zebraLabelQuantity.toString();
    _addZebraLineItem(); // Add initial line item
  }

  @override
  void dispose() {
    _headerController.dispose();
    _detailsController.dispose();
    _itemsController.dispose();
    _footerController.dispose();
    _logoBase64Controller.dispose();
    _epsonLabelProductNameController.dispose();
    _epsonLabelPriceController.dispose();
    _epsonLabelSizeColourController.dispose();
    _epsonLabelScancodeController.dispose();
    
    // Dispose Zebra controllers
    _zebraLabelProductNameController.dispose();
    _zebraLabelColorSizeController.dispose();
    _zebraLabelScancodeController.dispose();
    _zebraLabelPriceController.dispose();
    _zebraStoreNameController.dispose();
    _zebraStoreAddressController.dispose();
    _zebraStorePhoneController.dispose();
    _zebraReceiptNumberController.dispose();
    _zebraCashierNameController.dispose();
    _zebraLaneNumberController.dispose();
    _zebraThankYouMessageController.dispose();
    _zebraLabelQuantityController.dispose();
    _zebraMacAddressController.dispose();
    
    // Dispose Zebra line item controllers
    for (var controllerMap in _zebraLineItemControllers) {
      controllerMap['quantity']?.dispose();
      controllerMap['item']?.dispose();
      controllerMap['price']?.dispose();
    }
    
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
    // Only check Bluetooth permissions on Android - iOS handles this differently
    if (Platform.isAndroid) {
      // Check if we need to request Bluetooth permissions
      final bluetoothStatus = await Permission.bluetoothConnect.status;
      final bluetoothScanStatus = await Permission.bluetoothScan.status;

      if (!bluetoothStatus.isGranted || !bluetoothScanStatus.isGranted) {
        print('DEBUG: Bluetooth permissions not granted, requesting...');
        
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

  // Zebra helper methods
  void _addZebraLineItem() {
    setState(() {
      _zebraLineItemControllers.add({
        'quantity': TextEditingController(),
        'item': TextEditingController(),
        'price': TextEditingController(),
      });
    });
  }

  void _removeZebraLineItem(int index) {
    if (_zebraLineItemControllers.length > 1) {
      setState(() {
        _zebraLineItemControllers[index]['quantity']?.dispose();
        _zebraLineItemControllers[index]['item']?.dispose();
        _zebraLineItemControllers[index]['price']?.dispose();
        _zebraLineItemControllers.removeAt(index);
      });
    }
  }

  void _clearZebraDiscoveries() {
    if (_isConnected && _selectedBrand == PrinterBrand.zebra) {
      _disconnectFromPrinter();
    }
    
    setState(() {
      _zebraDiscoveredPrinters.clear();
      _selectedZebraPrinter = null;
      _connectedZebraPrinter = null;
    });
    
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cleared Zebra printer discoveries')),
    );
  }

  // Zebra comprehensive discovery method from zebramain.dart
  Future<void> _discoverZebraAll() async {
    // Clear discoveries at the beginning of the comprehensive discovery
    setState(() {
      _zebraDiscoveredPrinters.clear();
      _discoveredPrinters = <String>[];
      _selectedPrinter = null;
      _selectedZebraPrinter = null;
    });
    
    //if iOS, skip USB discovery
    if (Platform.isIOS) {
      await _discoverZebraNetworkPrintersAuto();
      await _discoverZebraBluetoothPrinters();
      return;
    } else {
      // Android - do all discoveries
      await _discoverZebraUsbPrinters();
      await _discoverZebraNetworkPrintersAuto();
      await _discoverZebraBluetoothPrinters();
      return;
    }
  }

  Future<void> _discoverZebraNetworkPrintersAuto() async {
    setState(() {
      _isDiscovering = true;
    });

    try {
      print('[Flutter] Starting automatic network discovery...');
      final printers = await ZebraPrinter.discoverNetworkPrintersAuto();
      print('[Flutter] Auto discovery completed. Found ${printers.length} printers');
      
      setState(() {
        // Add new printers - allow duplicates for different interfaces
        _zebraDiscoveredPrinters.addAll(printers);
        
        // Convert to compatible format for _discoveredPrinters
        final zebraAddresses = _zebraDiscoveredPrinters
            .map((printer) => '${printer.friendlyName ?? printer.address}:${printer.address}:${printer.interfaceType.toUpperCase()}')
            .toList();
        _discoveredPrinters = zebraAddresses;
        
        _selectedPrinter = _discoveredPrinters.isNotEmpty ? _discoveredPrinters.first : null;
        _selectedZebraPrinter = _zebraDiscoveredPrinters.isNotEmpty ? _zebraDiscoveredPrinters.first : null;
        _isDiscovering = false;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Auto discovery found ${printers.length} printers')),
      );
    } catch (e) {
      print('[Flutter] Auto discovery failed: $e');
      setState(() {
        _isDiscovering = false;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Auto discovery failed: $e')),
      );
    }
  }

  Future<void> _discoverZebraBluetoothPrinters() async {
    setState(() {
      _isDiscovering = true;
    });

    try {
      print('[Flutter] Starting Bluetooth LE discovery...');
      final printers = await ZebraPrinter.discoverBluetoothPrinters();
      print('[Flutter] Bluetooth discovery completed. Found ${printers.length} printers');
      
      setState(() {
        // Merge with existing discoveries - allow duplicates for different interfaces
        _zebraDiscoveredPrinters.addAll(printers);
        
        // Convert to compatible format for _discoveredPrinters
        final zebraAddresses = _zebraDiscoveredPrinters
            .map((printer) => '${printer.friendlyName ?? printer.address}:${printer.address}:${printer.interfaceType.toUpperCase()}')
            .toList();
        _discoveredPrinters = zebraAddresses;
        
        _selectedPrinter = _discoveredPrinters.isNotEmpty ? _discoveredPrinters.first : null;
        _selectedZebraPrinter = _zebraDiscoveredPrinters.isNotEmpty ? _zebraDiscoveredPrinters.first : null;
        _isDiscovering = false;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bluetooth found ${printers.length} printers')),
      );
    } catch (e) {
      print('[Flutter] Bluetooth discovery failed: $e');
      setState(() {
        _isDiscovering = false;
      });

      if (!mounted) return;
      
      String errorMessage = 'Bluetooth discovery failed: $e';
      
      // Check if it's a permissions error and provide helpful guidance
      if (e.toString().contains('MISSING_PERMISSIONS') || e.toString().contains('permission')) {
        errorMessage = 'Bluetooth permissions required!\n\n'
            'Please go to Settings > Apps > Flutter Zebra > Permissions '
            'and enable:\n• Nearby devices (Bluetooth)\n• Location\n\n'
            'Then restart the app and try again.';
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'OK',
            onPressed: () {},
          ),
        ),
      );
    }
  }

  Future<void> _discoverZebraUsbPrinters() async {
    // Check if running on iOS
    if (Platform.isIOS) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('iOS doesn\'t support USB discovery or printing'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    // Android implementation - discover USB printers
    setState(() {
      _isDiscovering = true;
    });

    try {
      print('[Flutter] Starting USB printer discovery...');
      final printers = await ZebraPrinter.discoverUsbPrinters();
      print('[Flutter] USB discovery completed. Found ${printers.length} printers');
      
      setState(() {
        // Add new USB printers - allow duplicates for different interfaces
        _zebraDiscoveredPrinters.addAll(printers);
        
        // Convert to compatible format for _discoveredPrinters
        final zebraAddresses = _zebraDiscoveredPrinters
            .map((printer) => '${printer.friendlyName ?? printer.address}:${printer.address}:${printer.interfaceType.toUpperCase()}')
            .toList();
        _discoveredPrinters = zebraAddresses;
        
        // Preserve selected printer reference if it still exists
        if (_selectedZebraPrinter != null) {
          final matchingPrinter = _zebraDiscoveredPrinters
              .where((p) => p.address == _selectedZebraPrinter!.address && p.interfaceType == _selectedZebraPrinter!.interfaceType)
              .firstOrNull;
          _selectedZebraPrinter = matchingPrinter;
          if (_selectedZebraPrinter != null) {
            final matchingAddress = zebraAddresses
                .where((addr) => addr.contains(_selectedZebraPrinter!.address))
                .firstOrNull;
            _selectedPrinter = matchingAddress;
          }
        }
        
        _isDiscovering = false;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('USB discovery found ${printers.length} printers')),
      );
    } catch (e) {
      print('[Flutter] USB discovery failed: $e');
      setState(() {
        _isDiscovering = false;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('USB discovery failed: $e')),
      );
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
            
            final printers = await star.StarPrinter.discoverPrinters();
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
          await _discoverZebraAll();
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
            
            // Try to detect paper width and set as default
            try {
              String detectedWidth = await EpsonPrinter.detectPaperWidth();
              if (_availableEpsonPaperWidths.contains(detectedWidth)) {
                setState(() => _epsonLabelPaperWidth = detectedWidth);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Connected! Detected paper width: $detectedWidth')),
                );
              } else {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Connected to: ${_selectedPrinter!.split(':').last} (Detected: $detectedWidth)')),
                );
              }
            } catch (e) {
              // Paper width detection failed, but connection succeeded
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Connected to: ${_selectedPrinter!.split(':').last}')),
              );
            }
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
              await star.StarPrinter.disconnect();
              setState(() {
                _isConnected = false;
              });
              // Small delay to ensure clean disconnect
              await Future.delayed(const Duration(milliseconds: 500));
            }
            
            final printerString = _selectedPrinter!; // Use selected printer instead of first
            
            // Parse the printer string to determine interface type
            star.StarInterfaceType interfaceType;
            String identifier;
            
            if (printerString.startsWith('LAN:')) {
              interfaceType = star.StarInterfaceType.lan;
              // Extract just the identifier part (MAC address or IP), ignore model info
              final parts = printerString.substring(4).split(':');
              identifier = parts[0]; // Take first part before any model info
            } else if (printerString.startsWith('BT:')) {
              interfaceType = star.StarInterfaceType.bluetooth;
              final parts = printerString.substring(3).split(':');
              identifier = parts[0]; // Take first part before any model info
            } else if (printerString.startsWith('BLE:')) {
              interfaceType = star.StarInterfaceType.bluetoothLE;
              final parts = printerString.substring(4).split(':');
              identifier = parts[0]; // Take first part before any model info
            } else if (printerString.startsWith('USB:')) {
              interfaceType = star.StarInterfaceType.usb;
              final parts = printerString.substring(4).split(':');
              identifier = parts[0]; // Take first part before any model info
            } else {
              interfaceType = star.StarInterfaceType.lan;
              identifier = printerString.split(':')[0]; // Take first part
            }
            
            print('DEBUG: Connecting to $interfaceType printer: $identifier (Selected: $printerString)');
            
            final settings = star.StarConnectionSettings(
              interfaceType: interfaceType,
              identifier: identifier,
            );
            await star.StarPrinter.connect(settings);
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
          // Zebra connection implementation
          try {
            if (_selectedZebraPrinter == null) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please select a Zebra printer first.')),
              );
              return;
            }

            // Force disconnect if already connected
            if (_isConnected) {
              print('[Flutter] Force disconnecting from current printer...');
              try {
                await ZebraPrinter.disconnect();
                await Future.delayed(const Duration(milliseconds: 500));
                setState(() {
                  _isConnected = false;
                  _printerStatus = 'Disconnected';
                  _connectedZebraPrinter = null;
                });
              } catch (e) {
                print('[Flutter] Error disconnecting: $e');
                setState(() {
                  _isConnected = false;
                  _printerStatus = 'Disconnected';
                  _connectedZebraPrinter = null;
                });
              }
            }
            
            // Determine interface type for connection
            ZebraInterfaceType interfaceType;
            switch (_selectedZebraPrinter!.interfaceType.toLowerCase()) {
              case 'bluetooth':
                interfaceType = ZebraInterfaceType.bluetooth;
                break;
              case 'usb':
                interfaceType = ZebraInterfaceType.usb;
                break;
              default:
                interfaceType = ZebraInterfaceType.tcp;
                break;
            }
            
            final settings = ZebraConnectionSettings(
              interfaceType: interfaceType,
              identifier: _selectedZebraPrinter!.address,
              timeout: 15000,
            );

            print('[Flutter] Connecting to Zebra printer: ${_selectedZebraPrinter!.address}');
            await ZebraPrinter.connect(settings);
            print('[Flutter] Connection successful');
            
            // Add small delay to ensure connection is fully established
            await Future.delayed(const Duration(milliseconds: 500));
            
            // Auto-fetch printer dimensions after successful connection
            try {
              print('[Flutter] Fetching printer dimensions after connection...');
              final dimensions = await ZebraPrinter.getPrinterDimensions();
              print('[Flutter] Raw dimensions received: $dimensions');
              
              // Validate that we got reasonable dimensions for a ZD421/ZD410
              final printWidth = dimensions['printWidthInDots'] ?? 0;
              final labelLength = dimensions['labelLengthInDots'] ?? 0;
              final dpi = dimensions['dpi'] ?? 203;
              
              if (printWidth < 100 || labelLength < 100) {
                print('[Flutter] Warning: Dimensions seem invalid, retrying...');
                await Future.delayed(const Duration(milliseconds: 300));
                final retryDimensions = await ZebraPrinter.getPrinterDimensions();
                print('[Flutter] Retry dimensions: $retryDimensions');
                
                _connectedZebraPrinter = ConnectedPrinter(
                  discoveredPrinter: _selectedZebraPrinter!,
                  printWidthInDots: retryDimensions['printWidthInDots'],
                  labelLengthInDots: retryDimensions['labelLengthInDots'], 
                  dpi: retryDimensions['dpi'],
                  maxPrintWidthInDots: retryDimensions['maxPrintWidthInDots'],
                  mediaWidthInDots: retryDimensions['mediaWidthInDots'],
                  connectedAt: DateTime.now(),
                );
              } else {
                _connectedZebraPrinter = ConnectedPrinter(
                  discoveredPrinter: _selectedZebraPrinter!,
                  printWidthInDots: dimensions['printWidthInDots'],
                  labelLengthInDots: dimensions['labelLengthInDots'], 
                  dpi: dimensions['dpi'],
                  maxPrintWidthInDots: dimensions['maxPrintWidthInDots'],
                  mediaWidthInDots: dimensions['mediaWidthInDots'],
                  connectedAt: DateTime.now(),
                );
              }
              
              print('[Flutter] Connected printer dimensions: ${_connectedZebraPrinter.toString()}');
            } catch (e) {
              print('[Flutter] Warning: Could not fetch Zebra printer dimensions: $e');
              _connectedZebraPrinter = ConnectedPrinter(
                discoveredPrinter: _selectedZebraPrinter!,
                connectedAt: DateTime.now(),
              );
            }
            
            setState(() {
              _isConnected = true;
              _printerStatus = 'Connected';
            });

            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Connected to Zebra: ${_selectedZebraPrinter!.friendlyName ?? _selectedZebraPrinter!.address} [${_selectedZebraPrinter!.interfaceType.toUpperCase()}]')),
            );
          } catch (e) {
            print('[Flutter] Zebra connection failed: $e');
            setState(() {
              _isConnected = false;
              _printerStatus = 'Connection Failed';
              _connectedZebraPrinter = null;
            });

            if (!mounted) return;
            String errorMessage = 'Zebra connection failed: $e';
            
            // Provide specific guidance for Zebra connection issues
            if (e.toString().contains('socket might closed') || 
                e.toString().contains('read failed') ||
                e.toString().contains('CONNECTION_FAILED')) {
              errorMessage = 'Zebra connection failed!\n\n'
                  'Try:\n• Check printer IP/MAC address\n'
                  '• Ensure printer is powered on\n'
                  '• Check network connectivity\n'
                  '• For Bluetooth: ensure printer is in pairing mode\n\n'
                  'Original error: $e';
            }
            
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(errorMessage),
                duration: const Duration(seconds: 6),
              ),
            );
          }
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
          await _printZebraReceipt();
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
    if (!_isConnected) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please connect to a printer first')),
      );
      return;
    }

    try {
      // Use improved POS style receipt building with standardized commands
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Print failed: $e')),
      );
    }
  }

  Future<void> _printStarReceipt() async {
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

      final printJob = star.PrintJob(
        content: '',
        settings: layoutSettings,
      );
      
      print('DEBUG: Sending print job to printer...');
      await star.StarPrinter.printReceipt(printJob);
      
      print('DEBUG: Print job completed successfully');
      
      // Optionally open cash drawer after successful print
      if (_openDrawerAfterPrint && _isConnected) {
        try {
          print('DEBUG: Auto-opening cash drawer after print...');
          await star.StarPrinter.openCashDrawer();
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
    } catch (e) {
      print('DEBUG: Print failed with error: $e');
      print('DEBUG: Error type: ${e.runtimeType}');
      print('DEBUG: Error details: ${e.toString()}');
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Print failed: $e')),
      );
    }
  }

  Future<void> _printLabel() async {
    if (_selectedBrand == null) {
      _showBrandSelectionSnackBar();
      return;
    }

    switch (_selectedBrand!) {
      case PrinterBrand.epson:
        await _printEpsonLabel();
        break;
      case PrinterBrand.star:
        await _printStarLabel();
        break;
      case PrinterBrand.zebra:
        // TODO: Implement Zebra label printing when available
        await _printZebraLabel();
        break;
    }
  }

  Future<void> _printStarLabel() async {
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
      
      final labelContent = '';

      final printJob = star.PrintJob(
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
          await star.StarPrinter.printReceipt(printJob);
          
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
                await star.StarPrinter.printReceipt(printJob);
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$_labelQuantity Star label(s) printed successfully')),
      );
    } catch (e) {
      print('DEBUG: Label print failed with error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to print Star label: $e')),
      );
    }
  }

  Future<void> _printEpsonLabel() async {
    if (!_isConnected) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please connect to a printer first')),
      );
      return;
    }

    try {
      // Build label commands based on current label fields and paper width
      final commands = _buildEpsonLabelCommands();
      final printJob = EpsonPrintJob(commands: commands);
      
      // Print multiple labels based on quantity setting
      for (int i = 0; i < _epsonLabelQuantity; i++) {
        await EpsonPrinter.printReceipt(printJob);
        
        // Small delay between prints to avoid overwhelming the printer
        if (i < _epsonLabelQuantity - 1) {
          await Future.delayed(const Duration(milliseconds: 200));
        }
      }

      if (!mounted) return;
      final message = _epsonLabelQuantity == 1 
          ? 'Epson label printed successfully!' 
          : '$_epsonLabelQuantity Epson labels printed successfully!';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Epson label print failed: $e')),
      );
    }
  }

  List<EpsonPrintCommand> _buildEpsonLabelCommands() {
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
      parameters: {'data': _epsonLabelProductNameController.text.trim() + '\n'}
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
      parameters: {'data': _epsonLabelPriceController.text.trim() + '\n'}
    ));
    
    // Size/Color (centered under price)
    commands.add(EpsonPrintCommand(
      type: EpsonCommandType.text,
      parameters: {'data': _epsonLabelSizeColourController.text.trim() + '\n'}
    ));
    
    // CODE128 barcode with HRI below (center alignment already set)
    commands.add(EpsonPrintCommand(
      type: EpsonCommandType.barcode,
      parameters: {
        'data': _epsonLabelScancodeController.text.trim(),
        'type': 'CODE128_AUTO', // Using CODE128 auto for simplicity
        'hri': 'below', // HRI (Human Readable Interpretation) below barcode
        'width': 2, // Width of single module (2 dots)
        'height': 35, // Height in dots (good for labels)
        'font': 'A', // Font A for HRI
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

  Future<void> _printZebraReceipt() async {
    if (!_isConnected) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please connect to a printer first')),
      );
      return;
    }

    try {
      if (_connectedZebraPrinter == null) {
        throw Exception('No connected Zebra printer information available');
      }
      
      // Use actual detected dimensions, with fallbacks
      final width = _connectedZebraPrinter!.printWidthInDots ?? 386; // fallback to ZD410 width
      final height = _connectedZebraPrinter!.labelLengthInDots ?? 212; // fallback to common label height
      final dpi = _connectedZebraPrinter!.dpi ?? 203; // fallback to common Zebra DPI
      
      print('[Flutter] Using Zebra printer dimensions: ${width}x${height} @ ${dpi}dpi');
      
      // Build receipt data from form inputs
      ReceiptData receiptData = await _buildZebraReceiptDataFromForm();
      
      // Generate ZPL for receipt
      final receiptZpl = await _generateZebraReceiptZPL(width, height, dpi, receiptData);
      
      await ZebraPrinter.sendCommands(receiptZpl, language: ZebraPrintLanguage.zpl);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Zebra receipt sent successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Zebra receipt print failed: $e')),
      );
    }
  }

  Future<void> _printZebraLabel() async {
    if (!_isConnected) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please connect to a printer first')),
      );
      return;
    }

    try {
      if (_connectedZebraPrinter == null) {
        throw Exception('No connected Zebra printer information available');
      }
      
      // Use actual detected dimensions, with fallbacks
      final width = _connectedZebraPrinter!.printWidthInDots ?? 386; // fallback to ZD410 width
      final height = _connectedZebraPrinter!.labelLengthInDots ?? 212; // fallback to common label height
      final dpi = _connectedZebraPrinter!.dpi ?? 203; // fallback to common Zebra DPI
      
      print('[Flutter] Using Zebra printer dimensions: ${width}x${height} @ ${dpi}dpi');
      
      // Create label data from form inputs
      final labelData = LabelData(
        productName: _zebraLabelProductNameController.text.trim().isNotEmpty 
            ? _zebraLabelProductNameController.text.trim() 
            : 'T-Shirt',
        colorSize: _zebraLabelColorSizeController.text.trim().isNotEmpty 
            ? _zebraLabelColorSizeController.text.trim() 
            : 'Small Turquoise',
        scancode: _zebraLabelScancodeController.text.trim().isNotEmpty 
            ? _zebraLabelScancodeController.text.trim() 
            : '123456789',
        price: _zebraLabelPriceController.text.trim().isNotEmpty 
            ? _zebraLabelPriceController.text.trim() 
            : '\$5.00',
      );
      
      // Generate ZPL with actual printer dimensions, DPI, and label data
      String labelZpl = await _generateZebraLabelZPL(width, height, dpi, labelData);
      
      // Ensure we have a valid quantity (minimum 1)
      final printQuantity = _zebraLabelQuantity > 0 ? _zebraLabelQuantity : 1;
      if (printQuantity != _zebraLabelQuantity) {
        setState(() {
          _zebraLabelQuantity = printQuantity;
          _zebraLabelQuantityController.text = printQuantity.toString();
        });
      }
      
      // Print labels based on quantity
      for (int i = 0; i < printQuantity; i++) {
        await ZebraPrinter.sendCommands(labelZpl, language: ZebraPrintLanguage.zpl);
        
        // Small delay between labels to prevent overwhelming the printer
        if (i < printQuantity - 1) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$printQuantity Zebra label(s) sent successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Zebra label print failed: $e')),
      );
    }
  }

  Future<LabelData> _buildZebraLabelDataFromForm() async {
    return LabelData(
      productName: _zebraLabelProductNameController.text,
      colorSize: _zebraLabelColorSizeController.text,
      scancode: _zebraLabelScancodeController.text,
      price: _zebraLabelPriceController.text,
    );
  }

  Future<ReceiptData> _buildZebraReceiptDataFromForm() async {
    List<ReceiptLineItem> items = [];
    for (int i = 0; i < _zebraLineItemControllers.length; i++) {
      final quantity = int.tryParse(_zebraLineItemControllers[i]['quantity']!.text) ?? 1;
      final itemName = _zebraLineItemControllers[i]['item']!.text;
      final unitPrice = double.tryParse(_zebraLineItemControllers[i]['price']!.text) ?? 0.0;
      
      if (itemName.isNotEmpty) {
        items.add(ReceiptLineItem(
          quantity: quantity,
          itemName: itemName,
          unitPrice: unitPrice,
        ));
      }
    }
    
    return ReceiptData(
      storeName: _zebraStoreNameController.text,
      storeAddress: _zebraStoreAddressController.text,
      storePhone: _zebraStorePhoneController.text.isNotEmpty ? _zebraStorePhoneController.text : null,
      cashierName: _zebraCashierNameController.text.isNotEmpty ? _zebraCashierNameController.text : null,
      laneNumber: _zebraLaneNumberController.text.isNotEmpty ? _zebraLaneNumberController.text : null,
      receiptNumber: _zebraReceiptNumberController.text.isNotEmpty ? _zebraReceiptNumberController.text : null,
      transactionDate: DateTime.now(),
      items: items,
      thankYouMessage: _zebraThankYouMessageController.text.isNotEmpty ? _zebraThankYouMessageController.text : null,
    );
  }

  // Generate label ZPL with given dimensions and label data
  Future<String> _generateZebraLabelZPL(int width, int height, int dpi, LabelData labelData) async {
    // Extract label content from the data object
    String productName = labelData.productName;
    String colorSize = labelData.colorSize;
    String scancode = labelData.scancode;
    String price = labelData.price;
    
    //paper details - use actual detected DPI instead of hardcoded value
    int paperWidthDots = width; // use provided width in dots
    
    // Helper function to get character width in dots based on font size and DPI
    int getCharWidthInDots(int fontSize, int dpi) {
      // Based on empirical testing and Zebra font matrices
      // Using a more conservative estimate that matches actual rendering
      // Base character width scales roughly with font size
      
      if (fontSize <= 25) {
        return 10; // For smaller fonts like size 25
      } else if (fontSize <= 38) {
        return 20; // For medium fonts like size 38
      } else {
        return (fontSize * 0.5).round(); // For larger fonts, scale proportionally
      }
    }
    
    // Calculate barcode position
    int scancodeLength = scancode.length;
    // Estimate barcode width for Code 128
    // Code 128: Each character takes ~11 modules + start/stop characters
    int totalBarcodeCharacters = scancodeLength + 3; // +3 for start, check, and stop characters
    int moduleWidth = 2; // from ^BY2
    int estimatedBarcodeWidth = totalBarcodeCharacters * 11 * moduleWidth;
    
    // Calculate text widths using font size and DPI
    int productNameCharWidth = getCharWidthInDots(38, dpi);
    int colorSizeCharWidth = getCharWidthInDots(25, dpi);
    int priceCharWidth = getCharWidthInDots(38, dpi);
    
    int estimatedProductNameWidth = productName.length * productNameCharWidth;
    int estimatedColorSizeWidth = colorSize.length * colorSizeCharWidth;
    int estimatedPriceWidth = price.length * priceCharWidth;

    print('[Flutter] Font calculations - DPI: $dpi, Font 38: ${productNameCharWidth}dots/char, Font 25: ${colorSizeCharWidth}dots/char');
    print('[Flutter] Text widths - ProductName: ${estimatedProductNameWidth}dots, ColorSize: ${estimatedColorSizeWidth}dots, Price: ${estimatedPriceWidth}dots');

    // Calculate centered X position for barcode
    int barcodeX = (paperWidthDots - estimatedBarcodeWidth) ~/ 2;
    int productNameX = (paperWidthDots - estimatedProductNameWidth) ~/ 2;
    int colorSizeX = (paperWidthDots - estimatedColorSizeWidth) ~/ 2;
    int priceX = (paperWidthDots - estimatedPriceWidth) ~/ 2;

    // Ensure barcode doesn't go off the left edge
    barcodeX = barcodeX.clamp(0, paperWidthDots - estimatedBarcodeWidth);
    
    print('[Flutter] Label positions - ProductName: ($productNameX,14), Price: ($priceX,52), ColorSize: ($colorSizeX,90), Barcode: ($barcodeX,124)');

    String labelZpl = '''
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

  Future<String> _generateZebraReceiptZPL(int width, int height, int dpi, ReceiptData receiptData) async {
    // Format date and time (handle nullable DateTime)
    final now = receiptData.transactionDate ?? DateTime.now();
    final formattedDate = "${_getWeekday(now.weekday)} ${_getMonth(now.month)} ${now.day} ${now.hour}:${now.minute.toString().padLeft(2, '0')} ${now.hour >= 12 ? 'PM' : 'AM'}";
    
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
        return (fontSize * 0.5).round(); // For even larger fonts, scale proportionally
      }
    }
    
    // Calculate centered positions for store name and address
    int storeNameCharWidth = getCharWidthInDots(47, dpi);
    int storeAddressCharWidth = getCharWidthInDots(27, dpi);
    
    int estimatedStoreNameWidth = receiptData.storeName.length * storeNameCharWidth;
    int estimatedStoreAddressWidth = receiptData.storeAddress.length * storeAddressCharWidth;
    
    int storeNameX = (width - estimatedStoreNameWidth) ~/ 2;
    int storeAddressX = (width - estimatedStoreAddressWidth) ~/ 2;
    
    // Ensure positions don't go negative
    storeNameX = storeNameX.clamp(0, width - estimatedStoreNameWidth);
    storeAddressX = storeAddressX.clamp(0, width - estimatedStoreAddressWidth);
    
    print('[Flutter] Receipt positioning - Store Name: ($storeNameX,64), Store Address: ($storeAddressX,388)');
    
    // Build ZPL string dynamically using actual form data with calculated positions
    String receiptZpl = '''
^XA
^CF0,47
^FO$storeNameX,64
^FD${receiptData.storeName}^FS
^CF0,27
^FO$storeAddressX,388
^FD${receiptData.storeAddress}^FS''';

    // Add phone if provided (centered)
    if (receiptData.storePhone != null) {
      int storePhoneCharWidth = getCharWidthInDots(25, dpi);
      int estimatedStorePhoneWidth = receiptData.storePhone!.length * storePhoneCharWidth;
      int storePhoneX = (width - estimatedStorePhoneWidth) ~/ 2;
      storePhoneX = storePhoneX.clamp(0, width - estimatedStorePhoneWidth);
      
      receiptZpl += '''
^CF0,25
^FO$storePhoneX,420
^FD${receiptData.storePhone}^FS''';
    }

    receiptZpl += '''
^CF0,30
^FO20,478
^FD$formattedDate^FS''';

    // Add cashier if provided
    if (receiptData.cashierName != null) {
      // Position cashier name to avoid cutoff - use right-aligned positioning
      String cashierText = "Cashier: ${receiptData.cashierName}";
      int cashierCharWidth = getCharWidthInDots(30, dpi);
      int estimatedCashierWidth = cashierText.length * cashierCharWidth;
      int cashierX = (width - estimatedCashierWidth - 20); // 20 dot right margin
      cashierX = cashierX.clamp(20, width - estimatedCashierWidth); // Ensure minimum left margin
      
      receiptZpl += '''
^CF0,30
^FO$cashierX,478
^FD$cashierText^FS''';
    }

    // Add lane if provided
    if (receiptData.laneNumber != null) {
      receiptZpl += '''
^CF0,30
^FO470,526
^FDLane: ${receiptData.laneNumber}^FS''';
    }

    // Add receipt number if provided
    if (receiptData.receiptNumber != null) {
      receiptZpl += '''
^CF0,30
^FO20,530
^FDReceipt No: ${receiptData.receiptNumber}^FS''';
    }

    // Add logo (keeping the existing logo)
    receiptZpl += '''
^FO200,132
^GFA,7200,7200,30,!::::::::::::::::::::::::::::::::::::::::::::::gVF03!gTFCJ0!gTFL0!XFCH0RF8L03!:WFEJ07OFEM01!WFK01OFCN0!VFCL03NFO01!VF8L01MFEP0!UFCN0MFCP07!:UF8N07LF8I01HFJ07!UFO03LFI01IFCI03!UFI03HFJ0LFI07IFK0!TFEI0IFJ07JFCI0IFEK0!TFCH03HFEJ07JFCH03IFEK07!:TFCH0IFEJ03JF8H07IFEH08H07!TFH01IFE02H03JF8H0JFE03CH07!TFH03JF03H01JFI0KF03EH03!TFH03JFCFC01JFH01MFEH03!SFEH07LFC01JFH01MFEH03!:SFEH07LFCH0JFH01NFH01!SFEH07LFEH0IFEH03NFH01!SFEH0MFEH0IFEH03NFH01!:::SFEH0MFEH0HF9EH03NFH01!SFEH0MFEH0FC0EH03NFH01!SFEH0MFEH0FH0EH03NFH01!SFEH07LFEH0EH0EH03NFH01!SFEH07LFC01CH03H01NFH01!:SFEH07LFCK03H01MFEH03!TFH03LFL01I0MFEH03!TFH03LFL01I0MFCH03!TFH01KFEL018H07LFCH07!TFCH0KFCM08H03LF8H07!:TFCH03JF8M0CH03LFI07!TFEI0IFCN04I0LF8H0!UFH03JFN07H03LFE03!UF81KFEM0380NFC3!UF87LFM0381OF7!:gIFN0C3!gIFN07!gHFEN03!gHFCN01!gHFCO0!:gHFCO03!gHF8O01!gHF8P07!gHF8P03!gHF8Q07!:gHF8R0!gHFES0!gHFES03!gIFT07!gIFCS0!:gIFER03!gJFR07!gJFQ01!gJF8P03!gJFCO01!:gKF8N07!gKFCM03!gKFEM0!gLFCK03!gMFJ07!:gNFH0!!:::::::::::::gFH0!XFCK07!:WFCM01!VFEP0!VFR0!UF8R01!TFET01!:TFCU07!SFEW0!SFCW01!SFY03!RFCg0!:RF8g03!RFgH07!QFEgH01!QFCgI03!QFgJ01!:PFEgK07XFC!PFCgL0XF0!PFCgL07VF80!MFgP01UFCH0!LFgR0UFCH0!:KFC03FCgN01UFC0!KF03HFCgO0UFC0!JFE0IF8gO07TFC0!JF81IFgR0SFC0!JF83IFgS03QFC0!:JF0IFEgT01PFC0!IFC1IFCgU03OFC0!IF81IFCgV07NFC0!IF83IFgX0NFC0!IF03IFgX03MFC0!:IF07HFEgX01MFC0!IF07HFEgY03LFC0!HFE07HFEh0LFC0!HFE07HFEh07KFC0!HFE07HFEhG07JFC0!:HFE07HFEhH03IFC0!HFC0IFEhH01IFC0!HFC0JFhI0IFC0!HFC07IFhI07HFC0!HFC07IFChH07HFC0!:HFC07IFEhH07HFC0!HFC07JFU078gK03HFC0!HFC07JF8T07gL03HFC0!HFE07KFQ07E04gM0HFC0!HFE07KFCN01HFE04gM07FC0!:HFE03LFEM0IFEgO03FC0!HFE03NFE07FE0IFEgO01FC0!IF03NFE0HFE0IFEgO01FC0!IF01NFE0HFE0IFEgP0FC0!IF80NFC1HFE0IFEgP03C0!:IF80NFC1HFE0IFEgP01C0!IFC03MF83HFE0IFEgQ0C0!IFC01MF8IFE0IFEgQ0C0!JFH0MF0IFE07HFEgQ040!JF807KFC1IFE07HFEgQ040!:JFC03KF83IFE07HFCgS0!JFEH0KF07JF03HF8gS0!KFH03IFC3KFH0HFgT03!JFCI03FC07KF8gX0!JF8L01LFCI0CgT03HF:JF83CI01NF8078gO03E3!JF1HF8I0QF8gK07!JF3HFEJ03OF8gH07!JF3IFCK0NF8Y07!IFC7JFM0KF8W03!:JF7JFCgL03!PFgJ07!PFCgK0!QFgM0!QFEgN07RFC!:SFK07HF8gG0OFC0!gNFCgJ03!gRFg07!gTF8V0!gVFCQ03!:!:::::::^FS
^FO44,574^GB554,1,2,B,0^FS''';

    // Add line items dynamically
    int yPosition = 612;
    for (var item in receiptData.items) {
      receiptZpl += '''
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
    int actualReceiptHeight = height > minRequiredHeight ? height : minRequiredHeight;
    
    print('[Flutter] Receipt layout - Last item Y: $yPosition, Total Y: $totalY, Thank you Y: $thankYouY');
    print('[Flutter] Receipt height - Detected: $height, Required: $minRequiredHeight, Using: $actualReceiptHeight');

    // Add bottom line at dynamic position
    receiptZpl += '''
^FO44,$bottomLineY^GB554,1,2,B,0^FS''';

    // Add total using the correct getter (centered) at dynamic position
    final total = receiptData.calculatedTotal;
    int totalCharWidth = getCharWidthInDots(35, dpi);
    String totalText = "Total: \$${total.toStringAsFixed(2)}";
    int estimatedTotalWidth = totalText.length * totalCharWidth;
    int totalX = (width - estimatedTotalWidth) ~/ 2;
    totalX = totalX.clamp(20, width - estimatedTotalWidth - 20); // Add margins
    
    receiptZpl += '''
^CF0,35
^FO$totalX,$totalY
^FD$totalText^FS''';

    // Add thank you message (centered) at dynamic position
    String thankYouMsg = receiptData.thankYouMessage ?? 'Thank you for shopping with us!';
    int thankYouCharWidth = getCharWidthInDots(30, dpi);
    int estimatedThankYouWidth = thankYouMsg.length * thankYouCharWidth;
    int thankYouX = (width - estimatedThankYouWidth) ~/ 2;
    thankYouX = thankYouX.clamp(0, width - estimatedThankYouWidth);
    
    receiptZpl += '''
^CF0,30
^FO$thankYouX,$thankYouY
^FD$thankYouMsg^FS''';

    // Set the label length to accommodate the full receipt if needed
    if (actualReceiptHeight > height) {
      receiptZpl = '''
^XA
^LL$actualReceiptHeight
''' + receiptZpl.substring(4); // Replace ^XA with ^XA^LL command
    }
    
    receiptZpl += '''
^XZ''';

    return receiptZpl;
  }

  String _getWeekday(int weekday) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return weekdays[weekday - 1];
  }

  String _getMonth(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                   'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }

  Widget _buildZebraControls() {
    return Column(
      children: [
        // Label Printing Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.label, color: Colors.blue),
                    const SizedBox(width: 8),
                    Text('Label Printing', style: Theme.of(context).textTheme.headlineSmall),
                  ],
                ),
                const SizedBox(height: 16),
                
                // Label form fields
                TextField(
                  controller: _zebraLabelProductNameController,
                  decoration: const InputDecoration(
                    labelText: 'Product Name',
                    hintText: 'Enter product name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _zebraLabelColorSizeController,
                        decoration: const InputDecoration(
                          labelText: 'Color/Size',
                          hintText: 'Red/Large',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _zebraLabelPriceController,
                        decoration: const InputDecoration(
                          labelText: 'Price',
                          hintText: '\$29.99',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _zebraLabelScancodeController,
                        decoration: const InputDecoration(
                          labelText: 'Barcode/SKU',
                          hintText: '123456789',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 100,
                      child: TextField(
                        controller: _zebraLabelQuantityController,
                        decoration: const InputDecoration(
                          labelText: 'Quantity',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (value) {
                          // Allow empty field temporarily, only validate on print or focus loss
                          final parsed = int.tryParse(value);
                          if (parsed != null && parsed > 0) {
                            setState(() {
                              _zebraLabelQuantity = parsed;
                            });
                          } else if (value.isEmpty) {
                            // Allow empty field temporarily
                            setState(() {
                              _zebraLabelQuantity = 0; // Use 0 to indicate empty, will default to 1 when printing
                            });
                          }
                        },
                        onSubmitted: (value) {
                          // When user finishes editing, ensure we have a valid value
                          final parsed = int.tryParse(value);
                          final finalValue = (parsed != null && parsed > 0) ? parsed : 1;
                          setState(() {
                            _zebraLabelQuantity = finalValue;
                            _zebraLabelQuantityController.text = finalValue.toString();
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                Center(
                  child: ElevatedButton.icon(
                    onPressed: _isConnected ? () => _printLabel() : null,
                    icon: const Icon(Icons.print),
                    label: const Text('Print Label'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 16),
        
        // Receipt Printing Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.receipt, color: Colors.green),
                    const SizedBox(width: 8),
                    Text('Receipt Printing', style: Theme.of(context).textTheme.headlineSmall),
                    const Spacer(),
                    IconButton(
                      icon: Icon(_zebraShowReceiptForm ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down),
                      onPressed: () {
                        setState(() {
                          _zebraShowReceiptForm = !_zebraShowReceiptForm;
                        });
                      },
                    ),
                  ],
                ),
                
                if (_zebraShowReceiptForm) ...[
                  const SizedBox(height: 16),
                  
                  // Store Information
                  Text('Store Information', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _zebraStoreNameController,
                          decoration: const InputDecoration(
                            labelText: 'Store Name',
                            hintText: 'My Store',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _zebraStoreAddressController,
                          decoration: const InputDecoration(
                            labelText: 'Store Address',
                            hintText: '123 Main St',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  
                  TextField(
                    controller: _zebraStorePhoneController,
                    decoration: const InputDecoration(
                      labelText: 'Store Phone (Optional)',
                      hintText: '(555) 123-4567',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Transaction Details
                  Text('Transaction Details', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _zebraCashierNameController,
                          decoration: const InputDecoration(
                            labelText: 'Cashier Name (Optional)',
                            hintText: 'John Doe',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _zebraLaneNumberController,
                          decoration: const InputDecoration(
                            labelText: 'Lane Number (Optional)',
                            hintText: '1',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  
                  TextField(
                    controller: _zebraReceiptNumberController,
                    decoration: const InputDecoration(
                      labelText: 'Receipt Number (Optional)',
                      hintText: 'R001',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Line Items
                  Text('Line Items', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  
                  ...List.generate(_zebraLineItemControllers.length, (index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 60,
                            child: TextField(
                              controller: _zebraLineItemControllers[index]['quantity'],
                              decoration: const InputDecoration(
                                labelText: 'Qty',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _zebraLineItemControllers[index]['item'],
                              decoration: const InputDecoration(
                                labelText: 'Item Name',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _zebraLineItemControllers[index]['price'],
                              decoration: const InputDecoration(
                                labelText: 'Price',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            ),
                          ),
                          if (_zebraLineItemControllers.length > 1) ...[
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.remove_circle, color: Colors.red),
                              onPressed: () => _removeZebraLineItem(index),
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
                  
                  // Add line item button
                  Center(
                    child: IconButton(
                      icon: const Icon(Icons.add_circle, color: Colors.green, size: 32),
                      onPressed: _addZebraLineItem,
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Thank you message
                  TextField(
                    controller: _zebraThankYouMessageController,
                    decoration: const InputDecoration(
                      labelText: 'Thank You Message (Optional)',
                      hintText: 'Thank you for shopping with us!',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Print receipt button
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: _isConnected ? () => _printReceipt() : null,
                      icon: const Icon(Icons.print),
                      label: const Text('Print Receipt'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Zebra MAC address direct BLE connection
  Future<void> _testDirectBleConnection() async {
    if (_zebraMacAddress.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter MAC address first')),
      );
      return;
    }

    setState(() {
      _isDiscovering = true;
    });

    try {
      print('[Flutter] Testing direct BLE connection to MAC: $_zebraMacAddress');
      final printers = await ZebraPrinter.testDirectBleConnection(macAddress: _zebraMacAddress);
      print('[Flutter] Direct BLE connection test completed. Found ${printers.length} printers');
      
      setState(() {
        _zebraDiscoveredPrinters.addAll(printers);
        
        final zebraAddresses = _zebraDiscoveredPrinters
            .map((printer) => '${printer.friendlyName ?? printer.address}:${printer.address}:${printer.interfaceType.toUpperCase()}')
            .toList();
        _discoveredPrinters = zebraAddresses;
        
        _selectedPrinter = _discoveredPrinters.isNotEmpty ? _discoveredPrinters.first : null;
        _selectedZebraPrinter = _zebraDiscoveredPrinters.isNotEmpty ? _zebraDiscoveredPrinters.first : null;
        _isDiscovering = false;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Direct BLE found ${printers.length} printers')),
      );
    } catch (e) {
      print('[Flutter] Direct BLE connection failed: $e');
      setState(() {
        _isDiscovering = false;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Direct BLE connection failed: $e')),
      );
    }
  }

  // Zebra dimensions UI methods
  Future<void> _getZebraDimensionsUI() async {
    if (!_isConnected || _selectedZebraPrinter == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please connect to a printer first')),
      );
      return;
    }

    try {
      print('[Flutter] Getting printer dimensions...');
      
      // Try both methods - the built-in method and direct SGD reading
      final dimensions = await ZebraPrinter.getPrinterDimensions();
      print('[Flutter] Built-in method dimensions: $dimensions');
      
      // Also try reading dimensions directly via SGD parameters
      Map<String, String?> sgdDimensions = {};
      try {
        sgdDimensions['print_width'] = await ZebraPrinter.getSgdParameter('ezpl.print_width');
        sgdDimensions['label_length_max'] = await ZebraPrinter.getSgdParameter('ezpl.label_length_max');
        sgdDimensions['media_width'] = await ZebraPrinter.getSgdParameter('media.width');
        sgdDimensions['media_length'] = await ZebraPrinter.getSgdParameter('media.length');
        print('[Flutter] SGD dimensions: $sgdDimensions');
      } catch (e) {
        print('[Flutter] Could not read SGD parameters: $e');
      }
      
      if (!mounted) return;
      
      final width = dimensions['printWidthInDots'] ?? 0;
      final height = dimensions['labelLengthInDots'] ?? 0;
      final dpi = dimensions['dpi'] ?? 203;
      final maxWidth = dimensions['maxPrintWidthInDots'] ?? 0;
      final mediaWidth = dimensions['mediaWidthInDots'] ?? 0;
      
      final widthInches = width / dpi;
      final heightInches = height / dpi;
      
      // Show both sets of dimensions in the dialog
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Printer Dimensions'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Built-in Method:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Print Width: $width dots (${widthInches.toStringAsFixed(2)}")'),
              Text('Label Length: $height dots (${heightInches.toStringAsFixed(2)}")'),
              Text('DPI: $dpi'),
              Text('Max Print Width: $maxWidth dots'),
              Text('Media Width: $mediaWidth dots'),
              const SizedBox(height: 16),
              const Text('SGD Parameters:', style: TextStyle(fontWeight: FontWeight.bold)),
              ...sgdDimensions.entries.map((entry) {
                return Text('${entry.key}: ${entry.value ?? "null"}', 
                  style: const TextStyle(fontFamily: 'monospace'));
              }).toList(),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Current dimensions: ${widthInches.toStringAsFixed(1)}" x ${heightInches.toStringAsFixed(1)}" (${width}x${height} dots)')),
      );
    } catch (e) {
      print('[Flutter] Failed to get printer dimensions: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to get dimensions: $e')),
      );
    }
  }

  Future<void> _setZebraDimensionsUI() async {
    if (!_isConnected || _selectedZebraPrinter == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please connect to a printer first')),
      );
      return;
    }

    final widthController = TextEditingController();
    final heightController = TextEditingController();

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set Printer Dimensions'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter dimensions in inches:'),
            const SizedBox(height: 16),
            TextField(
              controller: widthController,
              decoration: const InputDecoration(
                labelText: 'Width (inches)',
                hintText: 'e.g. 2.20',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: heightController,
              decoration: const InputDecoration(
                labelText: 'Height (inches)',
                hintText: 'e.g. 1.04',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final width = widthController.text.trim();
              final height = heightController.text.trim();
              if (width.isNotEmpty && height.isNotEmpty) {
                Navigator.of(context).pop({'width': width, 'height': height});
              }
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );

    if (result == null) return;

    try {
      final width = result['width']!;
      final height = result['height']!;
      
      print('[Flutter] Setting printer dimensions to ${width}x$height inches...');
      
      // Get current DPI and dimensions to convert inches to dots
      final dimensions = await ZebraPrinter.getPrinterDimensions();
      final dpi = 203; // Default to 203 DPI if not available
      final currentWidthDots = dimensions['printWidthInDots'] ?? 448;
      
      // Convert target inches to dots
      final targetWidthInDots = (double.parse(width) * dpi).round();
      
      print('[Flutter] Current width: $currentWidthDots dots, Target width: $targetWidthInDots dots');
      
      // Smart width setting: step up gradually if increasing width significantly
      if (targetWidthInDots > currentWidthDots) {
        final widthDifference = targetWidthInDots - currentWidthDots;
        if (widthDifference > 100) { // If jumping more than ~0.5 inches
          print('[Flutter] Large width increase detected, stepping up gradually...');
          
          // Step up in increments of ~100 dots (~0.5 inches)
          int stepWidth = currentWidthDots;
          while (stepWidth < targetWidthInDots) {
            stepWidth = (stepWidth + 100).clamp(currentWidthDots, targetWidthInDots);
            
            print('[Flutter] Setting intermediate width: $stepWidth dots');
            await ZebraPrinter.setSgdParameter('ezpl.print_width', stepWidth.toString());
            
            // Small delay between steps
            await Future.delayed(const Duration(milliseconds: 200));
          }
        }
      }
      
      // Set final width
      await ZebraPrinter.setSgdParameter('ezpl.print_width', targetWidthInDots.toString());
      print('[Flutter] Set ezpl.print_width to $targetWidthInDots dots');
      
      // Set the label length using ZPL ^LL command for immediate effect (in dots)
      final heightInDots = (double.parse(height) * dpi).round();
      await ZebraPrinter.setLabelLength(heightInDots);
      print('[Flutter] Set label length to $heightInDots dots (${height}") using ZPL ^LL command');
      
      // Set label length max using SGD command (in inches)
      await ZebraPrinter.setSgdParameter('ezpl.label_length_max', height);
      print('[Flutter] Set ezpl.label_length_max to $height inches');
      
      // Skip immediate verification as it may not reflect changes immediately
      // The native logs show commands are sent successfully
      print('[Flutter] Dimension setting commands sent successfully');
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Set dimensions: ${width}" x ${height}" ($targetWidthInDots x $heightInDots dots)')),
      );
      
      // Update the connected printer object with new dimensions
      if (_connectedZebraPrinter != null) {
        _connectedZebraPrinter = ConnectedPrinter(
          discoveredPrinter: _connectedZebraPrinter!.discoveredPrinter,
          printWidthInDots: targetWidthInDots,
          labelLengthInDots: heightInDots,
          dpi: _connectedZebraPrinter!.dpi ?? dpi, // Keep existing DPI or use current
          maxPrintWidthInDots: _connectedZebraPrinter!.maxPrintWidthInDots,
          mediaWidthInDots: _connectedZebraPrinter!.mediaWidthInDots,
          connectedAt: _connectedZebraPrinter!.connectedAt,
        );
        print('[Flutter] Updated connected printer dimensions: ${_connectedZebraPrinter.toString()}');
      }
      
      print('[Flutter] Successfully set printer dimensions');
    } catch (e) {
      print('[Flutter] Failed to set printer dimensions: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to set dimensions: $e')),
      );
    }
  }

  Future<void> _getZebraStatus() async {
    if (!_isConnected || _selectedZebraPrinter == null) {
      setState(() => _printerStatus = 'Not connected');
      return;
    }

    try {
      final status = await ZebraPrinter.getStatus();
      setState(() => _printerStatus = status.isOnline ? 'Online' : 'Offline');
    } catch (e) {
      setState(() => _printerStatus = 'Error: $e');
      print('[Flutter] Zebra status error: $e');
    }
  }

  Future<ConnectedPrinter?> _getZebraDimensions() async {
    if (!_isConnected || _selectedZebraPrinter == null) return null;

    try {
      final dimensions = await ZebraPrinter.getPrinterDimensions();
      return ConnectedPrinter(
        discoveredPrinter: _selectedZebraPrinter!,
        printWidthInDots: dimensions['printWidthInDots'] ?? 0,
        labelLengthInDots: dimensions['labelLengthInDots'] ?? 0,
        dpi: dimensions['dpi'] ?? 203,
        connectedAt: DateTime.now(),
      );
    } catch (e) {
      print('[Flutter] Zebra dimensions error: $e');
      return null;
    }
  }

  // Build EpsonPrintCommand list for POS style receipt with standardized commands
  List<EpsonPrintCommand> _buildEpsonPosReceiptCommands() {
    final List<EpsonPrintCommand> cmds = [];

    // Calculate the correct characters per line based on detected paper width
    int effectiveCharsPerLine;
    switch (_epsonLabelPaperWidth) {
      case '58mm': effectiveCharsPerLine = 35; break;  // 58mm - more conservative to match real 58mm behavior
      case '60mm': effectiveCharsPerLine = 34; break;  // 60mm typically 34 chars  
      case '70mm': effectiveCharsPerLine = 42; break;  // 70mm typically 42 chars
      case '76mm': effectiveCharsPerLine = 45; break;  // 76mm typically 45 chars
      case '80mm': effectiveCharsPerLine = 48; break;  // 80mm typically 48 chars
      default:     effectiveCharsPerLine = _posCharsPerLine; break; // Fallback to current setting
    }

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
        return '$left ${right}';
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

    int _estimatePrinterDots() {
      // Map from effective chars per line to dot width
      if (effectiveCharsPerLine <= 32) return 384;   // 58mm common
      if (effectiveCharsPerLine <= 42) return 512;   // 72mm or dense 58mm fonts
      if (effectiveCharsPerLine <= 48) return 576;   // 80mm Font A
      if (effectiveCharsPerLine <= 56) return 640;   // Some 3" models
      if (effectiveCharsPerLine <= 64) return 832;   // 80mm Font B / high density
      return 576; // fallback
    }
    final printerWidthDots = _estimatePrinterDots();

    String title = _headerTitle.trim();
    if (title.isNotEmpty) {
      // Use SDK centering like labels instead of manual padding
      cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'align': 'center' }));
      // Wrap title text to respect the selected paper width
      final wrappedTitleLines = wrapText(title, effectiveCharsPerLine);
      for (String line in wrappedTitleLines) {
        cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'data': line + '\n' }));
      }
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
      // Reset to left alignment after title
      cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'align': 'left' }));
    }

    if (_locationText.trim().isNotEmpty) {
      cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'align': 'center' }));
      // Wrap location text to respect the selected paper width
      final wrappedLocationLines = wrapText(_locationText.trim(), effectiveCharsPerLine);
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
    final dateTime = '${_date.trim()} ${_time.trim()}';
    final cashierStr = 'Cashier: ${_cashier.trim()}';
    cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'align': 'center' }));
    cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'data': leftRight(dateTime, cashierStr) + '\n' }));
    cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'align': 'left' }));

    // Receipt # vs Lane - center the whole line using SDK
    final recLine = 'Receipt: ${_receiptNum.trim()}';
    final laneLine = 'Lane: ${_lane.trim()}';
    cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'align': 'center' }));
    cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'data': leftRight(recLine, laneLine) + '\n' }));
    cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'align': 'left' }));

    // Blank line
    cmds.add(EpsonPrintCommand(type: EpsonCommandType.feed, parameters: { 'line': 1 }));

    // Horizontal line - center using SDK
    cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'align': 'center' }));
    cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'data': horizontalLine() + '\n' }));
    cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'align': 'left' }));

    // Items repeated - center each item line using SDK
    final repeatCount = _itemRepeat;
    for (int i = 0; i < repeatCount; i++) {
      cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'align': 'center' }));
      cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'data': qtyNamePrice(_itemQuantity, _itemName, _itemPrice) + '\n' }));
      cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'align': 'left' }));
    }

    // Second horizontal line - center using SDK
    cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'align': 'center' }));
    cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'data': horizontalLine() + '\n' }));
    cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'align': 'left' }));

    if (_footer.trim().isNotEmpty) {
      cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'align': 'center' }));
      // Wrap footer text to respect the selected paper width
      final wrappedFooterLines = wrapText(_footer.trim(), effectiveCharsPerLine);
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
  // ==========================================================================

  Future<void> _disconnectFromPrinter() async {
    try {
      if (_selectedBrand != null && _isConnected) {
        switch (_selectedBrand!) {
          case PrinterBrand.epson:
            await EpsonPrinter.disconnect();
            break;
          case PrinterBrand.star:
            await star.StarPrinter.disconnect();
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
          final status = await star.StarPrinter.getStatus();
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
          await star.StarPrinter.openCashDrawer();
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
      // Heuristic: decide target width based on original size
      int suggestedWidth = 200;
      try {
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Logo pick failed: $e'))
      );
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
            
            // Brand-specific controls
            if (_selectedBrand == PrinterBrand.zebra) ...[
              _buildZebraControls(),
              const SizedBox(height: 16),
            ] else ...[
              // POS Style Receipt Card for non-Zebra brands
              _buildPosReceiptCard(),
            ],
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
                    
                    // Update the Zebra-specific selected printer when brand is Zebra
                    if (_selectedBrand == PrinterBrand.zebra && newValue != null) {
                      // Find the corresponding DiscoveredPrinter object from the string
                      // Format: '${printer.friendlyName ?? printer.address}:${printer.address}:${printer.interfaceType.toUpperCase()}'
                      try {
                        _selectedZebraPrinter = _zebraDiscoveredPrinters.firstWhere(
                          (printer) => '${printer.friendlyName ?? printer.address}:${printer.address}:${printer.interfaceType.toUpperCase()}' == newValue,
                        );
                      } catch (e) {
                        // If no match found, keep the current selection or use first available
                        _selectedZebraPrinter = _zebraDiscoveredPrinters.isNotEmpty ? _zebraDiscoveredPrinters.first : null;
                      }
                    }
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
                // Universal label printing button
                if (_selectedBrand == PrinterBrand.star || _selectedBrand == PrinterBrand.epson)
                  ElevatedButton.icon(
                    onPressed: _isConnected ? _printLabel : null,
                    icon: const Icon(Icons.label),
                    label: const Text('Print Labels'),
                  ),
                // Epson label printing button

              ],
            ),
            
            // Zebra-specific controls
            if (_selectedBrand == PrinterBrand.zebra) ...[
              const SizedBox(height: 16),
              
              // MAC Address input for Android BTLE connection
              if (Platform.isAndroid) ...[
                const Text('Printer MAC Address (for BTLE):', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: _zebraMacAddressController,
                  decoration: const InputDecoration(
                    hintText: '00:07:4D:XX:XX:XX',
                    border: OutlineInputBorder(),
                    labelText: 'MAC Address',
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _zebraMacAddress = value.trim();
                    });
                  },
                ),
                const SizedBox(height: 8),
                
                // Direct BLE connection button
                ElevatedButton.icon(
                  onPressed: (_isDiscovering || _zebraMacAddress.isEmpty) ? null : _testDirectBleConnection,
                  icon: const Icon(Icons.bluetooth),
                  label: const Text('BTLE (MAC)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              
              // Dimensions controls
              const Text('Printer Dimensions:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    onPressed: _isConnected ? _getZebraDimensionsUI : null,
                    icon: const Icon(Icons.straighten),
                    label: const Text('Get Dimensions'),
                  ),
                  ElevatedButton.icon(
                    onPressed: _isConnected ? _setZebraDimensionsUI : null,
                    icon: const Icon(Icons.settings),
                    label: const Text('Set Dimensions'),
                  ),
                ],
              ),
            ],
            
            const SizedBox(height: 8),
            
            // Star label printing controls
            if (_selectedBrand == PrinterBrand.star) ...[
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Label Paper Width:'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<int>(
                          title: const Text('38mm'),
                          value: 38,
                          groupValue: _labelPaperWidthMm,
                          onChanged: (int? value) {
                            setState(() {
                              _labelPaperWidthMm = value!;
                            });
                          },
                          dense: true,
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<int>(
                          title: const Text('58mm'),
                          value: 58,
                          groupValue: _labelPaperWidthMm,
                          onChanged: (int? value) {
                            setState(() {
                              _labelPaperWidthMm = value!;
                            });
                          },
                          dense: true,
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<int>(
                          title: const Text('80mm'),
                          value: 80,
                          groupValue: _labelPaperWidthMm,
                          onChanged: (int? value) {
                            setState(() {
                              _labelPaperWidthMm = value!;
                            });
                          },
                          dense: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Row(
                children: [
                  const Text('Label Quantity: '),
                  Expanded(
                    child: Slider(
                      value: _labelQuantity.toDouble(),
                      min: 1,
                      max: 10,
                      divisions: 9,
                      label: _labelQuantity.toString(),
                      onChanged: (double value) {
                        setState(() {
                          _labelQuantity = value.round();
                        });
                      },
                    ),
                  ),
                  Text('$_labelQuantity'),
                ],
              ),
            ],
            
            // Epson label printing controls
            if (_selectedBrand == PrinterBrand.epson) ...[
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Epson Label Paper Width:'),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _epsonLabelPaperWidth,
                    decoration: const InputDecoration(
                      labelText: 'Paper Width',
                      border: OutlineInputBorder(),
                      helperText: 'Auto-detected on connection',
                    ),
                    items: _availableEpsonPaperWidths.map((width) {
                      return DropdownMenuItem(
                        value: width,
                        child: Text(width),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      if (newValue != null) {
                        setState(() {
                          _epsonLabelPaperWidth = newValue;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('Label Quantity: '),
                      Expanded(
                        child: Slider(
                          value: _epsonLabelQuantity.toDouble(),
                          min: 1,
                          max: 10,
                          divisions: 9,
                          label: _epsonLabelQuantity.toString(),
                          onChanged: (double value) {
                            setState(() {
                              _epsonLabelQuantity = value.round();
                            });
                          },
                        ),
                      ),
                      Text('$_epsonLabelQuantity'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text('Label Content:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _epsonLabelProductNameController,
                    decoration: const InputDecoration(
                      labelText: 'Product Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _epsonLabelPriceController,
                    decoration: const InputDecoration(
                      labelText: 'Price',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _epsonLabelSizeColourController,
                    decoration: const InputDecoration(
                      labelText: 'Size/Colour',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _epsonLabelScancodeController,
                    decoration: const InputDecoration(
                      labelText: 'Scancode/Barcode',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ],
            
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
