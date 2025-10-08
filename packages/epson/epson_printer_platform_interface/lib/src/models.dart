/// Data models for Epson printer operations.

/// Printer status information
class EpsonPrinterStatus {
  final bool isOnline;
  final String status;
  final String? errorMessage;
  final EpsonStatusPaper paperStatus;
  final EpsonStatusDrawer drawerStatus;
  final EpsonBatteryLevel batteryLevel;
  final bool isCoverOpen;
  final EpsonPrinterError errorCode;

  const EpsonPrinterStatus({
    required this.isOnline,
    required this.status,
    this.errorMessage,
    required this.paperStatus,
    required this.drawerStatus,
    required this.batteryLevel,
    required this.isCoverOpen,
    required this.errorCode,
  });

  factory EpsonPrinterStatus.fromMap(Map<String, dynamic> map) {
    return EpsonPrinterStatus(
      isOnline: map['isOnline'] ?? false,
      status: map['status'] ?? 'unknown',
      errorMessage: map['errorMessage'],
      paperStatus: EpsonStatusPaper.values[map['paperStatus'] ?? 0],
      drawerStatus: EpsonStatusDrawer.values[map['drawerStatus'] ?? 0],
      batteryLevel: EpsonBatteryLevel.values[map['batteryLevel'] ?? 0],
      isCoverOpen: map['isCoverOpen'] ?? false,
      errorCode: EpsonPrinterError.values[map['errorCode'] ?? 0],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'isOnline': isOnline,
      'status': status,
      'errorMessage': errorMessage,
      'paperStatus': paperStatus.index,
      'drawerStatus': drawerStatus.index,
      'batteryLevel': batteryLevel.index,
      'isCoverOpen': isCoverOpen,
      'errorCode': errorCode.index,
    };
  }
}

/// Connection settings for Epson printers
class EpsonConnectionSettings {
  final EpsonPortType portType;
  final String identifier;
  final int timeout;

  // Note: printerSeries is not needed for connection, only for initialization
  final EpsonPrinterSeries? printerSeries;
  final EpsonModelLang? modelLang;

  const EpsonConnectionSettings({
    required this.portType,
    required this.identifier,
    this.timeout = 15000,
    this.printerSeries,
    this.modelLang = EpsonModelLang.ank,
  });

  /// Generates the target string for the Epson connect API
  String get targetString {
    // If identifier already includes a known prefix, use it as-is to avoid double-prefixing
    final upper = identifier.toUpperCase();
    final hasScheme = upper.startsWith('TCP:') ||
        upper.startsWith('TCPS:') ||
        upper.startsWith('BT:') ||
        upper.startsWith('BLE:') ||
        upper.startsWith('USB:');
    if (hasScheme) {
      return identifier;
    }

    final prefix = switch (portType) {
      EpsonPortType.tcp => 'TCP',
      EpsonPortType.bluetooth => 'BT',
      EpsonPortType.usb => 'USB',
      EpsonPortType.bluetoothLe => 'BLE',
      EpsonPortType.all => 'TCP',
    };
    return '$prefix:$identifier';
  }

  Map<String, dynamic> toMap() {
    return {
      'portType': portType.index,
      'identifier': identifier,
      'timeout': timeout,
      'targetString': targetString,
      'printerSeries': printerSeries?.index,
      'modelLang': modelLang?.index,
    };
  }

  factory EpsonConnectionSettings.fromMap(Map<String, dynamic> map) {
    return EpsonConnectionSettings(
      portType: EpsonPortType.values[map['portType'] ?? 0],
      identifier: map['identifier'] ?? '',
      timeout: map['timeout'] ?? 15000,
      printerSeries: map['printerSeries'] != null 
          ? EpsonPrinterSeries.values[map['printerSeries']] 
          : null,
      modelLang: map['modelLang'] != null 
          ? EpsonModelLang.values[map['modelLang']] 
          : null,
    );
  }
}

/// Print job configuration
class EpsonPrintJob {
  final List<EpsonPrintCommand> commands;
  final Map<String, dynamic>? settings;

  const EpsonPrintJob({
    required this.commands,
    this.settings,
  });

  Map<String, dynamic> toMap() {
    return {
      'commands': commands.map((cmd) => cmd.toMap()).toList(),
      'settings': settings,
    };
  }
}

/// Individual print command
class EpsonPrintCommand {
  final EpsonCommandType type;
  final Map<String, dynamic> parameters;

  const EpsonPrintCommand({
    required this.type,
    required this.parameters,
  });

  Map<String, dynamic> toMap() {
    return {
      'type': type.name,
      'parameters': parameters,
    };
  }

  factory EpsonPrintCommand.fromMap(Map<String, dynamic> map) {
    return EpsonPrintCommand(
      type: EpsonCommandType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => EpsonCommandType.text,
      ),
      parameters: Map<String, dynamic>.from(map['parameters'] ?? {}),
    );
  }
}

/// Text styling options
class EpsonTextStyle {
  final EpsonFont font;
  final EpsonAlign alignment;
  final EpsonLang language;
  final bool bold;
  final bool underline;
  final bool italic;
  final int size;
  final EpsonColor color;

  const EpsonTextStyle({
    this.font = EpsonFont.fontA,
    this.alignment = EpsonAlign.left,
    this.language = EpsonLang.en,
    this.bold = false,
    this.underline = false,
    this.italic = false,
    this.size = 1,
    this.color = EpsonColor.none,
  });

  Map<String, dynamic> toMap() {
    return {
      'font': font.index,
      'alignment': alignment.index,
      'language': language.index,
      'bold': bold,
      'underline': underline,
      'italic': italic,
      'size': size,
      'color': color.index,
    };
  }
}

/// Barcode configuration
class EpsonBarcodeConfig {
  final EpsonBarcode type;
  final String data;
  final EpsonHri hri;
  final int height;
  final int width;

  const EpsonBarcodeConfig({
    required this.type,
    required this.data,
    this.hri = EpsonHri.none,
    this.height = 162,
    this.width = 3,
  });

  Map<String, dynamic> toMap() {
    return {
      'type': type.index,
      'data': data,
      'hri': hri.index,
      'height': height,
      'width': width,
    };
  }
}

/// QR Code configuration
class EpsonQRCodeConfig {
  final EpsonSymbol type;
  final String data;
  final EpsonLevel level;
  final int size;

  const EpsonQRCodeConfig({
    required this.data,
    this.type = EpsonSymbol.qrcodeModel2,
    this.level = EpsonLevel.levelM,
    this.size = 3,
  });

  Map<String, dynamic> toMap() {
    return {
      'type': type.index,
      'data': data,
      'level': level.index,
      'size': size,
    };
  }
}

/// Image printing configuration
class EpsonImageConfig {
  final String imagePath;
  final EpsonMode mode;
  final EpsonHalftone halftone;
  final EpsonCompress compress;
  final int brightness;

  const EpsonImageConfig({
    required this.imagePath,
    this.mode = EpsonMode.mono,
    this.halftone = EpsonHalftone.dither,
    this.compress = EpsonCompress.auto,
    this.brightness = 1,
  });

  Map<String, dynamic> toMap() {
    return {
      'imagePath': imagePath,
      'mode': mode.index,
      'halftone': halftone.index,
      'compress': compress.index,
      'brightness': brightness,
    };
  }
}

/// Discovery result for printer detection
class EpsonPrinterDiscoveryResult {
  final String deviceName;
  final String ipAddress;
  final String macAddress;
  final EpsonDeviceType deviceType;
  final EpsonPortType portType;

  const EpsonPrinterDiscoveryResult({
    required this.deviceName,
    required this.ipAddress,
    required this.macAddress,
    required this.deviceType,
    required this.portType,
  });

  factory EpsonPrinterDiscoveryResult.fromMap(Map<String, dynamic> map) {
    return EpsonPrinterDiscoveryResult(
      deviceName: map['deviceName'] ?? '',
      ipAddress: map['ipAddress'] ?? '',
      macAddress: map['macAddress'] ?? '',
      deviceType: EpsonDeviceType.values[map['deviceType'] ?? 0],
      portType: EpsonPortType.values[map['portType'] ?? 0],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'deviceName': deviceName,
      'ipAddress': ipAddress,
      'macAddress': macAddress,
      'deviceType': deviceType.index,
      'portType': portType.index,
    };
  }
}

// MARK: - Enums

/// Command types for print operations
enum EpsonCommandType {
  text,
  image,
  barcode,
  qrCode,
  cut,
  feed,
  pulse,
  beep,
  layout,
}

/// Port types supported by Epson printers
enum EpsonPortType {
  all,
  tcp,
  bluetooth,
  usb,
  bluetoothLe,
}

/// Epson printer series
enum EpsonPrinterSeries {
  tmM10,
  tmM30,
  tmP20,
  tmP60,
  tmP60II,
  tmP80,
  tmT20,
  tmT60,
  tmT70,
  tmT81,
  tmT82,
  tmT83,
  tmT88,
  tmT90,
  tmT90KP,
  tmU220,
  tmU330,
  tmL90,
  tmH6000,
  tmT83III,
  tmT100,
  tmM30II,
  ts100,
  tmM50,
  tmT88VII,
  tmL90LFC,
  tmL100,
  tmP20II,
  tmP80II,
  tmM30III,
  tmM50II,
  tmM55,
  tmU220II,
  sbH50,
}

/// Model language support
enum EpsonModelLang {
  ank,
  japanese,
  chinese,
  taiwan,
  korean,
  thai,
  southasia,
}

/// Paper status
enum EpsonStatusPaper {
  ok,
  nearEnd,
  empty,
}

/// Panel switch status
enum EpsonPanelSwitch {
  off,
  on,
}

/// Drawer status
enum EpsonStatusDrawer {
  high,
  low,
}

/// Printer error types
enum EpsonPrinterError {
  noError,
  mechanicalError,
  autocutterError,
  unrecoverableError,
  autorecoverableError,
}

/// Auto-recover error types
enum EpsonAutoRecoverError {
  headOverheat,
  motorOverheat,
  batteryOverheat,
  wrongPaper,
  coverOpen,
}

/// Battery level
enum EpsonBatteryLevel {
  level0,
  level1,
  level2,
  level3,
  level4,
  level5,
  level6,
}

/// Device types
enum EpsonDeviceType {
  all,
  printer,
  hybridPrinter,
  display,
  keyboard,
  scanner,
  serial,
  cchanger,
  posKeyboard,
  cat,
  msr,
  otherPeripheral,
  gfe,
}

/// Text alignment
enum EpsonAlign {
  left,
  center,
  right,
}

/// Language settings
enum EpsonLang {
  en,
  ja,
  zhCn,
  zhTw,
  ko,
  th,
  vi,
  multi,
}

/// Font types
enum EpsonFont {
  fontA,
  fontB,
  fontC,
  fontD,
  fontE,
}

/// Color options
enum EpsonColor {
  none,
  color1,
  color2,
  color3,
  color4,
}

/// Print modes
enum EpsonMode {
  mono,
  gray16,
  monoHighDensity,
}

/// Halftone processing
enum EpsonHalftone {
  dither,
  errorDiffusion,
  threshold,
}

/// Compression methods
enum EpsonCompress {
  deflate,
  none,
  auto,
}

/// Barcode types
enum EpsonBarcode {
  upcA,
  upcE,
  ean13,
  jan13,
  ean8,
  jan8,
  code39,
  itf,
  codabar,
  code93,
  code128,
  gs1128,
  gs1DatabarOmnidirectional,
  gs1DatabarTruncated,
  gs1DatabarLimited,
  gs1DatabarExpanded,
  code128Auto,
}

/// Human readable interpretation for barcodes
enum EpsonHri {
  none,
  above,
  below,
  both,
}

/// Symbol types (QR codes, etc.)
enum EpsonSymbol {
  pdf417Standard,
  pdf417Truncated,
  qrcodeModel1,
  qrcodeModel2,
  qrcodeMicro,
  maxicodeMode2,
  maxicodeMode3,
  maxicodeMode4,
  maxicodeMode5,
  maxicodeMode6,
  gs1DatabarStacked,
  gs1DatabarStackedOmnidirectional,
  gs1DatabarExpandedStacked,
  azteccodeFullrange,
  azteccodeCompact,
  datamatrixSquare,
  datamatrixRectangle8,
  datamatrixRectangle12,
  datamatrixRectangle16,
}

/// Error correction levels
enum EpsonLevel {
  level0,
  level1,
  level2,
  level3,
  level4,
  level5,
  level6,
  level7,
  level8,
  levelL,
  levelM,
  levelQ,
  levelH,
}

/// Line styles
enum EpsonLine {
  thin,
  medium,
  thick,
  thinDouble,
  mediumDouble,
  thickDouble,
}

/// Print direction
enum EpsonDirection {
  leftToRight,
  bottomToTop,
  rightToLeft,
  topToBottom,
}

/// Cut types
enum EpsonCut {
  cutFeed,
  cutNoFeed,
  cutReserve,
  fullCutFeed,
  fullCutNoFeed,
  fullCutReserve,
}

/// Drawer pin configuration
enum EpsonDrawer {
  pin2,
  pin5,
}

/// Status events
enum EpsonStatusEvent {
  online,
  offline,
  powerOff,
  coverClose,
  coverOpen,
  paperOk,
  paperNearEnd,
  paperEmpty,
  drawerHigh,
  drawerLow,
  batteryEnough,
  batteryEmpty,
  insertionWaitSlip,
  insertionWaitValidation,
  insertionWaitMicr,
  insertionWaitNone,
  removalWaitPaper,
  removalWaitNone,
  slipPaperOk,
  slipPaperEmpty,
  autoRecoverError,
  autoRecoverOk,
  unrecoverableError,
  removalDetectPaper,
  removalDetectPaperNone,
  removalDetectUnknown,
}

/// Connection events
enum EpsonConnectionEvent {
  reconnecting,
  reconnect,
  disconnect,
}

/// Error status codes
enum EpsonErrorStatus {
  success,
  errParam,
  errConnect,
  errTimeout,
  errMemory,
  errIllegal,
  errProcessing,
  errNotFound,
  errInUse,
  errTypeInvalid,
  errDisconnect,
  errAlreadyOpened,
  errAlreadyUsed,
  errBoxCountOver,
  errBoxClientOver,
  errUnsupported,
  errDeviceBusy,
  errRecoveryFailure,
  errFailure,
}

/// Callback codes for async operations
enum EpsonCallbackCode {
  success,
  errTimeout,
  errNotFound,
  errAutorecover,
  errCoverOpen,
  errCutter,
  errMechanical,
  errEmpty,
  errUnrecoverable,
  errSystem,
  errPort,
  errInvalidWindow,
  errJobNotFound,
  printing,
  errSpooler,
  errBatteryLow,
  errTooManyRequests,
  errRequestEntityTooLarge,
  canceled,
  errNoMicrData,
  errIllegalLength,
  errNoMagneticData,
  errRecognition,
  errRead,
  errNoiseDetected,
  errPaperJam,
  errPaperPulledOut,
  errCancelFailed,
  errPaperType,
  errWaitInsertion,
  errIllegal,
  errInserted,
  errWaitRemoval,
  errDeviceBusy,
  errGetJsonSize,
  errInUse,
  errConnect,
  errDisconnect,
  errDifferentModel,
  errDifferentVersion,
  errMemory,
  errProcessing,
  errDataCorrupted,
  errParam,
  retry,
  errRecoveryFailure,
  errJsonFormat,
  noPassword,
  errInvalidPassword,
  errInvalidFirmVersion,
  errSslCertification,
  errFailure,
}