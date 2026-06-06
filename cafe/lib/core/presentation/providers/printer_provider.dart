import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../services/printer_service.dart';
import '../../services/models/printer_config_model.dart';
import '../../../features/orders/data/models/order_model.dart';
import '../../../features/orders/data/models/order_item_model.dart';
import '../../../features/orders/presentation/models/cart_item.dart';
import '../../services/notification_service.dart';

enum PrinterState { initial, loading, connected, disconnected, error }

class PrinterProvider extends ChangeNotifier {
  final PrinterService _printerService = PrinterService();
  
  PrinterState _state = PrinterState.initial;
  PrinterState get state => _state;

  List<BluetoothDevice> _devices = [];
  List<BluetoothDevice> get devices => _devices;

  BluetoothDevice? _selectedDevice;
  BluetoothDevice? get selectedDevice => _selectedDevice;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  // Multi-Printer Configurations
  PrinterConfig? _counterConfig;
  PrinterConfig? get counterConfig => _counterConfig;

  PrinterConfig? _kitchenConfig;
  PrinterConfig? get kitchenConfig => _kitchenConfig;

  PrinterProvider() {
    _initPrinter();
    
    // Legacy Bluetooth listener
    _printerService.bluetooth.onStateChanged().listen((state) {
      if (state == BlueThermalPrinter.DISCONNECTED) {
        _state = PrinterState.disconnected;
        _selectedDevice = null;
        NotificationService().showPrinterDisconnected();
        
        // Sync dynamic config status
        if (_counterConfig?.connectionType == PrinterConnectionType.bluetooth) {
          _counterConfig = _counterConfig!.copyWith(status: 'Disconnected');
        }
        if (_kitchenConfig?.connectionType == PrinterConnectionType.bluetooth) {
          _kitchenConfig = _kitchenConfig!.copyWith(status: 'Disconnected');
        }
        
        notifyListeners();
      }
    });
  }

  Future<void> _initPrinter() async {
    _loadConfigurations();
    await scanDevices();
    await verifyAllConnections();
  }

  /// Loads configurations from Hive box
  void _loadConfigurations() {
    try {
      final box = Hive.box('printer_settings');
      
      final counterJson = box.get('counter_printer');
      if (counterJson != null) {
        _counterConfig = PrinterConfig.fromJson(jsonDecode(counterJson));
      } else {
        _counterConfig = PrinterConfig(
          id: 'counter_printer',
          name: 'Counter Receipt Printer',
          connectionType: PrinterConnectionType.bluetooth,
          role: PrinterRole.counter,
          status: 'Disconnected',
        );
      }

      final kitchenJson = box.get('kitchen_printer');
      if (kitchenJson != null) {
        _kitchenConfig = PrinterConfig.fromJson(jsonDecode(kitchenJson));
      } else {
        _kitchenConfig = PrinterConfig(
          id: 'kitchen_printer',
          name: 'Kitchen KOT Printer',
          connectionType: PrinterConnectionType.bluetooth,
          role: PrinterRole.kitchen,
          status: 'Disconnected',
        );
      }
    } catch (e) {
      debugPrint('Error loading printer configurations: $e');
    }
    notifyListeners();
  }

  /// Verifies connection state across all active, enabled printer configurations
  Future<void> verifyAllConnections() async {
    if (_counterConfig != null && _counterConfig!.isEnabled) {
      await verifyConnection(_counterConfig!);
    }
    if (_kitchenConfig != null && _kitchenConfig!.isEnabled) {
      await verifyConnection(_kitchenConfig!);
    }
  }

  /// Low-level verifier for a specific printer configuration connection state
  Future<void> verifyConnection(PrinterConfig config) async {
    String status = 'Disconnected';
    String? error;

    try {
      switch (config.connectionType) {
        case PrinterConnectionType.bluetooth:
          final connected = await _printerService.isConnected;
          if (connected) {
            status = 'Connected';
            // Sync legacy fields
            _state = PrinterState.connected;
          } else if (config.btAddress != null) {
            // Attempt auto-reconnect if address exists
            final device = BluetoothDevice(config.btName, config.btAddress);
            final success = await _printerService.connect(device);
            if (success) {
              status = 'Connected';
              _selectedDevice = device;
              _state = PrinterState.connected;
            } else {
              status = 'Error';
              error = 'Auto-reconnect failed';
            }
          }
          break;
        case PrinterConnectionType.wifi:
          if (config.ipAddress != null && config.ipAddress!.isNotEmpty) {
            // Simple probe
            final testSocket = await _printerService.printToWifi(
              config.ipAddress!,
              config.port,
              [0x10, 0x04, 0x01], // DLE EOT 1 status probe
            );
            if (testSocket) {
              status = 'Connected';
            } else {
              status = 'Error';
              error = 'Connection failed';
            }
          } else {
            status = 'Disconnected';
          }
          break;
        case PrinterConnectionType.usb:
          if (config.usbDeviceName != null && config.usbDeviceName!.isNotEmpty) {
            status = 'Connected';
          }
          break;
      }
    } catch (e) {
      status = 'Error';
      error = e.toString();
    }

    _updateConfigStatus(config.id, status, error: error);
  }

  void _updateConfigStatus(String id, String status, {String? error}) {
    if (id == 'counter_printer' && _counterConfig != null) {
      _counterConfig = _counterConfig!.copyWith(status: status, lastError: error);
    } else if (id == 'kitchen_printer' && _kitchenConfig != null) {
      _kitchenConfig = _kitchenConfig!.copyWith(status: status, lastError: error);
    }
    notifyListeners();
  }

  /// Persists a specific config configuration inside local Hive Cache
  Future<void> savePrinterConfig(PrinterConfig config) async {
    try {
      final box = Hive.box('printer_settings');
      await box.put(config.id, jsonEncode(config.toJson()));
      
      if (config.id == 'counter_printer') {
        _counterConfig = config;
      } else {
        _kitchenConfig = config;
      }
      
      notifyListeners();
      await verifyConnection(config);
    } catch (e) {
      debugPrint('Error saving printer configuration: $e');
    }
  }

  Future<void> scanDevices() async {
    _state = PrinterState.loading;
    notifyListeners();

    _devices = await _printerService.getDevices();
    
    _state = PrinterState.disconnected;
    notifyListeners();
  }

  /// Legacy helper to connect standard Bluetooth configuration
  Future<void> connect(BluetoothDevice device) async {
    _state = PrinterState.loading;
    _errorMessage = null;
    notifyListeners();

    final success = await _printerService.connect(device);
    if (success) {
      _selectedDevice = device;
      _state = PrinterState.connected;
      
      // Update config if currently active
      if (_counterConfig?.connectionType == PrinterConnectionType.bluetooth) {
        _counterConfig = _counterConfig!.copyWith(
          status: 'Connected',
          btName: device.name,
          btAddress: device.address,
        );
        await savePrinterConfig(_counterConfig!);
      }
    } else {
      _errorMessage = "Failed to connect to ${device.name}";
      _state = PrinterState.error;
    }
    notifyListeners();
  }

  /// Legacy helper to disconnect standard Bluetooth configuration
  Future<void> disconnect() async {
    await _printerService.disconnect();
    _selectedDevice = null;
    _state = PrinterState.disconnected;
    
    if (_counterConfig?.connectionType == PrinterConnectionType.bluetooth) {
      _counterConfig = _counterConfig!.copyWith(status: 'Disconnected');
      await savePrinterConfig(_counterConfig!);
    }
    if (_kitchenConfig?.connectionType == PrinterConnectionType.bluetooth) {
      _kitchenConfig = _kitchenConfig!.copyWith(status: 'Disconnected');
      await savePrinterConfig(_kitchenConfig!);
    }
    notifyListeners();
  }

  /// Direct Test print action for setting diagnostics
  Future<void> testPrint(PrinterConfig config) async {
    _updateConfigStatus(config.id, 'Connecting...');
    try {
      // Connect first if bluetooth is not connected
      if (config.connectionType == PrinterConnectionType.bluetooth) {
        final connected = await _printerService.isConnected;
        if (!connected && config.btAddress != null) {
          final device = BluetoothDevice(config.btName, config.btAddress);
          await _printerService.connect(device);
        }
      }
      
      await _printerService.printTest(config: config);
      
      if (config.id == 'counter_printer') {
        _counterConfig = _counterConfig!.copyWith(status: 'Connected', lastPrintTime: DateTime.now(), lastError: null);
      } else {
        _kitchenConfig = _kitchenConfig!.copyWith(status: 'Connected', lastPrintTime: DateTime.now(), lastError: null);
      }
    } catch (e) {
      if (config.id == 'counter_printer') {
        _counterConfig = _counterConfig!.copyWith(status: 'Error', lastError: e.toString());
      } else {
        _kitchenConfig = _kitchenConfig!.copyWith(status: 'Error', lastError: e.toString());
      }
    }
    notifyListeners();
  }

  /// Intelligent router for customer receipts (routes to Counter Printer)
  Future<void> printReceiptRouted({
    required OrderModel order,
    required List<OrderItemModel> items,
    required String cafeName,
    required String panVat,
    required String cashierName,
  }) async {
    if (_counterConfig == null || !_counterConfig!.isEnabled) {
      throw Exception('Counter Printer is not configured or disabled');
    }

    _updateConfigStatus('counter_printer', 'Printing...');
    try {
      // Direct connection validation
      if (_counterConfig!.connectionType == PrinterConnectionType.bluetooth) {
        final connected = await _printerService.isConnected;
        if (!connected && _counterConfig!.btAddress != null) {
          final device = BluetoothDevice(_counterConfig!.btName, _counterConfig!.btAddress);
          await _printerService.connect(device);
        }
      }

      await _printerService.printReceipt(
        config: _counterConfig!,
        order: order,
        items: items,
        cafeName: cafeName,
        panVat: panVat,
        cashierName: cashierName,
      );

      _counterConfig = _counterConfig!.copyWith(
        status: 'Connected',
        lastPrintTime: DateTime.now(),
        lastError: null,
      );
    } catch (e) {
      _counterConfig = _counterConfig!.copyWith(
        status: 'Error',
        lastError: e.toString(),
      );
      NotificationService().showReceiptPrintFailed(order.tableId?.toString() ?? 'POS');
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  /// Intelligent router for kitchen KOTs (routes to Kitchen Printer)
  Future<void> printKOTRouted({
    required String tableNumber,
    required String orderType,
    required List<CartItem> items,
  }) async {
    if (_kitchenConfig == null || !_kitchenConfig!.isEnabled) {
      throw Exception('Kitchen Printer is not configured or disabled');
    }

    _updateConfigStatus('kitchen_printer', 'Printing...');
    try {
      // Direct connection validation
      if (_kitchenConfig!.connectionType == PrinterConnectionType.bluetooth) {
        final connected = await _printerService.isConnected;
        if (!connected && _kitchenConfig!.btAddress != null) {
          final device = BluetoothDevice(_kitchenConfig!.btName, _kitchenConfig!.btAddress);
          await _printerService.connect(device);
        }
      }

      await _printerService.printKOT(
        config: _kitchenConfig!,
        tableNumber: tableNumber,
        orderType: orderType,
        items: items,
      );

      _kitchenConfig = _kitchenConfig!.copyWith(
        status: 'Connected',
        lastPrintTime: DateTime.now(),
        lastError: null,
      );
    } catch (e) {
      _kitchenConfig = _kitchenConfig!.copyWith(
        status: 'Error',
        lastError: e.toString(),
      );
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  // Fallback support for original non-routed printReceipt call
  Future<void> printReceipt({
    required OrderModel order,
    required List<OrderItemModel> items,
    required String cafeName,
    required String panVat,
    required String cashierName,
  }) async {
    if (_counterConfig != null && _counterConfig!.isEnabled) {
      await printReceiptRouted(
        order: order,
        items: items,
        cafeName: cafeName,
        panVat: panVat,
        cashierName: cashierName,
      );
    }
  }

  // Fallback support for original non-routed printKOT call
  Future<void> printKOT({
    required String tableNumber,
    required String orderType,
    required List<CartItem> items,
  }) async {
    if (_kitchenConfig != null && _kitchenConfig!.isEnabled) {
      await printKOTRouted(
        tableNumber: tableNumber,
        orderType: orderType,
        items: items,
      );
    }
  }
}
