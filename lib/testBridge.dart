import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:zebra_printer/zebra_printer.dart';
import 'package:flutter/foundation.dart';
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

  // Epson paper width configuration  
  String _epsonPaperWidth = 'Unknown';

  // Star paper width configuration
  int _starPaperWidthMm = 58; // Will be synced with StarConfig

  // Zebra-specific fields for direct access
  List<DiscoveredPrinter> _zebraDiscoveredPrinters = [];
  DiscoveredPrinter? _selectedZebraPrinter;
  Map<String, int>? _zebraDimensions; // Store dimensions after connection

  // Image picker state
  String? _logoBase64;
  int _imageWidthPx = 200;
  int _imageSpacingLines = 1;

  @override
  void initState() {
    super.initState();
    _epsonPaperWidth = PrinterBridge.epsonConfig.paperWidth;
    _starPaperWidthMm = PrinterBridge.starConfig.paperWidthMm;
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
                debugPrint('DEBUG: Brand switched to ${newValue?.displayName ?? "None"}');
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
                if (_isConnected && _selectedBrand == PrinterBrand.epson)
                  ElevatedButton.icon(
                    onPressed: _testPaperWidthDetection,
                    icon: const Icon(Icons.straighten),
                    label: const Text('Test Paper Width'),
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
                        debugPrint('Could not find matching Zebra printer: $e');
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
            
            // Epson paper width configuration
            if (_selectedBrand == PrinterBrand.epson) ...[
              const SizedBox(height: 16),
              const Text('Epson Paper Width Configuration:', 
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _epsonPaperWidth,
                decoration: const InputDecoration(
                  labelText: 'Paper Width',
                  border: OutlineInputBorder(),
                  helperText: 'Auto-detected on connection or set manually',
                ),
                items: EpsonConfig.availablePaperWidths.map((width) {
                  return DropdownMenuItem(
                    value: width,
                    child: Text(width),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  if (newValue != null) {
                    setState(() {
                      _epsonPaperWidth = newValue;
                      PrinterBridge.epsonConfig.setPaperWidth(newValue);
                    });
                    debugPrint('📏 Paper width manually set to: $newValue');
                  }
                },
              ),
              const SizedBox(height: 8),
              Text(
                'Characters per line: ${PrinterBridge.epsonConfig.charactersPerLine}',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ],
            
            // Star paper width configuration
            if (_selectedBrand == PrinterBrand.star) ...[
              const SizedBox(height: 16),
              const Text('Star Paper Width Configuration:', 
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                value: _starPaperWidthMm,
                decoration: const InputDecoration(
                  labelText: 'Paper Width (mm)',
                  border: OutlineInputBorder(),
                  helperText: 'Configurable paper width affects layout and printable area',
                ),
                items: StarConfig.availablePaperWidthsMm.map((widthMm) {
                  return DropdownMenuItem(
                    value: widthMm,
                    child: Text('${widthMm}mm'),
                  );
                }).toList(),
                onChanged: (int? newValue) {
                  if (newValue != null) {
                    setState(() {
                      _starPaperWidthMm = newValue;
                      PrinterBridge.starConfig.setPaperWidthMm(newValue);
                    });
                    debugPrint('📏 Star paper width manually set to: ${newValue}mm');
                  }
                },
              ),
              const SizedBox(height: 8),
              Text(
                'Printable area: ${PrinterBridge.starConfig.printableAreaMm}mm, Layout: ${PrinterBridge.starConfig.layoutType}',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ],
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
            
            if (_selectedBrand == PrinterBrand.star && _isConnected) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              
              Text('Star Paper Width Tests:', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    onPressed: _testStarReceiptWidths,
                    icon: const Icon(Icons.receipt),
                    label: const Text('Test Receipt Widths'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                  ),
                  ElevatedButton.icon(
                    onPressed: _testStarLabelWidths,
                    icon: const Icon(Icons.label),
                    label: const Text('Test Label Layouts'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.cyan),
                  ),
                ],
              ),
              
              const SizedBox(height: 8),
              Text(
                'Tests how different paper widths (38mm/58mm/80mm) affect printable area and layout.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
              ),
            ],

            // Image picker section (universal for all brands)
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            
            Text('Receipt Logo', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _pickLogoImage,
                    icon: const Icon(Icons.image),
                    label: const Text('Pick Logo Image'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
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
            
            if (_logoBase64 != null) ...[
              const SizedBox(height: 8),
              Text(
                'Image loaded (${_imageWidthPx}px width). Will be included in receipt printing tests.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: Colors.green[700],
                ),
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
      debugPrint('🔍 Testing PrinterBridge.discover(${_selectedBrand!.name})...');
      final results = await PrinterBridge.discover(_selectedBrand!.name);
      
      debugPrint('✅ Discovery successful: Found ${results.length} printers');
      for (int i = 0; i < results.length; i++) {
        debugPrint('  [$i] ${results[i]}');
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
      debugPrint('❌ Discovery failed: $e');
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
        debugPrint('Network discovery failed: $e');
      }
      
      // Bluetooth discovery
      try {
        final bluetoothPrinters = await ZebraPrinter.discoverBluetoothPrinters();
        _zebraDiscoveredPrinters.addAll(bluetoothPrinters);
      } catch (e) {
        debugPrint('Bluetooth discovery failed: $e');
      }
      
      // USB discovery (Android only)
      if (!Platform.isIOS) {
        try {
          final usbPrinters = await ZebraPrinter.discoverUsbPrinters();
          _zebraDiscoveredPrinters.addAll(usbPrinters);
        } catch (e) {
          debugPrint('USB discovery failed: $e');
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
          debugPrint('Could not match Zebra printer: $e');
        }
      }
    } catch (e) {
      debugPrint('Failed to populate Zebra printers: $e');
    }
  }

  Future<void> _testDiscovery() async {
    await _discoverPrinters();
  }

  Future<void> _connectToPrinter() async {
    if (_selectedPrinter == null || _selectedBrand == null) return;
    
    try {
      debugPrint('🔗 Testing PrinterBridge.connect...');
      final success = await PrinterBridge.connect(
        _selectedPrinter!['brand']!,
        _selectedPrinter!['interface']!,
        _selectedPrinter!['address']!,
      );
      
      setState(() {
        _isConnected = success;
        _printerStatus = success ? 'Connected' : 'Connection Failed';
      });
      
      debugPrint(success ? '✅ Connection successful' : '❌ Connection failed');
      
      // For Zebra printers, fetch and store dimensions after successful connection
      if (success && _selectedBrand == PrinterBrand.zebra) {
        try {
          debugPrint('TestBridge: Fetching Zebra dimensions after connection...');
          final dimensions = await PrinterBridge.getZebraDimensions(forceRefresh: true);
          if (dimensions != null) {
            setState(() {
              _zebraDimensions = dimensions;
            });
            debugPrint('TestBridge: Stored Zebra dimensions: $dimensions');
            
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Connected! Zebra dimensions: ${dimensions['printWidthInDots']}x${dimensions['labelLengthInDots']} @ ${dimensions['dpi']}DPI'
                ),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 4),
              ),
            );
            return; // Skip generic success message
          }
        } catch (e) {
          debugPrint('TestBridge: Error fetching Zebra dimensions: $e');
        }
      }
      
      if (success && _selectedBrand == PrinterBrand.epson) {
        // Try to detect paper width after successful Epson connection
        try {
          final detectedWidth = await PrinterBridge.detectPaperWidth(_selectedBrand!.name);
          if (detectedWidth != null && mounted) {
            // Update UI state to reflect the auto-updated config
            setState(() {
              _epsonPaperWidth = PrinterBridge.epsonConfig.paperWidth;
            });
            
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Connected! Detected paper width: $detectedWidth'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 3),
              ),
            );
            debugPrint('📏 Auto-detected paper width: $detectedWidth');
            return; // Skip the generic success message
          }
        } catch (e) {
          debugPrint('📏 Auto paper width detection failed: $e');
          // Continue to show generic success message
        }
      }
      
      if (success && _selectedBrand == PrinterBrand.zebra) {
        // Try to fetch dimensions after successful Zebra connection
        try {
          debugPrint('TestBridge: Fetching Zebra dimensions after connection...');
          final dimensions = await PrinterBridge.getZebraDimensions(forceRefresh: true);
          if (dimensions != null && mounted) {
            setState(() {
              _zebraDimensions = dimensions;
            });
            
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Connected! Zebra dimensions: ${dimensions['printWidthInDots']}x${dimensions['labelLengthInDots']} @ ${dimensions['dpi']}DPI'
                ),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 4),
              ),
            );
            debugPrint('📐 Stored Zebra dimensions: $dimensions');
            return; // Skip the generic success message
          }
        } catch (e) {
          debugPrint('📐 Zebra dimension fetch failed: $e');
          // Continue to show generic success message
        }
      }
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Connected successfully' : 'Connection failed'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
      
    } catch (e) {
      debugPrint('❌ Connection error: $e');
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
    if (_selectedBrand == null) return;
    
    try {
      final success = await PrinterBridge.disconnect(_selectedBrand!.name);
      setState(() {
        _isConnected = false;
        _printerStatus = success ? 'Disconnected' : 'Disconnect Failed';
      });
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Disconnected successfully' : 'Disconnect failed'),
          backgroundColor: success ? Colors.green : Colors.orange,
        ),
      );
    } catch (e) {
      setState(() {
        _isConnected = false;
        _printerStatus = 'Disconnected';
      });
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Disconnect error: $e')),
      );
    }
  }

  Future<void> _testPaperWidthDetection() async {
    if (!_isConnected || _selectedBrand == null) return;
    
    try {
      debugPrint('📏 Testing PrinterBridge.detectPaperWidth...');
      
      final detectedWidth = await PrinterBridge.detectPaperWidth(_selectedBrand!.name);
      
      if (detectedWidth != null) {
        // Update UI state to reflect the auto-updated config
        setState(() {
          _epsonPaperWidth = PrinterBridge.epsonConfig.paperWidth;
        });
        
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Detected and set paper width: $detectedWidth'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
        debugPrint('✅ Paper width detection successful: $detectedWidth');
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Paper width detection failed or not supported'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
        debugPrint('⚠️ Paper width detection failed');
      }
    } catch (e) {
      debugPrint('❌ Paper width detection error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Paper width detection error: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// Creates the primary test receipt data used across all receipt tests
  PrinterReceiptData _createPrimaryReceiptData() {
    return PrinterReceiptData(
      storeName: 'Metro INC',
      storeAddress: '1030 Adelaide St. N London, ON N5Y 2M9',
      storePhone: '(555) 123-BRIDGE',
      date: '12/19/2025',
      time: '${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}',
      cashierName: 'Harshil',
      receiptNumber: 'ORD584106',
      laneNumber: '1',
      receiptTitle: 'Store Receipt',
      items: [
        PrinterLineItem(
          itemName: 'Alpine Fir Diffuser',
          quantity: 1,
          unitPrice: 38.00,
          totalPrice: 38.00,
        ),
        PrinterLineItem(
          itemName: 'Air Essential Sweatshirt',
          quantity: 1,
          unitPrice: 148.00,
          totalPrice: 148.00,
        ),
        PrinterLineItem(
          itemName: 'A-Line Stripe Embroidered Dress',
          quantity: 1,
          unitPrice: 145.00,
          totalPrice: 145.00,
        )
      ],
      thankYouMessage: 'Thank you for your purchase!',
      logoBase64: _logoBase64, // Include logo if selected
    );
  }

  Future<void> _testReceiptPrinting() async {
    if (!_isConnected || _selectedPrinter == null) return;
    
    try {
      debugPrint('🧾 Testing PrinterBridge.printReceipt...');
      
      final receiptData = _createPrimaryReceiptData();
      
      // For Zebra printers with stored dimensions, use enhanced printing with dynamic height
      if (_selectedBrand == PrinterBrand.zebra && _zebraDimensions != null) {
        await _printZebraReceiptWithDynamicHeight(receiptData);
      } else {
        // For other brands or when dimensions not available, use standard PrinterBridge
        final success = await PrinterBridge.printReceipt(_selectedPrinter!['brand']!, receiptData);
        
        debugPrint(success ? '✅ Receipt print successful' : '❌ Receipt print failed');
        
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Receipt printed successfully!' : 'Receipt print failed'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
      
    } catch (e) {
      debugPrint('❌ Receipt print error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Receipt print error: $e')),
      );
    }
  }

  Future<void> _testLabelPrinting() async {
    if (!_isConnected || _selectedPrinter == null) return;
    
    try {
      debugPrint('Testing PrinterBridge.printLabel...');
      
      final labelData = PrinterLabelData(
        productName: 'T-Shirt',
        price: '\$5.00',
        colorSize: 'Small Turquoise',
        barcode: '123456789',
        quantity: 1,
      );
      
      final success = await PrinterBridge.printLabel(_selectedPrinter!['brand']!, labelData);
      
      debugPrint(success ? '✅ Label print successful' : '❌ Label print failed');
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Label printed successfully!' : 'Label print failed'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
      
    } catch (e) {
      debugPrint('❌ Label print error: $e');
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
    debugPrint('🧾 Testing Zebra receipt on ${_selectedZebraPrinter?.friendlyName ?? "unknown model"}...');
    
    // Use primary receipt data for consistency
    final receiptData = _createPrimaryReceiptData();
    
    await _testReceiptPrintingWithData(receiptData);
  }

  Future<void> _testZebraLabelPrint() async {
    debugPrint('🏷️ Testing Zebra label on ${_selectedZebraPrinter?.friendlyName ?? "unknown model"}...');
    
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
      
      debugPrint(success ? '✅ Model-specific receipt print successful' : '❌ Model-specific receipt print failed');
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Model-optimized receipt printed!' : 'Model-optimized receipt failed'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      debugPrint('❌ Model-specific receipt error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Model-optimized receipt error: $e')),
      );
    }
  }

  Future<void> _testLabelPrintingWithData(PrinterLabelData labelData) async {
    try {
      final success = await PrinterBridge.printLabel(_selectedPrinter!['brand']!, labelData);
      
      debugPrint(success ? '✅ Model-specific label print successful' : '❌ Model-specific label print failed');
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Model-optimized label printed!' : 'Model-optimized label failed'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      debugPrint('❌ Model-specific label error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Model-optimized label error: $e')),
      );
    }
  }

  /// Print Zebra receipt with dynamic height calculation (like main.dart)
  Future<void> _printZebraReceiptWithDynamicHeight(PrinterReceiptData receiptData) async {
    if (_zebraDimensions == null) {
      throw Exception('Zebra dimensions not available');
    }

    final width = _zebraDimensions!['printWidthInDots']!;
    final originalHeight = _zebraDimensions!['labelLengthInDots']!;
    final dpi = _zebraDimensions!['dpi']!;
    
    debugPrint('🧾 Using Zebra dimensions for receipt: ${width}x${originalHeight} @ ${dpi}DPI');
    
    // Calculate required height based on receipt content (same logic as main.dart)
    const baseHeight = 650; // Base receipt elements height in dots
    const itemHeight = 56;  // Height per line item in dots
    const marginHeight = 100; // Bottom margin in dots
    final calculatedHeight = baseHeight + (receiptData.items.length * itemHeight) + marginHeight;
    
    debugPrint('🧾 Receipt height calculation:');
    debugPrint('   Base height: $baseHeight dots');
    debugPrint('   Items (${receiptData.items.length}): ${receiptData.items.length * itemHeight} dots');
    debugPrint('   Margin: $marginHeight dots');
    debugPrint('   Total calculated: $calculatedHeight dots');
    debugPrint('   Original height: $originalHeight dots');
    
    try {
      if (calculatedHeight > originalHeight) {
        debugPrint('🧾 Dynamic height needed! Setting to $calculatedHeight dots');
        
        // Set new label length to accommodate the receipt
        final success = await PrinterBridge.setZebraLabelLength(calculatedHeight);
        if (success) {
          debugPrint('✅ Successfully set dynamic label length to $calculatedHeight dots');
          
          // Generate and print ZPL with new height
          final receiptZpl = PrinterBridge.generateZebraReceiptZPL(width, calculatedHeight, dpi, receiptData);
          await ZebraPrinter.sendCommands(receiptZpl, language: ZebraPrintLanguage.zpl);
          
          // Restore original height
          await PrinterBridge.setZebraLabelLength(originalHeight);
          debugPrint('🔄 Restored original label length to $originalHeight dots');
          
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Zebra receipt printed with dynamic height! ($calculatedHeight dots)'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
            ),
          );
        } else {
          throw Exception('Failed to set dynamic label length');
        }
      } else {
        debugPrint('🧾 Receipt fits in original height, printing normally');
        
        // Generate and print ZPL with original height
        final receiptZpl = PrinterBridge.generateZebraReceiptZPL(width, originalHeight, dpi, receiptData);
        await ZebraPrinter.sendCommands(receiptZpl, language: ZebraPrintLanguage.zpl);
        
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Zebra receipt printed successfully! (${originalHeight} dots)'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Zebra dynamic height receipt error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Zebra receipt error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Test Star receipt printing with different paper widths
  Future<void> _testStarReceiptWidths() async {
    if (!_isConnected || _selectedBrand != PrinterBrand.star) return;

    try {
      debugPrint('🌟 Testing Star receipt printing with different paper widths...');
      
      // Use primary receipt data for consistency
      final receiptData = _createPrimaryReceiptData();

      // Store original width
      final originalWidth = PrinterBridge.starConfig.paperWidthMm;
      
      for (final widthMm in [38, 58, 80]) {
        debugPrint('🌟 Testing with ${widthMm}mm paper width...');
        
        // Update StarConfig
        setState(() {
          _starPaperWidthMm = widthMm;
          PrinterBridge.starConfig.setPaperWidthMm(widthMm);
        });
        
        // Print receipt with this width setting
        final success = await PrinterBridge.printReceipt('star', receiptData);
        
        if (!success) {
          throw Exception('Failed to print receipt with ${widthMm}mm width');
        }
        
        debugPrint('✅ ${widthMm}mm receipt printed (printable: ${PrinterBridge.starConfig.printableAreaMm}mm)');
        
        // Small delay between prints
        await Future.delayed(const Duration(milliseconds: 1000));
      }
      
      // Restore original width
      setState(() {
        _starPaperWidthMm = originalWidth;
        PrinterBridge.starConfig.setPaperWidthMm(originalWidth);
      });
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Star receipt width test completed! Check your receipts to see the differences.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 5),
        ),
      );
    } catch (e) {
      debugPrint('❌ Star receipt width test error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Star receipt width test error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Test Star label printing with different paper widths and layouts
  Future<void> _testStarLabelWidths() async {
    if (!_isConnected || _selectedBrand != PrinterBrand.star) return;

    try {
      debugPrint('🌟 Testing Star label printing with different paper widths and layouts...');
      
      // Store original width
      final originalWidth = PrinterBridge.starConfig.paperWidthMm;
      
      for (final widthMm in [38, 58, 80]) {
        debugPrint('🌟 Testing label with ${widthMm}mm paper width...');
        
        // Update StarConfig
        setState(() {
          _starPaperWidthMm = widthMm;
          PrinterBridge.starConfig.setPaperWidthMm(widthMm);
        });
        
        final printableArea = PrinterBridge.starConfig.printableAreaMm;
        final layoutType = PrinterBridge.starConfig.layoutType;
        
        // Create label data that shows the current configuration
        final labelData = PrinterLabelData(
          productName: '${widthMm}mm Test Product',
          price: '\$${printableArea.toStringAsFixed(1)}',
          colorSize: '${layoutType.replaceAll('_', ' ')} layout',
          barcode: '${widthMm}${printableArea.toInt()}${DateTime.now().millisecondsSinceEpoch % 1000}',
          quantity: 1,
        );
        
        // Print label with this width setting
        final success = await PrinterBridge.printLabel('star', labelData);
        
        if (!success) {
          throw Exception('Failed to print label with ${widthMm}mm width');
        }
        
        debugPrint('✅ ${widthMm}mm label printed (${printableArea}mm printable, ${layoutType} layout)');
        
        // Small delay between prints
        await Future.delayed(const Duration(milliseconds: 1000));
      }
      
      // Restore original width
      setState(() {
        _starPaperWidthMm = originalWidth;
        PrinterBridge.starConfig.setPaperWidthMm(originalWidth);
      });
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Star label layout test completed! Compare the different layouts: vertical_centered (38mm), mixed (58mm), horizontal (80mm).'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 6),
        ),
      );
    } catch (e) {
      debugPrint('❌ Star label width test error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Star label width test error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _pickLogoImage() async {
    // Support iOS & Android; silently ignore on other platforms
    if (!(Platform.isIOS || Platform.isAndroid)) {
      debugPrint('DEBUG: Image picking not supported on this platform');
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
              debugPrint('DEBUG: Storage permission denied (continuing, picker may still work).');
            }
          }
        } catch (permErr) {
          debugPrint('DEBUG: Storage permission check threw (ignoring): $permErr');
        }
      }
      
      final picker = ImagePicker();
      final XFile? file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (file == null) {
        debugPrint('DEBUG: Image pick cancelled');
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
      
      debugPrint('DEBUG: Picked image size=${bytes.lengthInBytes} bytes, suggestedWidth=$suggestedWidth platform=${Platform.isIOS ? 'iOS' : 'Android'}');
    } catch (e) {
      debugPrint('DEBUG: Failed to pick image: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Logo pick failed: $e'))
      );
    }
  }
}