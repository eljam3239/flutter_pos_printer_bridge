import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:zebra_printer/zebra_printer.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zebra Printer Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'Zebra Printer Demo'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  List<DiscoveredPrinter> _discoveredPrinters = [];
  bool _isConnected = false;
  String _printerStatus = 'Unknown';
  DiscoveredPrinter? _selectedPrinter;
  ConnectedPrinter? _connectedPrinter; // Store connected printer with dimensions
  bool _isDiscovering = false;
  int _labelQuantity = 1;
  String _macAddress = '';
  final TextEditingController _macAddressController = TextEditingController();

  // Receipt form state
  bool _showReceiptForm = false;
  final TextEditingController _storeNameController = TextEditingController();
  final TextEditingController _storeAddressController = TextEditingController();
  final TextEditingController _storePhoneController = TextEditingController();
  final TextEditingController _receiptNumberController = TextEditingController();
  final TextEditingController _cashierNameController = TextEditingController();
  final TextEditingController _laneNumberController = TextEditingController();
  final TextEditingController _thankYouMessageController = TextEditingController();
  List<Map<String, TextEditingController>> _lineItemControllers = [];

  @override
  void dispose() {
    _macAddressController.dispose();
    _storeNameController.dispose();
    _storeAddressController.dispose();
    _storePhoneController.dispose();
    _receiptNumberController.dispose();
    _cashierNameController.dispose();
    _laneNumberController.dispose();
    _thankYouMessageController.dispose();
    for (var controllerMap in _lineItemControllers) {
      controllerMap['quantity']?.dispose();
      controllerMap['item']?.dispose();
      controllerMap['price']?.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _addLineItem(); // Add initial line item
  }

  void _addLineItem() {
    setState(() {
      _lineItemControllers.add({
        'quantity': TextEditingController(),
        'item': TextEditingController(),
        'price': TextEditingController(),
      });
    });
  }

  void _removeLineItem(int index) {
    if (_lineItemControllers.length > 1) {
      setState(() {
        _lineItemControllers[index]['quantity']?.dispose();
        _lineItemControllers[index]['item']?.dispose();
        _lineItemControllers[index]['price']?.dispose();
        _lineItemControllers.removeAt(index);
      });
    }
  }

  void _clearDiscoveries() {
    // Force disconnect if connected when clearing discoveries
    if (_isConnected) {
      _disconnectFromPrinter();
    }
    
    setState(() {
      _discoveredPrinters.clear();
      _selectedPrinter = null;
      _isConnected = false;
      _printerStatus = 'Unknown';
      _connectedPrinter = null;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cleared all discovered printers')),
    );
  }

  Future<void> _discoverPrinters() async {
    setState(() {
      _isDiscovering = true;
    });

    try {
      // Use actual Zebra printer discovery
      print('[Flutter] Starting printer discovery...');
      final printers = await ZebraPrinter.discoverPrinters();
      print('[Flutter] Discovery completed. Found ${printers.length} printers');
      
      setState(() {
        // Merge with existing discoveries - allow duplicates for different interfaces
        _discoveredPrinters.addAll(printers);
        
        // Preserve selected printer reference if it still exists, otherwise select first
        if (_selectedPrinter != null) {
          final matchingPrinter = _discoveredPrinters
              .where((p) => p.address == _selectedPrinter!.address && p.interfaceType == _selectedPrinter!.interfaceType)
              .firstOrNull;
          _selectedPrinter = matchingPrinter ?? (_discoveredPrinters.isNotEmpty ? _discoveredPrinters.first : null);
        } else {
          _selectedPrinter = _discoveredPrinters.isNotEmpty ? _discoveredPrinters.first : null;
        }
        
        _isDiscovering = false;
        _labelQuantity = 1;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Found ${printers.length} printers')),
      );
    } catch (e) {
      print('[Flutter] Discovery failed: $e');
      setState(() {
        _isDiscovering = false;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Discovery failed: $e')),
      );
    }
  }

  Future<void> _discoverMulticastPrinters() async {
    setState(() {
      _isDiscovering = true;
    });

    try {
      print('[Flutter] Starting multicast discovery...');
      final printers = await ZebraPrinter.discoverMulticastPrinters(hops: 3);
      print('[Flutter] Multicast discovery completed. Found ${printers.length} printers');
      
      setState(() {
        // Add new printers - allow duplicates for different interfaces
        _discoveredPrinters.addAll(printers);
        
        // Preserve selected printer reference if it still exists, otherwise select first
        if (_selectedPrinter != null) {
          final matchingPrinter = _discoveredPrinters
              .where((p) => p.address == _selectedPrinter!.address && p.interfaceType == _selectedPrinter!.interfaceType)
              .firstOrNull;
          _selectedPrinter = matchingPrinter ?? (_discoveredPrinters.isNotEmpty ? _discoveredPrinters.first : null);
        } else {
          _selectedPrinter = _discoveredPrinters.isNotEmpty ? _discoveredPrinters.first : null;
        }
        _isDiscovering = false;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Multicast found ${printers.length} printers')),
      );
    } catch (e) {
      print('[Flutter] Multicast discovery failed: $e');
      setState(() {
        _isDiscovering = false;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Multicast discovery failed: $e')),
      );
    }
  }

  Future<void> _discoverSubnetPrinters() async {
    setState(() {
      _isDiscovering = true;
    });

    try {
      print('[Flutter] Starting subnet search discovery...');
      // Search common private network ranges
      final printers = await ZebraPrinter.discoverSubnetSearch('10.20.30.*');
      print('[Flutter] Subnet discovery completed. Found ${printers.length} printers');
      
      setState(() {
        // Add new printers - allow duplicates for different interfaces
        _discoveredPrinters.addAll(printers);
        
        _selectedPrinter = _discoveredPrinters.isNotEmpty ? _discoveredPrinters.first : null;
        _isDiscovering = false;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Subnet search found ${printers.length} printers')),
      );
    } catch (e) {
      print('[Flutter] Subnet discovery failed: $e');
      setState(() {
        _isDiscovering = false;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Subnet discovery failed: $e')),
      );
    }
  }
  Future<void> _discoverAll() async {
    // Clear discoveries at the beginning of the comprehensive discovery
    setState(() {
      _discoveredPrinters.clear();
    });
    
    //if iOS, skip USB discovery
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await _discoverNetworkPrintersAuto();
      await _discoverBluetoothPrinters();
      return;
    } else {
      // Android - do all discoveries
      await _discoverUsbPrinters();
      await _discoverNetworkPrintersAuto();
      await _discoverBluetoothPrinters();
      // if mac address is provided, do direct ble connection test
      if (_macAddress.isNotEmpty) {
        await _testDirectBleConnection();
      }
      return;
    }
  }

  Future<void> _discoverNetworkPrintersAuto() async {
    setState(() {
      _isDiscovering = true;
    });

    try {
      print('[Flutter] Starting automatic network discovery...');
      final printers = await ZebraPrinter.discoverNetworkPrintersAuto();
      print('[Flutter] Auto discovery completed. Found ${printers.length} printers');
      
      setState(() {
        // Add new printers - allow duplicates for different interfaces
        _discoveredPrinters.addAll(printers);
        
        _selectedPrinter = _discoveredPrinters.isNotEmpty ? _discoveredPrinters.first : null;
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

  Future<void> _discoverBluetoothPrinters() async {
    setState(() {
      _isDiscovering = true;
    });

    try {
      print('[Flutter] Starting Bluetooth LE discovery...');
      final printers = await ZebraPrinter.discoverBluetoothPrinters();
      print('[Flutter] Bluetooth discovery completed. Found ${printers.length} printers');
      
      setState(() {
        // Merge with existing discoveries - allow duplicates for different interfaces
        _discoveredPrinters.addAll(printers);
        
        _selectedPrinter = _discoveredPrinters.isNotEmpty ? _discoveredPrinters.first : null;
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

  // Commented out - not used anymore
  /*
  Future<void> _discoverBluetoothNative() async {
    setState(() {
      _isDiscovering = true;
    });

    try {
      print('[Flutter] Starting native Bluetooth scan...');
      final printers = await ZebraPrinter.discoverBluetoothNative();
      print('[Flutter] Native Bluetooth scan completed. Found ${printers.length} devices');
      
      setState(() {
        // Add new printers - allow duplicates for different interfaces
        _discoveredPrinters.addAll(printers);
        
        _selectedPrinter = _discoveredPrinters.isNotEmpty ? _discoveredPrinters.first : null;
        _isDiscovering = false;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Native BT scan found ${_discoveredPrinters.length} devices')),
      );
    } catch (e) {
      print('[Flutter] Native Bluetooth scan failed: $e');
      setState(() {
        _isDiscovering = false;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Native BT scan failed: $e')),
      );
    }
  }
  */

  Future<void> _testDirectBleConnection() async {
    if (_macAddress.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter MAC address first')),
      );
      return;
    }

    setState(() {
      _isDiscovering = true;
    });

    try {
      print('[Flutter] Testing direct BLE connection to MAC: $_macAddress');
      final printers = await ZebraPrinter.testDirectBleConnection(macAddress: _macAddress);
      print('[Flutter] Direct BLE test completed. Found ${printers.length} printers');
      
      setState(() {
        // Merge with existing discoveries - allow duplicates for different interfaces
        _discoveredPrinters.addAll(printers);
        
        _isDiscovering = false;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Direct BLE test found ${printers.length} devices')),
      );
    } catch (e) {
      print('[Flutter] Direct BLE connection test failed: $e');
      setState(() {
        _isDiscovering = false;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Direct BLE test failed: $e')),
      );
    }
  }

  Future<void> _discoverUsbPrinters() async {
    // Check if running on iOS
    if (defaultTargetPlatform == TargetPlatform.iOS) {
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
        _discoveredPrinters.addAll(printers);
        
        // Preserve selected printer reference if it still exists
        if (_selectedPrinter != null) {
          final matchingPrinter = _discoveredPrinters
              .where((p) => p.address == _selectedPrinter!.address && p.interfaceType == _selectedPrinter!.interfaceType)
              .firstOrNull;
          _selectedPrinter = matchingPrinter;
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

  // Commented out - not used anymore
  /*
  Future<void> _requestBluetoothPermissions() async {
    try {
      print('[Flutter] Requesting Bluetooth permissions...');
      final granted = await ZebraPrinter.requestBluetoothPermissions();
      
      if (!mounted) return;
      
      if (granted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bluetooth permissions granted! You can now use Bluetooth discovery.'),
            duration: Duration(seconds: 3),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bluetooth permissions denied. Please grant them manually in Settings.'),
            duration: Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      print('[Flutter] Permission request failed: $e');
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Permission request failed: $e')),
      );
    }
  }
  */

  Future<void> _connectToPrinter() async {
    if (_selectedPrinter == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a printer first.')),
      );
      return;
    }

    try {
      // Force disconnect from current printer if connected, with additional cleanup
      if (_isConnected) {
        print('[Flutter] Force disconnecting from current printer before connecting to new one...');
        try {
          await ZebraPrinter.disconnect();
          // Add a small delay to ensure cleanup completes
          await Future.delayed(const Duration(milliseconds: 500));
          setState(() {
            _isConnected = false;
            _printerStatus = 'Disconnected';
            _connectedPrinter = null;
          });
        } catch (e) {
          print('[Flutter] Error disconnecting from current printer: $e');
          // Force reset state even if disconnect failed
          setState(() {
            _isConnected = false;
            _printerStatus = 'Disconnected';
            _connectedPrinter = null;
          });
        }
      }
      
      // Create connection settings based on the selected printer's interface type
      ZebraInterfaceType interfaceType;
      if (_selectedPrinter!.interfaceType == 'bluetooth') {
        interfaceType = ZebraInterfaceType.bluetooth;
        print('[Flutter] Connecting via Bluetooth to ${_selectedPrinter!.address}');
      } else if (_selectedPrinter!.interfaceType == 'usb') {
        interfaceType = ZebraInterfaceType.usb;
        print('[Flutter] Connecting via USB to ${_selectedPrinter!.address}');
      } else {
        interfaceType = ZebraInterfaceType.tcp;
        print('[Flutter] Connecting via TCP to ${_selectedPrinter!.address}');
      }
      
      final settings = ZebraConnectionSettings(
        interfaceType: interfaceType,
        identifier: _selectedPrinter!.address,
        timeout: 15000,
      );

      print('[Flutter] Attempting connection with settings: ${settings.toString()}');
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
          
          _connectedPrinter = ConnectedPrinter(
            discoveredPrinter: _selectedPrinter!,
            printWidthInDots: retryDimensions['printWidthInDots'],
            labelLengthInDots: retryDimensions['labelLengthInDots'], 
            dpi: retryDimensions['dpi'],
            maxPrintWidthInDots: retryDimensions['maxPrintWidthInDots'],
            mediaWidthInDots: retryDimensions['mediaWidthInDots'],
            connectedAt: DateTime.now(),
          );
        } else {
          _connectedPrinter = ConnectedPrinter(
            discoveredPrinter: _selectedPrinter!,
            printWidthInDots: dimensions['printWidthInDots'],
            labelLengthInDots: dimensions['labelLengthInDots'], 
            dpi: dimensions['dpi'],
            maxPrintWidthInDots: dimensions['maxPrintWidthInDots'],
            mediaWidthInDots: dimensions['mediaWidthInDots'],
            connectedAt: DateTime.now(),
          );
        }
        
        print('[Flutter] Connected printer dimensions: ${_connectedPrinter.toString()}');
      } catch (dimensionError) {
        print('[Flutter] Warning: Could not fetch printer dimensions: $dimensionError');
        // Still create connected printer object without dimensions
        _connectedPrinter = ConnectedPrinter(
          discoveredPrinter: _selectedPrinter!,
          connectedAt: DateTime.now(),
        );
      }
      
      setState(() {
        _isConnected = true;
        _printerStatus = 'Connected';
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connected to: ${_selectedPrinter!.friendlyName ?? _selectedPrinter!.address} [${_selectedPrinter!.interfaceType.toUpperCase()}]')),
      );
    } catch (e) {
      print('[Flutter] Connection failed with error: $e');
      setState(() {
        _isConnected = false;
        _printerStatus = 'Connection Failed';
        _connectedPrinter = null;
      });

      if (!mounted) return;
      
      String errorMessage = 'Connection failed: $e';
      
      // Provide specific guidance for common Bluetooth connection issues
      if (e.toString().contains('socket might closed') || 
          e.toString().contains('read failed') ||
          e.toString().contains('read ret: -1')) {
        errorMessage = 'Bluetooth connection failed!\n\n'
            'This can happen when switching from TCP to Bluetooth.\n'
            'Try:\n• Wait a few seconds and try again\n'
            '• Turn Bluetooth off and on\n'
            '• Restart the app if issue persists\n\n'
            'Original error: $e';
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  Future<void> _disconnectFromPrinter() async {
    try {
      print('[Flutter] Disconnecting from printer...');
      await ZebraPrinter.disconnect();
      
      // Add a small delay to ensure cleanup completes
      await Future.delayed(const Duration(milliseconds: 300));
      
      setState(() {
        _isConnected = false;
        _printerStatus = 'Disconnected';
        _connectedPrinter = null; // Clear connected printer data
      });

      print('[Flutter] Disconnection successful');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Disconnected from printer')),
      );
    } catch (e) {
      print('[Flutter] Disconnect failed: $e');
      // Force reset state even if disconnect failed
      setState(() {
        _isConnected = false;
        _printerStatus = 'Disconnected';
        _connectedPrinter = null;
      });
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Disconnect completed (with issues): $e')),
      );
    }
  }

  ReceiptData _buildReceiptDataFromForm() {
    // Build line items from controllers
    List<ReceiptLineItem> items = [];
    for (var controllerMap in _lineItemControllers) {
      final qtyText = controllerMap['quantity']?.text.trim() ?? '';
      final itemText = controllerMap['item']?.text.trim() ?? '';
      final priceText = controllerMap['price']?.text.trim() ?? '';
      
      // Only add line item if all fields have values
      if (qtyText.isNotEmpty && itemText.isNotEmpty && priceText.isNotEmpty) {
        final qty = int.tryParse(qtyText) ?? 0;
        final price = double.tryParse(priceText) ?? 0.0;
        
        if (qty > 0 && price > 0.0) {
          items.add(ReceiptLineItem(
            quantity: qty,
            itemName: itemText,
            unitPrice: price,
          ));
        }
      }
    }
    
    // Debug: Print what we're getting from the form
    print('[Flutter] Form values captured:');
    print('[Flutter] - Store Name: "${_storeNameController.text.trim()}"');
    print('[Flutter] - Store Address: "${_storeAddressController.text.trim()}"');
    print('[Flutter] - Store Phone: "${_storePhoneController.text.trim()}"');
    print('[Flutter] - Receipt Number: "${_receiptNumberController.text.trim()}"');
    print('[Flutter] - Cashier Name: "${_cashierNameController.text.trim()}"');
    print('[Flutter] - Lane Number: "${_laneNumberController.text.trim()}"');
    print('[Flutter] - Thank You Message: "${_thankYouMessageController.text.trim()}"');
    print('[Flutter] - Line Items: ${items.length} items');
    for (int i = 0; i < items.length; i++) {
      print('[Flutter]   Item ${i + 1}: ${items[i].toString()}');
    }
    
    final receiptData = ReceiptData(
      storeName: _storeNameController.text.trim().isEmpty 
          ? 'My Store' 
          : _storeNameController.text.trim(),
      storeAddress: _storeAddressController.text.trim().isEmpty 
          ? '123 Main Street' 
          : _storeAddressController.text.trim(),
      storePhone: _storePhoneController.text.trim().isEmpty 
          ? null 
          : _storePhoneController.text.trim(),
      receiptNumber: _receiptNumberController.text.trim().isEmpty 
          ? null 
          : _receiptNumberController.text.trim(),
      transactionDate: DateTime.now(),
      cashierName: _cashierNameController.text.trim().isEmpty 
          ? null 
          : _cashierNameController.text.trim(),
      laneNumber: _laneNumberController.text.trim().isEmpty 
          ? null 
          : _laneNumberController.text.trim(),
      items: items,
      thankYouMessage: _thankYouMessageController.text.trim().isEmpty 
          ? 'Thank you for shopping with us!' 
          : _thankYouMessageController.text.trim(),
    );
    
    print('[Flutter] Final ReceiptData: ${receiptData.toString()}');
    return receiptData;
  }

  Future<void> _printReceipt() async {
    if (!_isConnected) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please connect to a printer first')),
      );
      return;
    }

    try {
      if (_connectedPrinter == null) {
        throw Exception('No connected printer information available');
      }
      
      // Use actual detected dimensions, with fallbacks
      final width = _connectedPrinter!.printWidthInDots ?? 386; // fallback to ZD410 width
      final height = _connectedPrinter!.labelLengthInDots ?? 212; // fallback to common label height
      final dpi = _connectedPrinter!.dpi ?? 203; // fallback to common Zebra DPI
      
      print('[Flutter] Using printer dimensions: ${width}x${height} @ ${dpi}dpi');
      
      // Build receipt data from form inputs
      final receiptData = _buildReceiptDataFromForm();
      
      // Use the receipt ZPL
      final receiptZpl = await _generateReceiptZPL(width, height, dpi, receiptData);
      
      await ZebraPrinter.sendCommands(receiptZpl, language: ZebraPrintLanguage.zpl);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Receipt sent successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Print failed: $e')),
      );
    }
  }

  Future<void> _printLabel() async {
    if (!_isConnected) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please connect to a printer first')),
      );
      return;
    }
    // String productName = "T-Shirt";
    // String colorSize = "Small Turquoise";
    // String scancode = "123456789";
    // String price = "\$5.00";
    // double paperWidthMM = 54.1;

    // int scancodeLength = scancode.length;
    // // Calculate barcode position
    // int dpi = 203;
    // double paperWidthInches = paperWidthMM / 25.4;
    // int paperWidthDots = (paperWidthInches * dpi).round();

    // // Estimate barcode width for Code 128
    // // Code 128: Each character takes ~11 modules + start/stop characters
    // int totalBarcodeCharacters = scancodeLength + 3; // +3 for start, check, and stop characters
    // int moduleWidth = 2; // from ^BY2
    // int estimatedBarcodeWidth = totalBarcodeCharacters * 11 * moduleWidth;

    // // Calculate centered X position for barcode
    // int barcodeX = (paperWidthDots - estimatedBarcodeWidth) ~/ 2;

    // // Ensure barcode doesn't go off the left edge
    // barcodeX = barcodeX.clamp(0, paperWidthDots - estimatedBarcodeWidth);


    try {
      // Check if we have connected printer with dimensions
      if (_connectedPrinter == null) {
        throw Exception('No connected printer information available');
      }
      
      // Use actual detected dimensions, with fallbacks
      final width = _connectedPrinter!.printWidthInDots ?? 386; // fallback to ZD410 width
      final height = _connectedPrinter!.labelLengthInDots ?? 212; // fallback to common label height
      final dpi = _connectedPrinter!.dpi ?? 203; // fallback to common Zebra DPI
      
      print('[Flutter] Using printer dimensions: ${width}x${height} @ ${dpi}dpi');
      
      // Create label data object (in future, this could come from UI or API)
      final labelData = LabelData(
        productName: "T-Shirt",
        colorSize: "Small Turquoise", 
        scancode: "123456789",
        price: "\$5.00",
      );
      
      // Generate ZPL with actual printer dimensions, DPI, and label data
      String tShirtLabelZpl = await _generateLabelZPL(width, height, dpi, labelData);
      
      // Print labels based on quantity
      for (int i = 0; i < _labelQuantity; i++) {
        await ZebraPrinter.sendCommands(tShirtLabelZpl, language: ZebraPrintLanguage.zpl);
        
        // Small delay between labels to prevent overwhelming the printer
        if (i < _labelQuantity - 1) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$_labelQuantity label(s) sent successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Label print failed: $e')),
      );
    }
  }

  Future<void> _getPrinterDimensions() async {
    if (!_isConnected) {
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

      // Show both sets of dimensions in the dialog
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Printer Dimensions'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Built-in Method:', style: TextStyle(fontWeight: FontWeight.bold)),
                ...dimensions.entries.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                    child: Text('${entry.key}: ${entry.value}', 
                      style: const TextStyle(fontFamily: 'monospace')),
                  );
                }).toList(),
                const SizedBox(height: 16),
                const Text('SGD Parameters:', style: TextStyle(fontWeight: FontWeight.bold)),
                ...sgdDimensions.entries.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                    child: Text('${entry.key}: ${entry.value ?? "null"}', 
                      style: const TextStyle(fontFamily: 'monospace')),
                  );
                }).toList(),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      print('[Flutter] Failed to get printer dimensions: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to get dimensions: $e')),
      );
    }
  }

  Future<void> _setPrinterDimensions() async {
    if (!_isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please connect to a printer first')),
      );
      return;
    }

    // Show dialog to input width and height
    final TextEditingController widthController = TextEditingController();
    final TextEditingController heightController = TextEditingController();

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
      final dpi = 203;//dimensions['dpi'] ?? 203; // Default to 203 DPI if not available
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
      if (_connectedPrinter != null) {
        _connectedPrinter = ConnectedPrinter(
          discoveredPrinter: _connectedPrinter!.discoveredPrinter,
          printWidthInDots: targetWidthInDots,
          labelLengthInDots: heightInDots,
          dpi: _connectedPrinter!.dpi ?? dpi, // Keep existing DPI or use current
          maxPrintWidthInDots: _connectedPrinter!.maxPrintWidthInDots,
          mediaWidthInDots: _connectedPrinter!.mediaWidthInDots,
          connectedAt: _connectedPrinter!.connectedAt,
        );
        print('[Flutter] Updated connected printer dimensions: ${_connectedPrinter.toString()}');
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
  
  // Generate label ZPL with given dimensions and label data
  Future<String> _generateLabelZPL(int width, int height, int dpi, LabelData labelData) async {
    // Extract label content from the data object
    String productName = labelData.productName;
    String colorSize = labelData.colorSize;
    String scancode = labelData.scancode;
    String price = labelData.price;
    
    double paperWidthMM = 54.1;
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

  Future<String> _generateReceiptZPL(int width, int height, int dpi, ReceiptData receiptData) async {
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
      receiptZpl += '''
^CF0,30
^FO470,478
^FDCashier: ${receiptData.cashierName}^FS''';
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
    totalX = totalX.clamp(0, width - estimatedTotalWidth);
    
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Zebra Printer Controls', style: Theme.of(context).textTheme.headlineSmall),
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
                          child: DropdownButton<DiscoveredPrinter>(
                            value: _selectedPrinter,
                            hint: const Text('Select a printer'),
                            isExpanded: true,
                            items: _discoveredPrinters.map((printer) {
                              final displayName = printer.friendlyName?.isNotEmpty == true 
                                  ? printer.friendlyName!
                                  : 'Zebra Printer';
                              final displayAddress = printer.address.length > 15 
                                  ? '${printer.address.substring(0, 15)}...'
                                  : printer.address;
                              final interfaceType = printer.interfaceType.toUpperCase();
                              return DropdownMenuItem<DiscoveredPrinter>(
                                value: printer,
                                child: Text('$displayName ($displayAddress) [$interfaceType]'),
                              );
                            }).toList(),
                            onChanged: (DiscoveredPrinter? newValue) {
                              setState(() {
                                _selectedPrinter = newValue;
                                _isConnected = false;
                                _printerStatus = 'Unknown';
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_selectedPrinter != null)
                        Text('Selected: ${_selectedPrinter!.address} (Port: ${_selectedPrinter!.port}) [${_selectedPrinter!.interfaceType.toUpperCase()}]', 
                             style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                    ],
                    const SizedBox(height: 16),
                    Text('Connection Status: ${_isConnected ? "Connected" : "Disconnected"}'),
                    const SizedBox(height: 8),
                    Text('Printer Status: $_printerStatus'),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        // ElevatedButton(
                        //   onPressed: _isDiscovering ? null : _discoverPrinters,
                        //   style: ElevatedButton.styleFrom(
                        //     backgroundColor: Colors.blue,
                        //     foregroundColor: Colors.white,
                        //   ),
                        //   child: _isDiscovering 
                        //     ? const SizedBox(
                        //         width: 16,
                        //         height: 16,
                        //         child: CircularProgressIndicator(
                        //           strokeWidth: 2,
                        //           valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        //         ),
                        //       )
                        //     : const Text('Discover Printers (Local)'),
                        // ),
                        // ElevatedButton(
                        //   onPressed: _isDiscovering ? null : _discoverMulticastPrinters,
                        //   style: ElevatedButton.styleFrom(
                        //     backgroundColor: Colors.green,
                        //     foregroundColor: Colors.white,
                        //   ),
                        //   child: const Text('Discover (Multicast)'),
                        // ),
                        // ElevatedButton(
                        //   onPressed: _isDiscovering ? null : _discoverSubnetPrinters,
                        //   style: ElevatedButton.styleFrom(
                        //     backgroundColor: Colors.orange,
                        //     foregroundColor: Colors.white,
                        //   ),
                        //   child: const Text('Discover (Subnet)'),
                        // ),
                        ElevatedButton(
                          onPressed: _isDiscovering ? null : _discoverAll,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Discover All Printers'),
                        ),
                        ElevatedButton(
                          onPressed: _isDiscovering ? null : _discoverNetworkPrintersAuto,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.purple,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Auto Discover (LAN)'),
                        ),
                        ElevatedButton(
                          onPressed: _isDiscovering ? null : _discoverBluetoothPrinters,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Discover (Bluetooth)'),
                        ),
                        ElevatedButton(
                          onPressed: _discoveredPrinters.isEmpty ? null : _clearDiscoveries,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Clear Discoveries'),
                        ),
                        // Commented out Native BT Scan
                        // ElevatedButton(
                        //   onPressed: _isDiscovering ? null : _discoverBluetoothNative,
                        //   style: ElevatedButton.styleFrom(
                        //     backgroundColor: Colors.cyan,
                        //     foregroundColor: Colors.white,
                        //   ),
                        //   child: const Text('Native BT Scan'),
                        // ),
                        if (defaultTargetPlatform == TargetPlatform.android)
                          ElevatedButton(
                            onPressed: (_isDiscovering || _macAddress.isEmpty) ? null : _testDirectBleConnection,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.purple,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('BTLE (MAC)'),
                          ),
                        ElevatedButton(
                          onPressed: _isDiscovering ? null : _discoverUsbPrinters,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.brown,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Discover USB'),
                        ),
                        // Commented out Grant BT Permissions button
                        // ElevatedButton(
                        //   onPressed: _requestBluetoothPermissions,
                        //   style: ElevatedButton.styleFrom(
                        //     backgroundColor: Colors.indigo,
                        //     foregroundColor: Colors.white,
                        //   ),
                        //   child: const Text('Grant BT Permissions'),
                        // ),
                        ElevatedButton(
                          onPressed: _selectedPrinter != null ? _connectToPrinter : null,
                          child: const Text('Connect'),
                        ),
                        ElevatedButton(
                          onPressed: _isConnected ? _disconnectFromPrinter : null,
                          child: const Text('Disconnect'),
                        ),
                        ElevatedButton(
                          onPressed: _isConnected ? _printReceipt : null,
                          child: const Text('Print Receipt'),
                        ),
                        ElevatedButton(
                          onPressed: _isConnected ? _printLabel : null,
                          child: const Text('Print Label'),
                        ),
                        ElevatedButton(
                          onPressed: _isConnected ? _getPrinterDimensions : null,
                          child: const Text('Get Dimensions'),
                        ),
                        ElevatedButton(
                          onPressed: _isConnected ? _setPrinterDimensions : null,
                          child: const Text('Set Dimensions'),
                        ),
                        
                      ],
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
                        // MAC Address input for Android BTLE connection
                        if (defaultTargetPlatform == TargetPlatform.android) ...[
                          const SizedBox(height: 16),
                          const Text('Printer MAC Address (for BTLE):', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _macAddressController,
                            decoration: const InputDecoration(
                              hintText: '00:07:4D:XX:XX:XX',
                              border: OutlineInputBorder(),
                              labelText: 'MAC Address',
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            onChanged: (value) {
                              setState(() {
                                _macAddress = value.trim();
                              });
                            },
                          ),
                        ],
                  ],
                ),
              ),
            ),

            // Receipt Form Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header with dropdown indicator
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _showReceiptForm = !_showReceiptForm;
                        });
                      },
                      child: Row(
                        children: [
                          Text('Receipt Generator', style: Theme.of(context).textTheme.headlineSmall),
                          const Spacer(),
                          Icon(_showReceiptForm ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down),
                        ],
                      ),
                    ),
                    
                    // Collapsible form
                    if (_showReceiptForm) ...[
                      const SizedBox(height: 16),
                      
                      // Store Information
                      Text('Store Information', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _storeNameController,
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
                              controller: _storeAddressController,
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
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _storePhoneController,
                              decoration: const InputDecoration(
                                labelText: 'Phone',
                                hintText: '(555) 123-4567',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _receiptNumberController,
                              decoration: const InputDecoration(
                                labelText: 'Receipt #',
                                hintText: '12345',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _cashierNameController,
                              decoration: const InputDecoration(
                                labelText: 'Cashier',
                                hintText: 'John Doe',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _laneNumberController,
                              decoration: const InputDecoration(
                                labelText: 'Lane #',
                                hintText: '3',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Line Items
                      Text('Line Items', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      
                      // Line item entries
                      ...List.generate(_lineItemControllers.length, (index) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 80,
                                child: TextField(
                                  controller: _lineItemControllers[index]['quantity'],
                                  decoration: const InputDecoration(
                                    labelText: 'Qty',
                                    border: OutlineInputBorder(),
                                  ),
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 3,
                                child: TextField(
                                  controller: _lineItemControllers[index]['item'],
                                  decoration: const InputDecoration(
                                    labelText: 'Item Name',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  controller: _lineItemControllers[index]['price'],
                                  decoration: const InputDecoration(
                                    labelText: 'Price',
                                    border: OutlineInputBorder(),
                                  ),
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                ),
                              ),
                              if (_lineItemControllers.length > 1) ...[
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.remove_circle, color: Colors.red),
                                  onPressed: () => _removeLineItem(index),
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
                          onPressed: _addLineItem,
                        ),
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Thank you message
                      TextField(
                        controller: _thankYouMessageController,
                        decoration: const InputDecoration(
                          labelText: 'Thank You Message',
                          hintText: 'Thank you for shopping with us!',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Generate receipt button
                      Center(
                        child: ElevatedButton(
                          onPressed: _isConnected ? _printReceipt : null,
                          child: const Text('Generate Receipt'),
                        ),
                      ),
                    ],
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
