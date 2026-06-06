enum PrinterConnectionType { bluetooth, wifi, usb }
enum PrinterRole { counter, kitchen }

class PrinterConfig {
  final String id;
  final String name;
  final PrinterConnectionType connectionType;
  final PrinterRole role;
  
  // Connection Details
  final String? ipAddress;
  final int port;
  final String? btName;
  final String? btAddress;
  final String? usbDeviceName;
  final bool isEnabled;
  final String paperSize; // '58mm' or '80mm'
  
  // Dynamic runtime metrics (not serialized in Hive)
  final String status; // 'Connected', 'Disconnected', 'Error'
  final DateTime? lastPrintTime;
  final String? lastError;

  PrinterConfig({
    required this.id,
    required this.name,
    required this.connectionType,
    required this.role,
    this.ipAddress,
    this.port = 9100,
    this.btName,
    this.btAddress,
    this.usbDeviceName,
    this.isEnabled = true,
    this.paperSize = '58mm',
    this.status = 'Disconnected',
    this.lastPrintTime,
    this.lastError,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'connectionType': connectionType.name,
    'role': role.name,
    'ipAddress': ipAddress,
    'port': port,
    'btName': btName,
    'btAddress': btAddress,
    'usbDeviceName': usbDeviceName,
    'isEnabled': isEnabled,
    'paperSize': paperSize,
  };

  factory PrinterConfig.fromJson(Map<String, dynamic> json) => PrinterConfig(
    id: json['id'] as String,
    name: json['name'] as String,
    connectionType: PrinterConnectionType.values.firstWhere(
      (e) => e.name == json['connectionType'],
      orElse: () => PrinterConnectionType.bluetooth,
    ),
    role: PrinterRole.values.firstWhere(
      (e) => e.name == json['role'],
      orElse: () => PrinterRole.counter,
    ),
    ipAddress: json['ipAddress'] as String?,
    port: json['port'] as int? ?? 9100,
    btName: json['btName'] as String?,
    btAddress: json['btAddress'] as String?,
    usbDeviceName: json['usbDeviceName'] as String?,
    isEnabled: json['isEnabled'] as bool? ?? true,
    paperSize: json['paperSize'] as String? ?? '58mm',
  );

  PrinterConfig copyWith({
    String? name,
    PrinterConnectionType? connectionType,
    String? ipAddress,
    int? port,
    String? btName,
    String? btAddress,
    String? usbDeviceName,
    bool? isEnabled,
    String? paperSize,
    String? status,
    DateTime? lastPrintTime,
    String? lastError,
  }) => PrinterConfig(
    id: id,
    name: name ?? this.name,
    connectionType: connectionType ?? this.connectionType,
    role: role,
    ipAddress: ipAddress ?? this.ipAddress,
    port: port ?? this.port,
    btName: btName ?? this.btName,
    btAddress: btAddress ?? this.btAddress,
    usbDeviceName: usbDeviceName ?? this.usbDeviceName,
    isEnabled: isEnabled ?? this.isEnabled,
    paperSize: paperSize ?? this.paperSize,
    status: status ?? this.status,
    lastPrintTime: lastPrintTime ?? this.lastPrintTime,
    lastError: lastError ?? this.lastError,
  );
}
