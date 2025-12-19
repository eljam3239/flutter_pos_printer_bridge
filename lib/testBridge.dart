import 'dart:io';

import 'package:flutter/material.dart';
import 'package:zebra_printer/zebra_printer.dart';

import 'printer_bridge.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PrinterBridge Test App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'PrinterBridge Test'),
    );
  }
}

enum PrinterBrand {
  epson('Epson', 'Epson thermal printers (TM series)'),
  star('Star', 'Star Micronics printers'),
  zebra('Zebra', 'Zebra label printers (ZD series)');

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
  PrinterBrand? _selectedBrand;
  List<Map<String, String>> _discoveredPrinters = [];
  Map<String, String>? _selectedPrinter;
  bool _isConnected = false;
  bool _isDiscovering = false;
  String _printerStatus = 'Unknown';

  // Zebra-specific fields for direct access
  List<DiscoveredPrinter> _zebraDiscoveredPrinters = [];
  DiscoveredPrinter? _selectedZebraPrinter;

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
            
            // Testing Cards
            if (_selectedBrand != null) ...[
              _buildTestingCard(),
              const SizedBox(height: 16),
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
                setState(() {
                  _selectedBrand = newValue;
                  _discoveredPrinters = [];
                  _selectedPrinter = null;
                  _isConnected = false;
                  _printerStatus = 'Unknown';
                  _zebraDiscoveredPrinters = [];
                  _selectedZebraPrinter = null;
                });
                print('DEBUG: Brand switched to ${newValue?.displayName ?? "None"}');
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
                  onPressed: (_selectedBrand != null && !_isDiscovering) ? _discoverPrinters : null,
                  icon: _isDiscovering ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.search),
                  label: Text(_isDiscovering ? 'Discovering...' : 'Discover'),
                ),
                ElevatedButton.icon(
                  onPressed: _selectedPrinter != null && !_isConnected ? _connectToPrinter : null,
                  icon: const Icon(Icons.link),
                  label: const Text('Connect'),
                ),
                ElevatedButton.icon(
                  onPressed: _isConnected ? _disconnectFromPrinter : null,
                  icon: const Icon(Icons.link_off),
                  label: const Text('Disconnect'),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Printer selection dropdown
            if (_discoveredPrinters.isNotEmpty) ...[
              DropdownButtonFormField<Map<String, String>>(
                value: _selectedPrinter,
                decoration: const InputDecoration(
                  labelText: 'Select Printer',
                  border: OutlineInputBorder(),
                ),
                items: _discoveredPrinters.map((printer) {
                  return DropdownMenuItem(
                    value: printer,
                    child: Text('${printer['model']} (${printer['interface']?.toUpperCase()})'),
                  );
                }).toList(),
                onChanged: (Map<String, String>? newValue) {
                  setState(() {
                    _selectedPrinter = newValue;
                    
                    // Update Zebra-specific selected printer
                    if (_selectedBrand == PrinterBrand.zebra && newValue != null) {
                      try {
                        _selectedZebraPrinter = _zebraDiscoveredPrinters.firstWhere(
                          (p) => p.address == newValue['address'] && 
                                 p.interfaceType.toLowerCase() == newValue['interface']?.toLowerCase(),
                        );
                      } catch (e) {
                        print('Could not find matching Zebra printer: $e');
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
          ],
        ),
      ),
    );
  }

  Widget _buildTestingCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.science, color: Theme.of(context).primaryColor),
                const SizedBox(width: 8),
                Text('PrinterBridge Testing', style: Theme.of(context).textTheme.headlineSmall),
              ],
            ),
            const SizedBox(height: 16),
            
            Text('Test individual PrinterBridge methods:', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: _selectedBrand != null ? _testDiscovery : null,
                  icon: const Icon(Icons.search),
                  label: const Text('Test Discovery'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                ),
                ElevatedButton.icon(
                  onPressed: _selectedPrinter != null ? _testConnection : null,
                  icon: const Icon(Icons.link),
                  label: const Text('Test Connection'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                ),
                ElevatedButton.icon(
                  onPressed: _isConnected ? _testReceiptPrinting : null,
                  icon: const Icon(Icons.receipt),
                  label: const Text('Test Receipt Print'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                ),
                ElevatedButton.icon(
                  onPressed: _isConnected ? _testLabelPrinting : null,
                  icon: const Icon(Icons.label),
                  label: const Text('Test Label Print'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
                ),
              ],
            ),
            
            if (_selectedBrand == PrinterBrand.zebra && _isConnected) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              
              Text('Zebra-Specific Tests:', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    onPressed: _testZebraReceiptOptimized ? _testZebraReceiptPrint : null,
                    icon: const Icon(Icons.receipt_long),
                    label: const Text('ZD421 Receipt'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  ),
                  ElevatedButton.icon(
                    onPressed: _testZebraLabelOptimized ? _testZebraLabelPrint : null,
                    icon: const Icon(Icons.qr_code),
                    label: const Text('ZD410 Label'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
                  ),
                ],
              ),
              
              const SizedBox(height: 8),
              Text(
                'Note: These buttons detect your printer model and optimize the test accordingly.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // PrinterBridge Testing Methods
  Future<void> _discoverPrinters() async {
    if (_selectedBrand == null) return;
    
    setState(() => _isDiscovering = true);
    
    try {
      print('🔍 Testing PrinterBridge.discover(${_selectedBrand!.name})...');
      final results = await PrinterBridge.discover(_selectedBrand!.name);
      
      print('✅ Discovery successful: Found ${results.length} printers');
      for (int i = 0; i < results.length; i++) {
        print('  [$i] ${results[i]}');
      }
      
      // Store both universal and brand-specific lists
      setState(() {
        _discoveredPrinters = results;
        _selectedPrinter = results.isNotEmpty ? results[0] : null;
        
        // For Zebra, also populate the specific list for model detection
        if (_selectedBrand == PrinterBrand.zebra) {
          // We need to get the raw Zebra printers for model detection
          _populateZebraDiscoveredPrinters();
        }
      });
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Found ${results.length} ${_selectedBrand!.displayName} printers')),
      );
      
    } catch (e) {
      print('❌ Discovery failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Discovery failed: $e')),
      );
    } finally {
      setState(() => _isDiscovering = false);
    }
  }

  Future<void> _populateZebraDiscoveredPrinters() async {
    if (_selectedBrand != PrinterBrand.zebra) return;
    
    try {
      // Re-discover to get raw Zebra objects
      _zebraDiscoveredPrinters.clear();
      
      // Network discovery
      try {
        final networkPrinters = await ZebraPrinter.discoverNetworkPrintersAuto();
        _zebraDiscoveredPrinters.addAll(networkPrinters);
      } catch (e) {
        print('Network discovery failed: $e');
      }
      
      // Bluetooth discovery
      try {
        final bluetoothPrinters = await ZebraPrinter.discoverBluetoothPrinters();
        _zebraDiscoveredPrinters.addAll(bluetoothPrinters);
      } catch (e) {
        print('Bluetooth discovery failed: $e');
      }
      
      // USB discovery (Android only)
      if (!Platform.isIOS) {
        try {
          final usbPrinters = await ZebraPrinter.discoverUsbPrinters();
          _zebraDiscoveredPrinters.addAll(usbPrinters);
        } catch (e) {
          print('USB discovery failed: $e');
        }
      }
      
      // Match selected printer
      if (_selectedPrinter != null) {
        try {
          _selectedZebraPrinter = _zebraDiscoveredPrinters.firstWhere(
            (p) => p.address == _selectedPrinter!['address'] && 
                   p.interfaceType.toLowerCase() == _selectedPrinter!['interface']?.toLowerCase(),
          );
        } catch (e) {
          print('Could not match Zebra printer: $e');
        }
      }
    } catch (e) {
      print('Failed to populate Zebra printers: $e');
    }
  }

  Future<void> _testDiscovery() async {
    await _discoverPrinters();
  }

  Future<void> _connectToPrinter() async {
    if (_selectedPrinter == null || _selectedBrand == null) return;
    
    try {
      print('🔗 Testing PrinterBridge.connect...');
      final success = await PrinterBridge.connect(
        _selectedPrinter!['brand']!,
        _selectedPrinter!['interface']!,
        _selectedPrinter!['address']!,
      );
      
      setState(() {
        _isConnected = success;
        _printerStatus = success ? 'Connected' : 'Connection Failed';
      });
      
      print(success ? '✅ Connection successful' : '❌ Connection failed');
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Connected successfully' : 'Connection failed'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
      
    } catch (e) {
      print('❌ Connection error: $e');
      setState(() {
        _isConnected = false;
        _printerStatus = 'Error: $e';
      });
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connection error: $e')),
      );
    }
  }

  Future<void> _testConnection() async {
    await _connectToPrinter();
  }

  Future<void> _disconnectFromPrinter() async {
    // Note: PrinterBridge doesn't have disconnect yet, so we'll just update state
    setState(() {
      _isConnected = false;
      _printerStatus = 'Disconnected';
    });
    
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Disconnected')),
    );
  }

  Future<void> _testReceiptPrinting() async {
    if (!_isConnected || _selectedPrinter == null) return;
    
    try {
      print('🧾 Testing PrinterBridge.printReceipt...');
      
      final receiptData = PrinterReceiptData(
        storeName: 'Bridge Test Store',
        storeAddress: '123 Bridge Ave, Test City',
        storePhone: '(555) 123-BRIDGE',
        date: '12/19/2025',
        time: '${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}',
        cashierName: 'Bridge Tester',
        receiptNumber: 'BR-${DateTime.now().millisecondsSinceEpoch % 10000}',
        laneNumber: '1',
        items: [
          PrinterLineItem(
            itemName: 'Bridge Test Item A',
            quantity: 2,
            unitPrice: 12.50,
            totalPrice: 25.00,
          ),
          PrinterLineItem(
            itemName: 'Bridge Test Item B',
            quantity: 1,
            unitPrice: 8.99,
            totalPrice: 8.99,
          ),
        ],
        thankYouMessage: 'Thank you for testing PrinterBridge!',
      );
      
      final success = await PrinterBridge.printReceipt(_selectedPrinter!['brand']!, receiptData);
      
      print(success ? '✅ Receipt print successful' : '❌ Receipt print failed');
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Receipt printed successfully!' : 'Receipt print failed'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
      
    } catch (e) {
      print('❌ Receipt print error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Receipt print error: $e')),
      );
    }
  }

  Future<void> _testLabelPrinting() async {
    if (!_isConnected || _selectedPrinter == null) return;
    
    try {
      print('Testing PrinterBridge.printLabel...');
      
      final labelData = PrinterLabelData(
        productName: 'T-Shirt',
        price: '\$5.00',
        colorSize: 'Small Turquoise',
        barcode: '123456789',
        quantity: 1,
      );
      
      final success = await PrinterBridge.printLabel(_selectedPrinter!['brand']!, labelData);
      
      print(success ? '✅ Label print successful' : '❌ Label print failed');
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Label printed successfully!' : 'Label print failed'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
      
    } catch (e) {
      print('❌ Label print error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Label print error: $e')),
      );
    }
  }

  // Zebra model-specific optimization tests
  bool get _testZebraReceiptOptimized {
    if (_selectedZebraPrinter?.friendlyName == null) return true;
    final model = _selectedZebraPrinter!.friendlyName!.toUpperCase();
    return model.contains('ZD421') || model.contains('ZD420'); // Receipt-optimized models
  }

  bool get _testZebraLabelOptimized {
    if (_selectedZebraPrinter?.friendlyName == null) return true;
    final model = _selectedZebraPrinter!.friendlyName!.toUpperCase();
    return model.contains('ZD410') || model.contains('GC420'); // Label-optimized models
  }

  Future<void> _testZebraReceiptPrint() async {
    print('🧾 Testing Zebra receipt on ${_selectedZebraPrinter?.friendlyName ?? "unknown model"}...');
    
    // Create receipt-optimized data for ZD421
    final receiptData = PrinterReceiptData(
      storeName: 'ZD421 Receipt Test',
      storeAddress: '456 Receipt Blvd, Zebra City',
      storePhone: '(555) RECEIPT',
      date: '12/19/2025',
      time: '${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}',
      cashierName: 'ZD421 Tester',
      receiptNumber: 'ZD-${DateTime.now().millisecondsSinceEpoch % 10000}',
      laneNumber: 'ZD421',
      items: [
        PrinterLineItem(itemName: 'ZD421 Optimized Item 1', quantity: 1, unitPrice: 15.50, totalPrice: 15.50),
        PrinterLineItem(itemName: 'ZD421 Optimized Item 2', quantity: 2, unitPrice: 7.25, totalPrice: 14.50),
      ],
      thankYouMessage: 'ZD421 Receipt Test Complete!',
    );
    
    await _testReceiptPrintingWithData(receiptData);
  }

  Future<void> _testZebraLabelPrint() async {
    print('🏷️ Testing Zebra label on ${_selectedZebraPrinter?.friendlyName ?? "unknown model"}...');
    
    // Create label-optimized data for ZD410
    final labelData = PrinterLabelData(
      productName: 'ZD410 Label Test',
      price: '\$99.99',
      colorSize: 'ZD410 Optimized',
      barcode: '410${DateTime.now().millisecondsSinceEpoch % 100000000}',
      quantity: 1,
    );
    
    await _testLabelPrintingWithData(labelData);
  }

  Future<void> _testReceiptPrintingWithData(PrinterReceiptData receiptData) async {
    try {
      final success = await PrinterBridge.printReceipt(_selectedPrinter!['brand']!, receiptData);
      
      print(success ? '✅ Model-specific receipt print successful' : '❌ Model-specific receipt print failed');
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Model-optimized receipt printed!' : 'Model-optimized receipt failed'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      print('❌ Model-specific receipt error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Model-optimized receipt error: $e')),
      );
    }
  }

  Future<void> _testLabelPrintingWithData(PrinterLabelData labelData) async {
    try {
      final success = await PrinterBridge.printLabel(_selectedPrinter!['brand']!, labelData);
      
      print(success ? '✅ Model-specific label print successful' : '❌ Model-specific label print failed');
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Model-optimized label printed!' : 'Model-optimized label failed'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      print('❌ Model-specific label error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Model-optimized label error: $e')),
      );
    }
  }
}