/// Star Print Commands
/// 
/// This file defines a command-based abstraction for Star printer operations.
/// Commands are built in Dart and executed by native Swift/Kotlin code,
/// similar to how Epson commands work.
/// 
/// This approach allows receipt/label layouts to be defined entirely in Dart,
/// while native code handles model-specific rendering (graphics-only printers,
/// width calculations, DPI adjustments, etc.)

/// Alignment options for text and images
enum StarAlignment {
  left,
  center,
  right,
}

/// Barcode symbology types supported by Star printers
enum StarBarcodeSymbology {
  code128,
  code39,
  jan8,
  jan13,
  upcA,
  upcE,
  itf,
  codabar,
  qrCode,
}

/// Cut types for paper cutting
enum StarCutType {
  partial,
  full,
  tearOff,
}

/// Command types that map to StarXpand builder methods
enum StarCommandType {
  /// Single text block with optional styling
  /// Maps to: actionPrintText() with style modifiers
  text,
  
  /// Two text elements on the same line (left and right aligned)
  /// Maps to: calculated spacing or column-based layout
  textLeftRight,
  
  /// Multi-column text layout (e.g., qty | name | price)
  /// Maps to: calculated spacing based on column widths
  textColumns,
  
  /// Horizontal ruled line
  /// Maps to: actionPrintRuledLine() or dashes for graphics-only
  line,
  
  /// Line feed (vertical spacing)
  /// Maps to: actionFeedLine()
  feed,
  
  /// Print an image
  /// Maps to: actionPrintImage()
  image,
  
  /// Print a barcode
  /// Maps to: actionPrintBarcode()
  barcode,
  
  /// Print a QR code  
  /// Maps to: actionPrintQRCode()
  qrCode,
  
  /// Cut the paper
  /// Maps to: actionCut()
  cut,
  
  /// Open the cash drawer
  /// Maps to: DrawerBuilder.actionOpen()
  openDrawer,
}

/// A single print command for Star printers.
/// 
/// Each command represents one operation that the native code will execute.
/// The native layer handles model-specific adaptations (graphics-only rendering,
/// width calculations, DPI scaling, etc.)
class StarPrintCommand {
  final StarCommandType type;
  final Map<String, dynamic> parameters;

  const StarPrintCommand({
    required this.type,
    this.parameters = const {},
  });

  /// Convert to Map for passing through platform channel
  Map<String, dynamic> toMap() {
    return {
      'type': type.name,
      'parameters': parameters,
    };
  }

  // ============================================================
  // FACTORY CONSTRUCTORS - Convenient builders for each command
  // ============================================================

  /// Print a single text block
  /// 
  /// Example:
  /// ```dart
  /// StarPrintCommand.text('Hello World\n', align: StarAlignment.center, bold: true)
  /// ```
  factory StarPrintCommand.text(
    String text, {
    StarAlignment align = StarAlignment.left,
    bool bold = false,
    bool underline = false,
    bool invert = false,
    int magnificationWidth = 1,
    int magnificationHeight = 1,
  }) {
    return StarPrintCommand(
      type: StarCommandType.text,
      parameters: {
        'text': text,
        'align': align.name,
        'bold': bold,
        'underline': underline,
        'invert': invert,
        'magnificationWidth': magnificationWidth,
        'magnificationHeight': magnificationHeight,
      },
    );
  }

  /// Print two text elements on the same line (left and right aligned)
  /// 
  /// Example:
  /// ```dart
  /// StarPrintCommand.textLeftRight('Date: 01/12/2026', 'Cashier: John')
  /// ```
  factory StarPrintCommand.textLeftRight(
    String leftText,
    String rightText, {
    bool bold = false,
  }) {
    return StarPrintCommand(
      type: StarCommandType.textLeftRight,
      parameters: {
        'left': leftText,
        'right': rightText,
        'bold': bold,
      },
    );
  }

  /// Print multiple columns on a single line
  /// 
  /// Each column has text and a relative weight for width calculation.
  /// Native code will calculate actual character widths based on paper size.
  /// 
  /// Example:
  /// ```dart
  /// StarPrintCommand.textColumns([
  ///   StarColumn(text: '2x', weight: 1, align: StarAlignment.left),
  ///   StarColumn(text: 'Widget', weight: 4, align: StarAlignment.left),
  ///   StarColumn(text: '\$19.99', weight: 2, align: StarAlignment.right),
  /// ])
  /// ```
  factory StarPrintCommand.textColumns(
    List<StarColumn> columns, {
    bool bold = false,
  }) {
    return StarPrintCommand(
      type: StarCommandType.textColumns,
      parameters: {
        'columns': columns.map((c) => c.toMap()).toList(),
        'bold': bold,
      },
    );
  }

  /// Print a horizontal line/rule
  /// 
  /// Example:
  /// ```dart
  /// StarPrintCommand.line()
  /// StarPrintCommand.line(dashed: true)
  /// ```
  factory StarPrintCommand.line({
    bool dashed = false,
  }) {
    return StarPrintCommand(
      type: StarCommandType.line,
      parameters: {
        'dashed': dashed,
      },
    );
  }

  /// Feed (advance) paper by specified number of lines
  /// 
  /// Example:
  /// ```dart
  /// StarPrintCommand.feed(2)
  /// ```
  factory StarPrintCommand.feed(int lines) {
    return StarPrintCommand(
      type: StarCommandType.feed,
      parameters: {
        'lines': lines,
      },
    );
  }

  /// Print an image from base64 data
  /// 
  /// Example:
  /// ```dart
  /// StarPrintCommand.image(logoBase64, width: 200, align: StarAlignment.center)
  /// ```
  factory StarPrintCommand.image(
    String base64, {
    int width = 200,
    StarAlignment align = StarAlignment.center,
  }) {
    return StarPrintCommand(
      type: StarCommandType.image,
      parameters: {
        'base64': base64,
        'width': width,
        'align': align.name,
      },
    );
  }

  /// Print a barcode
  /// 
  /// Example:
  /// ```dart
  /// StarPrintCommand.barcode('1234567890', symbology: StarBarcodeSymbology.code128)
  /// ```
  factory StarPrintCommand.barcode(
    String content, {
    StarBarcodeSymbology symbology = StarBarcodeSymbology.code128,
    int height = 50,
    bool printHRI = true,
    int barDots = 3,
    StarAlignment align = StarAlignment.center,
  }) {
    return StarPrintCommand(
      type: StarCommandType.barcode,
      parameters: {
        'content': content,
        'symbology': symbology.name,
        'height': height,
        'printHRI': printHRI,
        'barDots': barDots,
        'align': align.name,
      },
    );
  }

  /// Print a QR code
  /// 
  /// Example:
  /// ```dart
  /// StarPrintCommand.qrCode('https://example.com', cellSize: 8)
  /// ```
  factory StarPrintCommand.qrCode(
    String content, {
    int cellSize = 8,
    String level = 'L', // L, M, Q, H
    StarAlignment align = StarAlignment.center,
  }) {
    return StarPrintCommand(
      type: StarCommandType.qrCode,
      parameters: {
        'content': content,
        'cellSize': cellSize,
        'level': level,
        'align': align.name,
      },
    );
  }

  /// Cut the paper
  /// 
  /// Example:
  /// ```dart
  /// StarPrintCommand.cut(StarCutType.partial)
  /// ```
  factory StarPrintCommand.cut([StarCutType cutType = StarCutType.partial]) {
    return StarPrintCommand(
      type: StarCommandType.cut,
      parameters: {
        'cutType': cutType.name,
      },
    );
  }

  /// Open the cash drawer
  /// 
  /// Example:
  /// ```dart
  /// StarPrintCommand.openDrawer()
  /// ```
  factory StarPrintCommand.openDrawer() {
    return const StarPrintCommand(
      type: StarCommandType.openDrawer,
    );
  }
}

/// Represents a column in a multi-column text layout
class StarColumn {
  /// The text content for this column
  final String text;
  
  /// Relative weight for width calculation (e.g., weight 2 gets twice the space of weight 1)
  final int weight;
  
  /// Text alignment within this column
  final StarAlignment align;

  const StarColumn({
    required this.text,
    this.weight = 1,
    this.align = StarAlignment.left,
  });

  Map<String, dynamic> toMap() {
    return {
      'text': text,
      'weight': weight,
      'align': align.name,
    };
  }
}

/// Extension to convert a list of commands to a format suitable for platform channels
extension StarPrintCommandListExtension on List<StarPrintCommand> {
  List<Map<String, dynamic>> toMapList() {
    return map((cmd) => cmd.toMap()).toList();
  }
}
