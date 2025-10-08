import 'package:flutter/material.dart';
import 'package:epson_printer/epson_printer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:io' show Platform;

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
  
  // ================= Receipt Layout State (Structured Formatting) =================
  // Controllers for dynamic receipt fields. These will allow the user to build
  // argument-driven receipts similar to the Star printer sample.
  final TextEditingController _headerController = TextEditingController();
  final TextEditingController _detailsController = TextEditingController(); // Multiline: key: value or free-form lines
  final TextEditingController _itemsController = TextEditingController();   // Multiline: item lines (e.g. "2x Coffee @ 3.50")
  final TextEditingController _footerController = TextEditingController();
  final TextEditingController _logoBase64Controller = TextEditingController(); // Optional Base64 image data

  // Spacing / formatting knobs (can be adjusted via sliders in upcoming UI card)
  double _headerGap = 1;     // feed lines after header block
  double _lineSpacing = 0;   // extra feeds between detail lines
  double _itemSpacing = 0;   // extra feeds between item lines

  // Future: cache of parsed items / prebuilt commands if optimization needed.
  // For now we rebuild on each print.
  // ===============================================================================

  // ================= POS Style Receipt Fields (Specific Layout) ==================
  String _headerTitle = "Wendy's";
  int _headerFontSize = 32; // placeholder (SDK may later support styles)
  int _headerSpacingLines = 1;
  String? _logoBase64; // optional centered image
  int _imageWidthPx = 200; // placeholder for future image scaling
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
  String _itemPrice = '5.00';
  String _itemRepeat = '3';
  // Estimated characters-per-line for current printer font (adjustable by user)
  int _posCharsPerLine = 48; // 80mm common: 48 (Font A) or 64 (Font B); 58mm often 32 or 42
  // ===============================================================================

  @override
  void initState() {
    super.initState();
    // Defer Bluetooth permission requests to Bluetooth actions.
    // Seed some default demo content for structured receipt fields.
    _headerController.text = 'My Shop\\n123 Sample Street';
    _detailsController.text = 'Order: 12345\\nDate: 2025-01-01 12:34';
    _itemsController.text = '2x Coffee @3.50\\n1x Bagel @2.25';
    _footerController.text = 'Thank you for visiting!';

    // POS style controller
    _headerControllerPos = TextEditingController(text: _headerTitle);
  }

  @override
  void dispose() {
    _headerController.dispose();
    _detailsController.dispose();
    _itemsController.dispose();
    _footerController.dispose();
    _logoBase64Controller.dispose();
    _headerControllerPos.dispose();
    super.dispose();
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
  }

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
    // Layout: qty (3) name (left) price (right) within paper width.
    qty = qty.trim();
    name = name.trim();
    price = price.trim();
    const qtyWidth = 4; // e.g. '999x'
    const priceWidth = 8; // enough for large price
    final qtyStr = qty.length > 3 ? qty.substring(0, 3) : qty;
    final qtyField = qtyStr.padRight(qtyWidth);
    // Remaining width for name = total - qtyWidth - priceWidth
    final nameWidth = _posCharsPerLine - qtyWidth - priceWidth;
    String nameTrunc = name;
    if (nameTrunc.length > nameWidth) nameTrunc = nameTrunc.substring(0, nameWidth);
    final priceField = price.padLeft(priceWidth);
    return qtyField + nameTrunc.padRight(nameWidth) + priceField;
  }
  // ==========================================================================

  List<EpsonPrintCommand> _buildPosReceiptCommands() {
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

    String title = _headerControllerPos.text.trim().isNotEmpty ? _headerControllerPos.text.trim() : _headerTitle.trim();
    if (title.isNotEmpty) {
      cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'data': _center(title) + '\n' }));
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

    // Future style/image usage placeholder (avoid unused field warnings until implemented)
    // ignore: unused_local_variable
    final _stylePlaceholder = {
      'fontSize': _headerFontSize,
      'logoProvided': _logoBase64 != null,
      'imageWidth': _imageWidthPx,
      'imageSpacing': _imageSpacingLines,
    };

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
    final repeatCount = int.tryParse(_itemRepeat) ?? 1;
    for (int i = 0; i < repeatCount; i++) {
      cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'data': _qtyNamePrice(_itemQuantity, _itemName, _itemPrice) + '\n' }));
    }

    // Second horizontal line
    cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'data': _horizontalLine() + '\n' }));

    if (_footer.trim().isNotEmpty) {
      cmds.add(EpsonPrintCommand(type: EpsonCommandType.text, parameters: { 'data': _footer.trim() + '\n' }));
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
                      ],
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
                        ElevatedButton(onPressed: _discoverPrinters, child: const Text('Discover LAN')),
                        ElevatedButton(onPressed: _discoverBluetoothPrinters, child: const Text('Discover Bluetooth')),
                        ElevatedButton(onPressed: _discoverUsbPrinters, child: const Text('Discover USB')),
                        // Hide Pair button on Android
                        if (!Platform.isAndroid)
                          ElevatedButton(onPressed: _pairBluetooth, child: const Text('Pair Bluetooth')),
                        ElevatedButton(onPressed: _selectedPrinter != null && !_isConnected ? _connectToPrinter : null, child: const Text('Connect')),
                        ElevatedButton(onPressed: _isConnected ? _disconnectFromPrinter : null, child: const Text('Disconnect')),
                        ElevatedButton(onPressed: _isConnected ? _printReceipt : null, child: const Text('Print Test Receipt')),
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
