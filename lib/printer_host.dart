/// The seams the service layer expects a host application to fill in.
///
/// [NativeReceiptService] and [NativeLabelService] need four things from
/// whatever app embeds them: the set of configured printers, who the store is,
/// somewhere to surface user-facing failures, and a receipt logo. Rather than
/// reach for application singletons, each is a small injectable type defined
/// here, so the service layer stays usable from a test, a demo harness, or a
/// real POS without modification.
library;

/// A printer the operator has configured and saved.
///
/// [settings] is deliberately an untyped bag: each brand needs different
/// configuration (Star wants `paperWidthMm`, Epson wants `paperWidth`, Zebra
/// wants `printWidthInDots`/`labelLengthInDots`/`dpi`), the discovery wizard
/// writes whatever it detected, and the service layer reads back only the keys
/// relevant to that printer's brand. Typing it per-brand would mean three
/// parallel hierarchies for a map that is written once and read once.
class SavedPrinter {
  String id; // Unique identifier
  String userGivenName; // "Front Counter", "Kitchen", etc.
  String brand; // "epson", "star", "zebra"
  String interface; // "tcp", "bluetooth", etc.
  String address; // Connection string
  String model; // Detected model
  bool isReceipt;
  bool isLabel;
  Map<String, dynamic> settings; // Paper width, print settings, etc.
  bool isDefault; // Default for receipt/label jobs
  bool isCashDrawerConnected; // This printer controls cash drawer
  DateTime lastConnected;
  bool isActive;

  SavedPrinter({
    required this.id,
    required this.userGivenName,
    required this.brand,
    required this.interface,
    required this.address,
    required this.model,
    required this.isReceipt,
    required this.isLabel,
    required this.settings,
    this.isDefault = false,
    this.isCashDrawerConnected = false,
    DateTime? lastConnected,
    this.isActive = true,
  }) : lastConnected = lastConnected ?? DateTime.now();

  /// Convert SavedPrinter to JSON for persistence
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userGivenName': userGivenName,
      'brand': brand,
      'interface': interface,
      'address': address,
      'model': model,
      'isReceipt': isReceipt,
      'isLabel': isLabel,
      'settings': settings,
      'isDefault': isDefault,
      'isCashDrawerConnected': isCashDrawerConnected,
      'lastConnected': lastConnected.millisecondsSinceEpoch,
      'isActive': isActive,
    };
  }

  /// Create SavedPrinter from JSON for persistence
  factory SavedPrinter.fromJson(Map<String, dynamic> json) {
    return SavedPrinter(
      id: json['id'] as String,
      userGivenName: json['userGivenName'] as String,
      brand: json['brand'] as String,
      interface: json['interface'] as String,
      address: json['address'] as String,
      model: json['model'] as String,
      isReceipt: json['isReceipt'] as bool,
      isLabel: json['isLabel'] as bool,
      settings: Map<String, dynamic>.from(json['settings'] as Map),
      isDefault: json['isDefault'] as bool? ?? false,
      isCashDrawerConnected: json['isCashDrawerConnected'] as bool? ?? false,
      lastConnected:
          DateTime.fromMillisecondsSinceEpoch(json['lastConnected'] as int),
      isActive: json['isActive'] as bool? ?? true,
    );
  }
}

/// The set of configured printers the service layer prints through.
///
/// Held in memory. A host app that persists printers across launches should
/// subclass this and override [savedPrinters], or seed it on startup and
/// serialize via [SavedPrinter.toJson] — the service layer only ever reads.
///
/// "Default" is tracked per role rather than globally: a store commonly runs a
/// receipt printer at the counter and a label printer in the back, so one
/// printer being the default for labels says nothing about receipts.
class PrinterRegistry {
  static PrinterRegistry instance = PrinterRegistry();

  final List<SavedPrinter> _printers = [];

  /// Every configured printer, in insertion order.
  List<SavedPrinter> get savedPrinters => List.unmodifiable(_printers);

  /// Adds [printer], replacing any existing entry with the same id.
  ///
  /// Setting a printer as default for a role clears that flag on the previous
  /// default for the same role, so the "default" invariant holds per role.
  void addPrinter(SavedPrinter printer) {
    _printers.removeWhere((p) => p.id == printer.id);
    if (printer.isDefault) {
      for (final existing in _printers) {
        final sharesRole = (printer.isReceipt && existing.isReceipt) ||
            (printer.isLabel && existing.isLabel);
        if (sharesRole) existing.isDefault = false;
      }
    }
    _printers.add(printer);
  }

  /// Removes the printer with [id]. Returns whether one was removed.
  bool removePrinter(String id) {
    final before = _printers.length;
    _printers.removeWhere((p) => p.id == id);
    return _printers.length != before;
  }

  /// Forgets every configured printer.
  void clear() => _printers.clear();

  /// The active receipt printer marked default, or null.
  SavedPrinter? getDefaultReceiptPrinter() => _defaultFor((p) => p.isReceipt);

  /// The active label printer marked default, or null.
  SavedPrinter? getDefaultLabelPrinter() => _defaultFor((p) => p.isLabel);

  SavedPrinter? _defaultFor(bool Function(SavedPrinter) hasRole) {
    for (final printer in _printers) {
      if (printer.isActive && printer.isDefault && hasRole(printer)) {
        return printer;
      }
    }
    return null;
  }
}

/// Who the store is, as printed on a receipt header and footer.
///
/// Receipts carry both an organization identity (the brand, shared across
/// locations) and a location identity (this specific storefront's name and
/// address). Header text prefers the organization name and falls back to the
/// location name, matching what customers expect to see.
class StoreIdentity {
  final String? organizationName;
  final String? organizationFooter;
  final String? locationName;
  final String? locationAddress;

  const StoreIdentity({
    this.organizationName,
    this.organizationFooter,
    this.locationName,
    this.locationAddress,
  });

  /// The identity used when the host app supplies none.
  static StoreIdentity current = const StoreIdentity();

  /// Name for the receipt header, falling back through the identities.
  String get displayName {
    final org = organizationName;
    if (org != null && org.isNotEmpty) return org;
    final location = locationName;
    if (location != null && location.isNotEmpty) return location;
    return 'Store';
  }

  /// Address for the receipt header; empty when unknown.
  String get displayAddress => locationAddress ?? '';
}

/// Where the service layer reports user-facing print failures.
///
/// A printing library has no business showing a toast or a snackbar — it does
/// not know what UI framework is above it, and a print triggered from a
/// background job has no UI at all. Failures are therefore handed to a
/// callback the host app installs; unset, they are dropped (the services still
/// log via `debugPrint` and return `false`).
class PrinterFeedback {
  /// Called with an already-localized, user-facing failure message.
  static void Function(String message)? onMessage;

  static void report(String message) => onMessage?.call(message);
}

/// Supplies the logo printed at the top of a receipt, as base64 PNG/JPEG.
///
/// Fetching and caching is left to the host app: it already knows where its
/// branding lives and how to cache it, and a printing library that reaches out
/// to the network on your behalf is a worse library. Unset, receipts print
/// without a logo.
///
/// [url] is the per-transaction logo override when a receipt carries one,
/// otherwise null to mean "the current organization's logo".
class PrinterLogoSource {
  static Future<String?> Function(String? url)? resolve;

  static Future<String?> get({String? url}) async {
    final resolver = resolve;
    if (resolver == null) return null;
    return resolver(url);
  }
}
