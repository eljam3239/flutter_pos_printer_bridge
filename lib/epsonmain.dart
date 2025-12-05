import 'package:flutter/material.dart';
import 'package:epson_printer/epson_printer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:io' show Platform;
import 'dart:async';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
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
  int _counter = 0;
  List<String> _discoveredPrinters = [];
  bool _isConnected = false;
  String _printerStatus = 'Unknown';
  String? _selectedPrinter;
  bool _openDrawerAfterPrint = true;
  bool _isDiscovering = false;
  bool _usbWasConnectedThisSession = false; // iOS: track if USB ever connected (BT hardware turns off)
  String _nativeDiscoveryState = 'idle';
  bool _pendingWorkQueued = false;
  int _lastSessionId = 0;
  Timer? _statePollTimer;
  
  // ================= Receipt Layout State (Structured Formatting) =================
  // Controllers for dynamic receipt fields. These will allow the user to build argument-driven receipts
  final TextEditingController _headerController = TextEditingController();
  final TextEditingController _detailsController = TextEditingController(); // Multiline: key: value or free-form lines
  final TextEditingController _itemsController = TextEditingController();   // Multiline: item lines (e.g. "2x Coffee @ 3.50")
  final TextEditingController _footerController = TextEditingController();
  final TextEditingController _logoBase64Controller = TextEditingController(); // Optional Base64 image data

  // Label content controllers
  final TextEditingController _labelProductNameController = TextEditingController();
  final TextEditingController _labelPriceController = TextEditingController();
  final TextEditingController _labelSizeColourController = TextEditingController();
  final TextEditingController _labelScancodeController = TextEditingController();

  // Spacing / formatting knobs (can be adjusted via sliders in upcoming UI card)
  double _headerGap = 1;     // feed lines after header block
  double _lineSpacing = 0;   // extra feeds between detail lines
  double _itemSpacing = 0;   // extra feeds between item lines

  // ================= POS Style Receipt Fields (Specific Layout) ==================
  String _headerTitle = "Wendy's";
  int _headerFontSize = 32; 
  int _headerSpacingLines = 1;
  String? _logoBase64; // optional centered image
  int _imageWidthPx = 200; 
  int _imageSpacingLines = 1;
  late final TextEditingController _headerControllerPos; // direct edit of title if needed

  // Detail fields
  String _locationText = '67 LeBron James avenue, Cleveland, OH';
  String _date = '02/10/2025';
  String _time = '2:39 PM';
  String _cashier = 'Eli';
  String _receiptNum = '67676969';
  String _lane = '1';
  String _footer = 'Thank you for shopping with us! Have a nice day!';

  // Single item template (will repeat itemRepeat times)
  String _itemQuantity = '1';
  String _itemName = 'Orange';
  String _itemPrice = '5000.00';
  String _itemRepeat = '3';
  // Estimated characters-per-line for current printer font (adjustable by user)
  int _posCharsPerLine = 48; // 80mm common: 48 (Font A) or 64 (Font B); 58mm 35 right now
  
  // Label Printing Fields
  String _labelProductName = 'Sample Product';
  String _labelPrice = '\$5.00';
  String _labelSizeColour = 'Small Turquoise';
  int _labelScancode = 123456789;

  // Paper size selection for labels - all Epson supported widths
  String _labelPaperWidth = '80mm'; // Default to 80mm
  final List<String> _availablePaperWidths = ['58mm', '60mm', '70mm', '76mm', '80mm'];
  
  // Number of labels to print
  int _labelQuantity = 1;
  // ===============================================================================

  @override
  void initState() {
    super.initState();
    // Initialize receipt controllers with default values
    _headerController.text = 'My Shop\\n123 Sample Street';
    _detailsController.text = 'Order: 12345\\nDate: 2025-01-01 12:34';
    _itemsController.text = '2x Coffee @3.50\\n1x Bagel @2.25';
    _footerController.text = 'Thank you for visiting!';

    // Initialize label controllers with default values
    _labelProductNameController.text = _labelProductName;
    _labelPriceController.text = _labelPrice;
    _labelSizeColourController.text = _labelSizeColour;
    _labelScancodeController.text = _labelScancode.toString();

    // POS style controller
    _headerControllerPos = TextEditingController(text: _headerTitle);

    // Start polling native discovery state (iOS only)
    if (Platform.isIOS) {
      _startDiscoveryStatePolling();
    }
  }

  @override
  void dispose() {
    _headerController.dispose();
    _detailsController.dispose();
    _itemsController.dispose();
    _footerController.dispose();
    _logoBase64Controller.dispose();
    _labelProductNameController.dispose();
    _labelPriceController.dispose();
    _labelSizeColourController.dispose();
    _labelScancodeController.dispose();
    _headerControllerPos.dispose();
    _statePollTimer?.cancel();
    super.dispose();
  }
  // Start periodic polling of native discovery state (iOS only) to handle USB/Bluetooth logic by setting the flag
  void _startDiscoveryStatePolling() {
    _statePollTimer?.cancel();
    _statePollTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      try {
        final state = await EpsonPrinter.getDiscoveryState();
        final nativeState = (state['state'] as String?) ?? 'unknown';
        final sessionId = (state['sessionId'] as int?) ?? 0;
        final usbFlag = state['usbWasConnectedThisSession'] == true;
        final pending = state['pendingWorkQueued'] == true;
        if (!mounted) return;
        setState(() {
          _nativeDiscoveryState = nativeState;
          _lastSessionId = sessionId;
          final usbEver = usbFlag || _usbWasConnectedThisSession;
          if (Platform.isIOS && usbEver) {
            final hadBt = _discoveredPrinters.any((p) => p.startsWith('BT:') || p.startsWith('BLE:'));
            if (hadBt && !_isDiscovering) {
              _discoveredPrinters.removeWhere((p) => p.startsWith('BT:') || p.startsWith('BLE:'));
              if (_selectedPrinter != null && (_selectedPrinter!.startsWith('BT:') || _selectedPrinter!.startsWith('BLE:'))) {
                _selectedPrinter = _discoveredPrinters.isNotEmpty ? _discoveredPrinters.first : null;
              }
            }
          }
          _usbWasConnectedThisSession = usbEver;
          _pendingWorkQueued = pending;
        });
      } catch (e) {
        // Swallow errors during polling
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
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bluetooth permissions are required for printer discovery. Please enable them in settings.'),
              duration: Duration(seconds: 5),
            ),
          );
        }
      }
    }
  }
  //funny artifact from the early days
  void _incrementCounter() {
    setState(() {
      _counter++;
    });
  }

  Future<void> _discoverPrinters() async {
    try {
      final printers = await EpsonPrinter.discoverPrinters();
      setState(() {
        _discoveredPrinters = printers;
        //if any printers are discovered the selectec printer is set to first
        if (_selectedPrinter == null || !printers.contains(_selectedPrinter)) { 
          _selectedPrinter = printers.isNotEmpty ? printers.first : null;
        }
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Found ${printers.length} printers')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Discovery failed: $e')),
      );
    }
  }

  //one button discovery
  Future<void> _discoverAllPrinters() async {
    // Prevent concurrent discoveries
    if (_isDiscovering || _nativeDiscoveryState != 'idle') {
      print('Discovery already in progress or native state not idle ($_nativeDiscoveryState)');
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
    
    if (!mounted) return;
    
    setState(() {
      _isDiscovering = true;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Discovering printers (LAN${Platform.isIOS ? ', USB' : ', Bluetooth, USB'})...')),
    );

    // Build a fresh snapshot each time to avoid stale entries from prior runs
    final List<String> snapshot = [];
    int totalFound = 0;

    // Discover LAN printers
    try {
      final lanPrinters = await EpsonPrinter.discoverPrinters();
      snapshot.addAll(lanPrinters);
      totalFound += lanPrinters.length;
      print('LAN discovery found ${lanPrinters.length} printers');
    } catch (e) {
      print('LAN discovery error: $e');
      // Continue even if LAN fails
    }

    // Small delay to let SDK fully clean up between discoveries
    await Future.delayed(const Duration(milliseconds: 500));

    // Discover Bluetooth printers
    // iOS: Skip if USB was ever connected (BT hardware turns off and won't come back until app restart)
    if (Platform.isIOS && _usbWasConnectedThisSession) {
      print('iOS: Skipping Bluetooth discovery - USB was connected this session');
    } else {
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
        print('Bluetooth discovery found ${btPrinters.length} printers');
      } catch (e) {
        print('Bluetooth discovery error: $e');
        // Continue even if Bluetooth fails
      }
    }

    // Small delay to let SDK fully clean up between discoveries
    await Future.delayed(const Duration(milliseconds: 500));

    // Discover USB printers AFTER Bluetooth (so iOS can filter out BT devices)
    try {
      final usbPrinters = await EpsonPrinter.discoverUsbPrinters();
      
      // iOS: Mark that USB was discovered - BT hardware will be disabled from now on
      if (Platform.isIOS && usbPrinters.isNotEmpty) {
        _usbWasConnectedThisSession = true;
        print('iOS: USB connected - Bluetooth hardware now disabled on printer');
      }
      
      snapshot.addAll(usbPrinters);
      totalFound += usbPrinters.length;
      print('USB discovery found ${usbPrinters.length} printers');
    } catch (e) {
      print('USB discovery error: $e');
      // Continue even if USB fails
    }

    // iOS: if USB was ever connected, ensure no BT/BLE entries are shown
    if (Platform.isIOS && _usbWasConnectedThisSession) {
      snapshot.removeWhere((p) => p.startsWith('BT:') || p.startsWith('BLE:'));
    }

    // Commit snapshot and selection
    setState(() {
      _isDiscovering = false;
      _discoveredPrinters = snapshot;
      if (_selectedPrinter == null || !_discoveredPrinters.contains(_selectedPrinter)) {
        _selectedPrinter = _discoveredPrinters.isNotEmpty ? _discoveredPrinters.first : null;
      }
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Discovery complete! Found $totalFound total printers')),
    );
  }

  Future<void> _abortDiscoveryIfNeeded() async {
    try {
      if (_nativeDiscoveryState != 'idle') {
        await EpsonPrinter.abortDiscovery();
        // Poll immediately after abort
        final state = await EpsonPrinter.getDiscoveryState();
        setState(() { _nativeDiscoveryState = (state['state'] as String?) ?? 'idle'; });
      }
    } catch (e) {
      // Ignore abort errors
    }
  }

  Future<void> _connectToPrinter() async {
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
        if (_availablePaperWidths.contains(detectedWidth)) {
          setState(() => _labelPaperWidth = detectedWidth);
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
  }
  //direct bluetooth pairing -- hidden on Android
  Future<void> _pairBluetooth() async {
    try {
      final res = await EpsonPrinter.pairBluetoothDevice();
      final target = res['target'] as String?;
      final code = res['resultCode'];
      if (target != null && target.isNotEmpty) {
        setState(() {
          final entry = '$target:PairedPrinter';
          if (!_discoveredPrinters.contains(entry)) {
            _discoveredPrinters.add(entry);
          }
          _selectedPrinter = entry;
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Paired: $target (code=$code)')),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Pairing failed (code=$code)')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pairing error: $e')),
      );
    }
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
      // Attempt to build structured commands from layout inputs.
      final structured = _buildReceiptCommandsFromLayout();

      // If all fields empty, we fall back automatically. Otherwise, ensure structured has content.
      final anyFieldNotEmpty = _headerController.text.trim().isNotEmpty ||
          _detailsController.text.trim().isNotEmpty ||
          _itemsController.text.trim().isNotEmpty ||
          _footerController.text.trim().isNotEmpty ||
          _logoBase64Controller.text.trim().isNotEmpty;
      if (anyFieldNotEmpty && structured.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nothing to print: please add header, details, items, footer or logo data.')),
        );
        return;
      }

      final commands = structured.isNotEmpty
          ? structured
          : [
              // Fallback legacy demo content if no structured input provided.
              EpsonPrintCommand(type: EpsonCommandType.text, parameters: {'data': 'EPSON PRINTER TEST\n'}),
              EpsonPrintCommand(type: EpsonCommandType.text, parameters: {'data': '================\n'}),
              EpsonPrintCommand(type: EpsonCommandType.feed, parameters: {'line': 1}),
              EpsonPrintCommand(type: EpsonCommandType.text, parameters: {'data': 'Counter: $_counter\n'}),
              EpsonPrintCommand(type: EpsonCommandType.text, parameters: {'data': 'Legacy Demo Mode\n'}),
              EpsonPrintCommand(type: EpsonCommandType.feed, parameters: {'line': 2}),
              EpsonPrintCommand(type: EpsonCommandType.text, parameters: {'data': 'Thank you!\n'}),
              EpsonPrintCommand(type: EpsonCommandType.feed, parameters: {'line': 1}),
              EpsonPrintCommand(type: EpsonCommandType.cut, parameters: {}),
            ];

      final printJob = EpsonPrintJob(commands: commands);

      await EpsonPrinter.printReceipt(printJob);

      if (_openDrawerAfterPrint && _isConnected) {
        try {
          await EpsonPrinter.openCashDrawer();
        } catch (_) {}
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_openDrawerAfterPrint ? 'Print job sent and drawer opened' : 'Print job sent successfully')),
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

    try {
      // Build label commands based on current label fields and paper width
      final commands = _buildLabelCommands();
      final printJob = EpsonPrintJob(commands: commands);
      
      // Print multiple labels based on quantity setting
      for (int i = 0; i < _labelQuantity; i++) {
        await EpsonPrinter.printReceipt(printJob);
        
        // Small delay between prints to avoid overwhelming the printer
        if (i < _labelQuantity - 1) {
          await Future.delayed(const Duration(milliseconds: 200));
        }
      }

      if (!mounted) return;
      final message = _labelQuantity == 1 
          ? 'Label printed successfully!' 
          : '$_labelQuantity labels printed successfully!';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Label print failed: $e')),
      );
    }
  }

  List<EpsonPrintCommand> _buildLabelCommands() {
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
      parameters: {'data': _labelProductNameController.text.trim() + '\n'}
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
      parameters: {'data': _labelPriceController.text.trim() + '\n'}
    ));
    
    // Size/Color (centered under price)
    commands.add(EpsonPrintCommand(
      type: EpsonCommandType.text,
      parameters: {'data': _labelSizeColourController.text.trim() + '\n'}
    ));
    
    // CODE128 barcode with HRI below (center alignment already set)
    commands.add(EpsonPrintCommand(
      type: EpsonCommandType.barcode,
      parameters: {
        'data': _labelScancodeController.text.trim(),
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
    
    // // Add minimal spacing before cut to ensure proper positioning
    // commands.add(EpsonPrintCommand(
    //   type: EpsonCommandType.feed,
    //   parameters: {'line': 1}
    // ));
    
    commands.add(EpsonPrintCommand(
      type: EpsonCommandType.cut,
      parameters: {} // Back to default CUT_FEED but with minimal manual feed
    ));
    
    return commands;
  }

  // Build EpsonPrintCommand list from current layout controller contents.
  // This is intentionally conservative: relies only on 'text', 'feed', 'cut' for broad compatibility.
  List<EpsonPrintCommand> _buildReceiptCommandsFromLayout() {
    final List<EpsonPrintCommand> cmds = [];

    String header = _headerController.text.trim();
    String details = _detailsController.text.trim();
    String items = _itemsController.text.trim();
    String footer = _footerController.text.trim();
    String logoB64 = _logoBase64Controller.text.trim();

    bool hasAny = header.isNotEmpty || details.isNotEmpty || items.isNotEmpty || footer.isNotEmpty || logoB64.isNotEmpty;
    if (!hasAny) {
      return [];
    }

    void addTextBlock(String block) {
      if (block.isEmpty) return;
      // Ensure newline termination for printer line flush.
      if (!block.endsWith('\n')) block = '$block\n';
      cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'data': block }));
    }

    // Header block (may contain internal newlines)
    if (header.isNotEmpty) {
      addTextBlock(header);
      if (_headerGap > 0) {
        cmds.add(EpsonPrintCommand(type: EpsonCommandType.feed, parameters: { 'line': _headerGap.round() }));
      }
    }

    // Placeholder for logo image if provided (SDK may later support image command type)
    if (logoB64.isNotEmpty) {
      // For now just add a marker line so user knows image would print here.
      addTextBlock('[LOGO]\n');
    }

    // Details: treat each non-empty line individually, applying optional spacing
    if (details.isNotEmpty) {
      final lines = details.split(RegExp(r'\r?\n')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      for (int i = 0; i < lines.length; i++) {
        addTextBlock(lines[i]);
        if (_lineSpacing > 0 && i != lines.length - 1) {
          cmds.add(EpsonPrintCommand(type: EpsonCommandType.feed, parameters: { 'line': _lineSpacing.round() }));
        }
      }
      // Gap after details block (reuse lineSpacing semantics if desired)
      if (_lineSpacing > 0) {
        cmds.add(EpsonPrintCommand(type: EpsonCommandType.feed, parameters: { 'line': 1 }));
      }
    }

    // Items: raw lines for now (future parsing for qty/price alignment)
    if (items.isNotEmpty) {
      final itemLines = items.split(RegExp(r'\r?\n')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      for (int i = 0; i < itemLines.length; i++) {
        addTextBlock(itemLines[i]);
        if (_itemSpacing > 0 && i != itemLines.length - 1) {
          cmds.add(EpsonPrintCommand(type: EpsonCommandType.feed, parameters: { 'line': _itemSpacing.round() }));
        }
      }
      // Add a separating feed after items
      cmds.add(EpsonPrintCommand(type: EpsonCommandType.feed, parameters: { 'line': 1 }));
    }

    // Footer
    if (footer.isNotEmpty) {
      addTextBlock(footer);
    }

    // Final feeds + cut
    cmds.add(EpsonPrintCommand(type: EpsonCommandType.feed, parameters: { 'line': 2 }));
    cmds.add(EpsonPrintCommand(type: EpsonCommandType.cut, parameters: {}));

    return cmds;
  }

  List<EpsonPrintCommand> _buildPosReceiptCommands() {
    final List<EpsonPrintCommand> cmds = [];

    // Calculate the correct characters per line based on detected paper width
    int effectiveCharsPerLine;
    switch (_labelPaperWidth) {
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

    String title = _headerControllerPos.text.trim().isNotEmpty ? _headerControllerPos.text.trim() : _headerTitle.trim();
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
          cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'data': '[LOGO ERR]' + '\n' }));
        }
      }
      if (_headerSpacingLines > 0) {
        cmds.add(EpsonPrintCommand(type: EpsonCommandType.feed, parameters: { 'line': _headerSpacingLines }));
      }
      // Reset to left alignment after title
      cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'align': 'left' }));
    }

    // Future style/image usage placeholder (avoid unused field warnings until implemented)
    // ignore: unused_local_variable
    final _stylePlaceholder = {
      'fontSize': _headerFontSize,
      'logoProvided': _logoBase64 != null,
      'imageWidth': _imageWidthPx,
      'imageSpacing': _imageSpacingLines,
    };

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
    final repeatCount = int.tryParse(_itemRepeat) ?? 1;
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

  Future<void> _pickLogoImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery, maxWidth: _imageWidthPx.toDouble());
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

  Future<void> _disconnectFromPrinter() async {
    try {
      await EpsonPrinter.disconnect();
      setState(() => _isConnected = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Disconnected from printer')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Disconnect failed: $e')),
      );
    }
  }

  Future<void> _getStatus() async {
    try {
      final status = await EpsonPrinter.getStatus();
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please connect to a printer first')),
      );
      return;
    }
    try {
      await EpsonPrinter.openCashDrawer();
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

  Future<void> _discoverBluetoothPrinters() async {
    try {
      // iOS: If USB was connected in this app session, the printer disables BT radio.
      // Purge any stale BT entries and skip discovery.
      if (Platform.isIOS && _usbWasConnectedThisSession) {
        setState(() {
          _discoveredPrinters.removeWhere((p) => p.startsWith('BT:') || p.startsWith('BLE:'));
          if (_selectedPrinter != null && (_selectedPrinter!.startsWith('BT:') || _selectedPrinter!.startsWith('BLE:'))) {
            _selectedPrinter = _discoveredPrinters.isNotEmpty ? _discoveredPrinters.first : null;
          }
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bluetooth disabled on printer after USB connect; skipping Bluetooth discovery.')),
        );
        return;
      }
      if (Platform.isAndroid) {
        final bluetoothConnectStatus = await Permission.bluetoothConnect.status;
        final bluetoothScanStatus = await Permission.bluetoothScan.status;
        if (!bluetoothConnectStatus.isGranted || !bluetoothScanStatus.isGranted) {
          await _checkAndRequestPermissions();
          final newConnect = await Permission.bluetoothConnect.status;
          final newScan = await Permission.bluetoothScan.status;
          if (!newConnect.isGranted || !newScan.isGranted) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Bluetooth permissions required for Bluetooth discovery'),
                action: SnackBarAction(label: 'Open Settings', onPressed: () => openAppSettings()),
                duration: const Duration(seconds: 8),
              ),
            );
            return;
          }
        }
      }

      final printers = await EpsonPrinter.discoverBluetoothPrinters();
      setState(() {
        final bluetoothPrinters = printers.where((p) => p.startsWith('BT:') || p.startsWith('BLE:')).toList();
        final updatedPrinters = List<String>.from(_discoveredPrinters);
        updatedPrinters.removeWhere((p) => p.startsWith('BT:') || p.startsWith('BLE:'));
        updatedPrinters.addAll(bluetoothPrinters);
        _discoveredPrinters = updatedPrinters;
        if (_selectedPrinter == null || !_discoveredPrinters.contains(_selectedPrinter)) {
          _selectedPrinter = _discoveredPrinters.isNotEmpty ? _discoveredPrinters.first : null;
        }
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Found ${printers.length} Bluetooth printers')),
      );
    } catch (e) {
      var message = 'Bluetooth discovery failed: $e';
      if (e.toString().contains('BLUETOOTH_PERMISSION_DENIED')) {
        message = 'Bluetooth permissions required. Please grant permissions and try again.';
      } else if (e.toString().contains('BLUETOOTH_UNAVAILABLE')) {
        message = 'Bluetooth is not available or disabled. Please enable Bluetooth.';
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Future<void> _discoverUsbPrinters() async {
    try {
      final printers = await EpsonPrinter.discoverUsbPrinters();
      setState(() {
        final updated = List<String>.from(_discoveredPrinters);
        updated.removeWhere((p) => p.startsWith('USB:'));
        updated.addAll(printers.where((p) => p.startsWith('USB:')));
        if (Platform.isIOS && printers.any((p) => p.startsWith('USB:'))) {
          _usbWasConnectedThisSession = true;
          // Purge any BT entries once USB is seen (printer BT hardware turned off)
          updated.removeWhere((p) => p.startsWith('BT:') || p.startsWith('BLE:'));
          if (_selectedPrinter != null && (_selectedPrinter!.startsWith('BT:') || _selectedPrinter!.startsWith('BLE:'))) {
            _selectedPrinter = null;
          }
        }
        _discoveredPrinters = updated;
        if (_selectedPrinter == null && _discoveredPrinters.isNotEmpty) {
          _selectedPrinter = _discoveredPrinters.first;
        }
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Found ${printers.length} USB printers')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('USB discovery failed: $e')),
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
            
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Counter Demo', style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    const Text('You have pushed the button this many times:'),
                    Text('$_counter', style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 16),
                    ElevatedButton(onPressed: _incrementCounter, child: const Text('Increment Counter')),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // ================= Receipt Layout Editor Card =================
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Receipt Layout', style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        ElevatedButton(
                          onPressed: _pickLogoImage,
                          child: const Text('Pick Logo'),
                        ),
                        const SizedBox(width: 8),
                        if (_logoBase64 != null && _logoBase64!.isNotEmpty)
                          ElevatedButton(
                            onPressed: () => setState(() => _logoBase64 = null),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                            child: const Text('Clear Logo'),
                          ),
                      ],
                    ),
                    if (_logoBase64 != null && _logoBase64!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 80,
                        child: Image.memory(
                          // decode preview (safe minimal) - if large, consider resizing
                          // ignore: unnecessary_raw_strings
                          const Base64Decoder().convert(_logoBase64!),
                          fit: BoxFit.contain,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: _headerController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Header (multi-line allowed)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _detailsController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Details (each line printed separately)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _itemsController,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Items (one line per item)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _footerController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Footer',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ExpansionTile(
                      title: const Text('Advanced / Logo & Spacing'),
                      children: [
                        TextField(
                          controller: _logoBase64Controller,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Logo (Base64) - placeholder only right now',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _SliderRow(
                          label: 'Header Gap',
                          value: _headerGap,
                          min: 0,
                          max: 5,
                          divisions: 5,
                          onChanged: (v) => setState(() => _headerGap = v),
                        ),
                        _SliderRow(
                          label: 'Detail Line Spacing',
                          value: _lineSpacing,
                          min: 0,
                          max: 3,
                          divisions: 3,
                          onChanged: (v) => setState(() => _lineSpacing = v),
                        ),
                        _SliderRow(
                          label: 'Item Spacing',
                          value: _itemSpacing,
                          min: 0,
                          max: 3,
                          divisions: 3,
                          onChanged: (v) => setState(() => _itemSpacing = v),
                        ),
                        const SizedBox(height: 8),
                        Builder(
                          builder: (context) {
                            final detailLines = _detailsController.text.trim().isEmpty
                                ? 0
                                : _detailsController.text.trim().split(RegExp('\\r?\\n')).where((l) => l.trim().isNotEmpty).length;
                            final itemLines = _itemsController.text.trim().isEmpty
                                ? 0
                                : _itemsController.text.trim().split(RegExp('\\r?\\n')).where((l) => l.trim().isNotEmpty).length;
                            return Text('Preview: header=${_headerController.text.trim().isEmpty ? 0 : 1}, details=$detailLines, items=$itemLines, footer=${_footerController.text.trim().isEmpty ? 0 : 1}');
                          },
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: _isConnected ? _printReceipt : null,
                          child: const Text('Print Structured Receipt'),
                        ),
                        const SizedBox(height: 16),
                        // Label content fields
                        const Text('Label Content', 
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _labelProductNameController,
                          decoration: const InputDecoration(
                            labelText: 'Product Name',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _labelPriceController,
                          decoration: const InputDecoration(
                            labelText: 'Price',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _labelSizeColourController,
                          decoration: const InputDecoration(
                            labelText: 'Size / Colour',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _labelScancodeController,
                          decoration: const InputDecoration(
                            labelText: 'Scancode/Barcode',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Paper size selection for labels
                        const Text('How wide is your label printer paper?', 
                          style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        // Create radio buttons for all available paper widths
                        Wrap(
                          spacing: 16.0,
                          runSpacing: 8.0,
                          children: _availablePaperWidths.map((width) => Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Radio<String>(
                                value: width,
                                groupValue: _labelPaperWidth,
                                onChanged: (value) => setState(() => _labelPaperWidth = value!),
                              ),
                              Text(width),
                            ],
                          )).toList(),
                        ),
                        const SizedBox(height: 16),
                        // Label quantity slider
                        const Text('Number of labels to print:', 
                          style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Text('1'),
                            Expanded(
                              child: Slider(
                                value: _labelQuantity.toDouble(),
                                min: 1.0,
                                max: 10.0,
                                divisions: 9,
                                label: _labelQuantity.toString(),
                                onChanged: (double value) {
                                  setState(() {
                                    _labelQuantity = value.round();
                                  });
                                },
                              ),
                            ),
                            const Text('10'),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('Quantity: $_labelQuantity', 
                          style: const TextStyle(fontSize: 16)),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: _isConnected ? _printLabel : null,
                          child: const Text('Print Label'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // Native discovery state banner (references session and queued work so fields aren't unused)
            if (Platform.isIOS) Row(
              children: [
                Expanded(
                  child: Text(
                    'Discovery state: '
                    '$_nativeDiscoveryState | session=$_lastSessionId'
                    '${_pendingWorkQueued ? ' | queued' : ''}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
                if (_nativeDiscoveryState != 'idle')
                  TextButton(
                    onPressed: _abortDiscoveryIfNeeded,
                    child: const Text('Abort'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Epson Printer Controls', style: Theme.of(context).textTheme.headlineSmall),
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
                              final parts = printer.split(':');
                              final model = parts.length > 2 ? parts[2] : 'Unknown';
                              final mac = parts.length > 1 ? parts[1] : 'Unknown';
                              final displayMac = mac.length > 8 ? '${mac.substring(0, 8)}...' : mac;
                              return DropdownMenuItem<String>(
                                value: printer,
                                child: Text('$model ($displayMac)'),
                              );
                            }).toList(),
                            onChanged: (String? newValue) {
                              setState(() {
                                _selectedPrinter = newValue;
                                _isConnected = false;
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_selectedPrinter != null)
                        Text('Selected: ${_selectedPrinter!}', style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                    ],
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
                        const Expanded(child: Text('Auto-open cash drawer after printing')),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        ElevatedButton(onPressed: _checkAndRequestPermissions, child: const Text('Check Permissions')),
                        ElevatedButton(
                          onPressed: _discoverAllPrinters,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Discover Printers'),
                        ),
                        ElevatedButton(onPressed: _discoverPrinters, child: const Text('Discover LAN')),
                        ElevatedButton(onPressed: _discoverBluetoothPrinters, child: const Text('Discover Bluetooth')),
                        ElevatedButton(onPressed: _discoverUsbPrinters, child: const Text('Discover USB')),
                        // Hide Pair button on Android
                        if (!Platform.isAndroid)
                          ElevatedButton(onPressed: _pairBluetooth, child: const Text('Pair Bluetooth')),
                        ElevatedButton(onPressed: _selectedPrinter != null && !_isConnected ? _connectToPrinter : null, child: const Text('Connect')),
                        ElevatedButton(onPressed: _isConnected ? _disconnectFromPrinter : null, child: const Text('Disconnect')),
                        ElevatedButton(onPressed: _isConnected ? _printReceipt : null, child: const Text('Print Test Receipt')),
                        ElevatedButton(onPressed: _isConnected ? _printLabel : null, child: const Text('Print Label')),
                        ElevatedButton(
                          onPressed: _isConnected
                              ? () async {
                                  final cmds = _buildPosReceiptCommands();
                                  if (cmds.isEmpty) {
                                    if (!mounted) return; 
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('POS receipt has no content.')));
                                    return;
                                  }
                                  try {
                                    await EpsonPrinter.printReceipt(EpsonPrintJob(commands: cmds));
                                    if (_openDrawerAfterPrint) {
                                      try { await EpsonPrinter.openCashDrawer(); } catch (_) {}
                                    }
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('POS Receipt sent')));
                                  } catch (e) {
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('POS print failed: $e')));
                                  }
                                }
                              : null,
                          child: const Text('Print POS Receipt'),
                        ),
                        ElevatedButton(onPressed: _getStatus, child: const Text('Get Status')),
                        ElevatedButton(onPressed: _isConnected ? _openCashDrawer : null, child: const Text('Open Cash Drawer')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // POS Receipt Field Quick Adjust Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('POS Receipt Fields', style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Chars / Line'),
                              Slider(
                                value: _posCharsPerLine.toDouble(),
                                min: 24,
                                max: 64,
                                divisions: 40,
                                label: _posCharsPerLine.toString(),
                                onChanged: (v) => setState(() => _posCharsPerLine = v.round()),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 60,
                          child: Text('${_posCharsPerLine}', textAlign: TextAlign.center),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _headerControllerPos,
                      decoration: const InputDecoration(labelText: 'Header Title', border: OutlineInputBorder()),
                      onChanged: (v) => setState(() => _headerTitle = v),
                    ),
                    const SizedBox(height: 12),
                    _TwoCol(
                      left: TextField(
                        decoration: const InputDecoration(labelText: 'Date', border: OutlineInputBorder()),
                        controller: TextEditingController(text: _date),
                        onSubmitted: (v) => setState(() => _date = v),
                      ),
                      right: TextField(
                        decoration: const InputDecoration(labelText: 'Time', border: OutlineInputBorder()),
                        controller: TextEditingController(text: _time),
                        onSubmitted: (v) => setState(() => _time = v),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _TwoCol(
                      left: TextField(
                        decoration: const InputDecoration(labelText: 'Cashier', border: OutlineInputBorder()),
                        controller: TextEditingController(text: _cashier),
                        onSubmitted: (v) => setState(() => _cashier = v),
                      ),
                      right: TextField(
                        decoration: const InputDecoration(labelText: 'Receipt #', border: OutlineInputBorder()),
                        controller: TextEditingController(text: _receiptNum),
                        onSubmitted: (v) => setState(() => _receiptNum = v),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _TwoCol(
                      left: TextField(
                        decoration: const InputDecoration(labelText: 'Lane', border: OutlineInputBorder()),
                        controller: TextEditingController(text: _lane),
                        onSubmitted: (v) => setState(() => _lane = v),
                      ),
                      right: TextField(
                        decoration: const InputDecoration(labelText: 'Location', border: OutlineInputBorder()),
                        controller: TextEditingController(text: _locationText),
                        onSubmitted: (v) => setState(() => _locationText = v),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _TwoCol(
                      left: TextField(
                        decoration: const InputDecoration(labelText: 'Item Qty', border: OutlineInputBorder()),
                        controller: TextEditingController(text: _itemQuantity),
                        onSubmitted: (v) => setState(() => _itemQuantity = v),
                      ),
                      right: TextField(
                        decoration: const InputDecoration(labelText: 'Item Name', border: OutlineInputBorder()),
                        controller: TextEditingController(text: _itemName),
                        onSubmitted: (v) => setState(() => _itemName = v),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _TwoCol(
                      left: TextField(
                        decoration: const InputDecoration(labelText: 'Item Price', border: OutlineInputBorder()),
                        controller: TextEditingController(text: _itemPrice),
                        onSubmitted: (v) => setState(() => _itemPrice = v),
                      ),
                      right: TextField(
                        decoration: const InputDecoration(labelText: 'Repeat Count', border: OutlineInputBorder()),
                        controller: TextEditingController(text: _itemRepeat),
                        onSubmitted: (v) => setState(() => _itemRepeat = v),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: const InputDecoration(labelText: 'Footer', border: OutlineInputBorder()),
                      controller: TextEditingController(text: _footer),
                      onSubmitted: (v) => setState(() => _footer = v),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    Text('Preview lines: POS receipt auto-formatted'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}

// Small helper widget for labeled slider rows inside the receipt layout card.
class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
        Expanded(
          flex: 5,
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: value.toStringAsFixed(0),
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 32,
          child: Text(value.toStringAsFixed(0), textAlign: TextAlign.center),
        ),
      ],
    );
  }
}

class _TwoCol extends StatelessWidget {
  final Widget left;
  final Widget right;
  const _TwoCol({required this.left, required this.right});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: left),
        const SizedBox(width: 12),
        Expanded(child: right),
      ],
    );
  }
}
