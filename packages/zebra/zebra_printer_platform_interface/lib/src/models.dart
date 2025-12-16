/// Data models for zebra printer platform interface

/// Represents a single line item on a receipt
class ReceiptLineItem {
  final int quantity;
  final String itemName;
  final double unitPrice;
  final double? totalPrice; // Calculated field, can be null if auto-calculated

  const ReceiptLineItem({
    required this.quantity,
    required this.itemName,
    required this.unitPrice,
    this.totalPrice,
  });

  /// Calculate the total price for this line item
  double get calculatedTotal => totalPrice ?? (quantity * unitPrice);

  factory ReceiptLineItem.fromJson(Map<String, dynamic> json) {
    return ReceiptLineItem(
      quantity: json['quantity'] ?? 0,
      itemName: json['itemName'] ?? '',
      unitPrice: (json['unitPrice'] ?? 0.0).toDouble(),
      totalPrice: json['totalPrice']?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'quantity': quantity,
      'itemName': itemName,
      'unitPrice': unitPrice,
      if (totalPrice != null) 'totalPrice': totalPrice,
    };
  }

  @override
  String toString() {
    return 'ReceiptLineItem($quantity x $itemName @ \$${unitPrice.toStringAsFixed(2)} = \$${calculatedTotal.toStringAsFixed(2)})';
  }
}

/// Data model for label content
class LabelData {
  final String productName;
  final String colorSize;
  final String scancode;
  final String price;
  final Map<String, dynamic>? customFields; // For future extensibility

  const LabelData({
    required this.productName,
    required this.colorSize,
    required this.scancode,
    required this.price,
    this.customFields,
  });

  factory LabelData.fromJson(Map<String, dynamic> json) {
    return LabelData(
      productName: json['productName'] ?? '',
      colorSize: json['colorSize'] ?? '',
      scancode: json['scancode'] ?? '',
      price: json['price'] ?? '',
      customFields: json['customFields']?.cast<String, dynamic>(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'productName': productName,
      'colorSize': colorSize,
      'scancode': scancode,
      'price': price,
      if (customFields != null) 'customFields': customFields,
    };
  }

  @override
  String toString() {
    return 'LabelData(product: $productName, size: $colorSize, code: $scancode, price: $price)';
  }
}

/// Data model for receipt content
class ReceiptData {
  final String storeName;
  final String storeAddress;
  final String? storePhone;
  final String? receiptNumber;
  final DateTime? transactionDate;
  final String? cashierName;
  final String? laneNumber;
  final List<ReceiptLineItem> items;
  final double? subtotal;
  final double? tax;
  final double? total;
  final String? thankYouMessage;
  final Map<String, dynamic>? customFields; // For future extensibility

  const ReceiptData({
    required this.storeName,
    required this.storeAddress,
    this.storePhone,
    this.receiptNumber,
    this.transactionDate,
    this.cashierName,
    this.laneNumber,
    this.items = const [],
    this.subtotal,
    this.tax,
    this.total,
    this.thankYouMessage,
    this.customFields,
  });

  /// Calculate subtotal from line items if not provided
  double get calculatedSubtotal => subtotal ?? items.fold(0.0, (sum, item) => sum + item.calculatedTotal);
  
  /// Calculate total (subtotal + tax) if not provided
  double get calculatedTotal => total ?? (calculatedSubtotal + (tax ?? 0.0));

  factory ReceiptData.fromJson(Map<String, dynamic> json) {
    return ReceiptData(
      storeName: json['storeName'] ?? '',
      storeAddress: json['storeAddress'] ?? '',
      storePhone: json['storePhone'],
      receiptNumber: json['receiptNumber'],
      transactionDate: json['transactionDate'] != null 
          ? DateTime.tryParse(json['transactionDate'])
          : null,
      cashierName: json['cashierName'],
      laneNumber: json['laneNumber'],
      items: (json['items'] as List<dynamic>?)
          ?.map((item) => ReceiptLineItem.fromJson(item))
          .toList() ?? [],
      subtotal: json['subtotal']?.toDouble(),
      tax: json['tax']?.toDouble(),
      total: json['total']?.toDouble(),
      thankYouMessage: json['thankYouMessage'],
      customFields: json['customFields']?.cast<String, dynamic>(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'storeName': storeName,
      'storeAddress': storeAddress,
      if (storePhone != null) 'storePhone': storePhone,
      if (receiptNumber != null) 'receiptNumber': receiptNumber,
      if (transactionDate != null) 'transactionDate': transactionDate!.toIso8601String(),
      if (cashierName != null) 'cashierName': cashierName,
      if (laneNumber != null) 'laneNumber': laneNumber,
      'items': items.map((item) => item.toJson()).toList(),
      if (subtotal != null) 'subtotal': subtotal,
      if (tax != null) 'tax': tax,
      if (total != null) 'total': total,
      if (thankYouMessage != null) 'thankYouMessage': thankYouMessage,
      if (customFields != null) 'customFields': customFields,
    };
  }

  @override
  String toString() {
    return 'ReceiptData(store: $storeName, items: ${items.length}, total: \$${calculatedTotal.toStringAsFixed(2)})';
  }
}

/// Represents a discovered Zebra printer
class DiscoveredPrinter {
  final String address;
  final int port;
  final String? friendlyName;
  final String? serialNumber;
  final String interfaceType; // TCP, BT, USB
  final Map<String, dynamic>? additionalInfo;

  const DiscoveredPrinter({
    required this.address,
    required this.port,
    this.friendlyName,
    this.serialNumber,
    required this.interfaceType,
    this.additionalInfo,
  });

  factory DiscoveredPrinter.fromMap(Map<String, dynamic> map) {
    return DiscoveredPrinter(
      address: map['address'] ?? '',
      port: map['port'] ?? 9100,
      friendlyName: map['friendlyName'],
      serialNumber: map['serialNumber'],
      interfaceType: map['interfaceType'] ?? 'TCP',
      additionalInfo: map['additionalInfo']?.cast<String, dynamic>(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'address': address,
      'port': port,
      'friendlyName': friendlyName,
      'serialNumber': serialNumber,
      'interfaceType': interfaceType,
      'additionalInfo': additionalInfo,
    };
  }

  @override
  String toString() {
    return 'DiscoveredPrinter(address: $address, port: $port, name: $friendlyName, type: $interfaceType)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! DiscoveredPrinter) return false;
    return other.address == address && other.interfaceType == interfaceType;
  }

  @override
  int get hashCode => address.hashCode ^ interfaceType.hashCode;
}

/// Represents a connected printer with its discovered info plus dimensions
class ConnectedPrinter {
  final DiscoveredPrinter discoveredPrinter;
  final int? printWidthInDots;
  final int? labelLengthInDots;
  final int? dpi;
  final int? maxPrintWidthInDots;
  final int? mediaWidthInDots;
  final DateTime connectedAt;

  const ConnectedPrinter({
    required this.discoveredPrinter,
    this.printWidthInDots,
    this.labelLengthInDots,
    this.dpi,
    this.maxPrintWidthInDots,
    this.mediaWidthInDots,
    required this.connectedAt,
  });

  // Convenience getters to access discovered printer properties
  String get address => discoveredPrinter.address;
  int get port => discoveredPrinter.port;
  String? get friendlyName => discoveredPrinter.friendlyName;
  String? get serialNumber => discoveredPrinter.serialNumber;
  String get interfaceType => discoveredPrinter.interfaceType;
  Map<String, dynamic>? get additionalInfo => discoveredPrinter.additionalInfo;

  @override
  String toString() {
    return 'ConnectedPrinter(${discoveredPrinter.toString()}, ${printWidthInDots}x${labelLengthInDots}@${dpi}dpi)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ConnectedPrinter) return false;
    return discoveredPrinter == other.discoveredPrinter;
  }

  @override
  int get hashCode => discoveredPrinter.hashCode;
}

/// Data models for zebra printer platform interface
class PrinterStatus {
  final bool isOnline;
  final String status;
  final String? errorMessage;
  final bool? paperPresent;  // Whether paper is present in the printer (for label printers with paper hold)

  const PrinterStatus({
    required this.isOnline,
    required this.status,
    this.errorMessage,
    this.paperPresent,
  });

  factory PrinterStatus.fromMap(Map<String, dynamic> map) {
    return PrinterStatus(
      isOnline: map['isOnline'] ?? false,
      status: map['status'] ?? 'unknown',
      errorMessage: map['errorMessage'],
      paperPresent: map['paperPresent'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'isOnline': isOnline,
      'status': status,
      'errorMessage': errorMessage,
      'paperPresent': paperPresent,
    };
  }
}

/// Connection settings for Zebra printers
class ZebraConnectionSettings {
  final ZebraInterfaceType interfaceType;
  final String identifier;
  final int? timeout;

  const ZebraConnectionSettings({
    required this.interfaceType,
    required this.identifier,
    this.timeout,
  });

  Map<String, dynamic> toMap() {
    return {
      'interfaceType': interfaceType.name,
      'identifier': identifier,
      'timeout': timeout,
    };
  }
}

/// Interface types supported by Zebra printers
enum ZebraInterfaceType {
  tcp,
  bluetooth,
  bluetoothLE,
  usb,
}

/// Print language enum for Zebra printers
enum ZebraPrintLanguage {
  zpl,  // Zebra Programming Language
  cpcl, // Common Printing Command Language
}

/// Print job configuration for Zebra printers
class PrintJob {
  final String content; // Raw ZPL or CPCL commands
  final ZebraPrintLanguage? language; // Language hint (auto-detected if null)
  final Map<String, dynamic>? settings;

  const PrintJob({
    required this.content,
    this.language,
    this.settings,
  });

  Map<String, dynamic> toMap() {
    return {
      'content': content,
      'language': language?.name,
      'settings': settings,
    };
  }
}
