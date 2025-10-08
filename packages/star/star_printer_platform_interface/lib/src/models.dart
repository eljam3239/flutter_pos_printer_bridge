/// Data models for Star printer operations
class PrinterStatus {
  final bool isOnline;
  final String status;
  final String? errorMessage;

  const PrinterStatus({
    required this.isOnline,
    required this.status,
    this.errorMessage,
  });

  factory PrinterStatus.fromMap(Map<String, dynamic> map) {
    return PrinterStatus(
      isOnline: map['isOnline'] ?? false,
      status: map['status'] ?? 'unknown',
      errorMessage: map['errorMessage'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'isOnline': isOnline,
      'status': status,
      'errorMessage': errorMessage,
    };
  }
}

/// Connection settings for Star printers
class StarConnectionSettings {
  final StarInterfaceType interfaceType;
  final String identifier;
  final int? timeout;

  const StarConnectionSettings({
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

/// Interface types supported by Star printers
enum StarInterfaceType {
  bluetooth,
  bluetoothLE,
  lan,
  usb,
}

/// Print job configuration
class PrintJob {
  final String content;
  final Map<String, dynamic>? settings;

  const PrintJob({
    required this.content,
    this.settings,
  });

  Map<String, dynamic> toMap() {
    return {
      'content': content,
      'settings': settings,
    };
  }
}
