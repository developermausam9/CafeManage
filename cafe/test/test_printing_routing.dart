import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:cafe/core/services/models/printer_config_model.dart';
import 'package:cafe/core/presentation/providers/printer_provider.dart';
import 'package:cafe/features/orders/data/models/order_model.dart';
import 'package:cafe/features/orders/data/models/order_item_model.dart';
import 'package:cafe/features/orders/presentation/models/cart_item.dart';
import 'package:cafe/features/menu/data/models/product_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late PrinterProvider printerProvider;

  setUpAll(() async {
    // Redirect debugPrint to standard print for test console visibility
    debugPrint = (String? message, {int? wrapWidth}) {
      print('DEBUG PRINT: $message');
    };

    // Initialize temporary Hive box
    tempDir = await Directory.systemTemp.createTemp('cafe_printer_hive_test');
    Hive.init(tempDir.path);
    await Hive.openBox('printer_settings');
    await Hive.openBox('cache');

    // Shared preferences mocks to prevent runtime plugins binding errors
    SharedPreferences.setMockInitialValues({});

    // Mock blue_thermal_printer method channel calls
    const channel = MethodChannel('blue_thermal_printer/methods');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (methodCall) async {
      if (methodCall.method == 'state') {
        return 0; // Disconnected state indicator
      }
      if (methodCall.method == 'isOn') {
        return false;
      }
      if (methodCall.method == 'isConnected') {
        return false;
      }
      return null;
    });
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  setUp(() async {
    // Mock blue_thermal_printer method channel calls
    const channel = MethodChannel('blue_thermal_printer/methods');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (methodCall) async {
      if (methodCall.method == 'state') {
        return 0; // Disconnected state indicator
      }
      if (methodCall.method == 'isOn') {
        return false;
      }
      if (methodCall.method == 'isConnected') {
        return false;
      }
      return null;
    });

    // Clear Hive printer settings before every test to isolate state
    await Hive.box('printer_settings').clear();
    printerProvider = PrinterProvider();
  });

  group('Advanced Printing & Multi-Printer Subsystem Tests', () {
    test('1. Default Configurations Initialization', () {
      expect(printerProvider.counterConfig, isNotNull);
      expect(printerProvider.kitchenConfig, isNotNull);

      // Verify IDs and roles
      expect(printerProvider.counterConfig!.id, equals('counter_printer'));
      expect(printerProvider.counterConfig!.role, equals(PrinterRole.counter));
      expect(printerProvider.counterConfig!.isEnabled, isTrue);
      expect(printerProvider.counterConfig!.status, equals('Disconnected'));

      expect(printerProvider.kitchenConfig!.id, equals('kitchen_printer'));
      expect(printerProvider.kitchenConfig!.role, equals(PrinterRole.kitchen));
      expect(printerProvider.kitchenConfig!.isEnabled, isTrue);
      expect(printerProvider.kitchenConfig!.status, equals('Disconnected'));
    });

    test('2. Save and Persist Custom Bluetooth Printer Config', () async {
      final bluetoothConfig = PrinterConfig(
        id: 'counter_printer',
        name: 'Master Counter thermal',
        connectionType: PrinterConnectionType.bluetooth,
        role: PrinterRole.counter,
        btName: 'POS-58-BT',
        btAddress: '00:11:22:33:FF:EE',
        paperSize: '58mm',
        isEnabled: true,
      );

      await printerProvider.savePrinterConfig(bluetoothConfig);

      // Check immediate provider memory state update
      expect(printerProvider.counterConfig!.name, equals('Master Counter thermal'));
      expect(printerProvider.counterConfig!.btAddress, equals('00:11:22:33:FF:EE'));
      expect(printerProvider.counterConfig!.connectionType, equals(PrinterConnectionType.bluetooth));

      // Reload config directly from Hive to verify absolute persistence
      final box = Hive.box('printer_settings');
      final savedJson = box.get('counter_printer');
      expect(savedJson, isNotNull);

      final reloadedConfig = PrinterConfig.fromJson(jsonDecode(savedJson));
      expect(reloadedConfig.name, equals('Master Counter thermal'));
      expect(reloadedConfig.btName, equals('POS-58-BT'));
      expect(reloadedConfig.paperSize, equals('58mm'));
    });

    test('3. Save and Persist Custom WiFi LAN Printer Config', () async {
      final wifiConfig = PrinterConfig(
        id: 'kitchen_printer',
        name: 'Hot Kitchen Printer',
        connectionType: PrinterConnectionType.wifi,
        role: PrinterRole.kitchen,
        ipAddress: '192.168.1.150',
        port: 9100,
        paperSize: '80mm',
        isEnabled: true,
      );

      await printerProvider.savePrinterConfig(wifiConfig);

      // Verify state matches WiFi details
      expect(printerProvider.kitchenConfig!.name, equals('Hot Kitchen Printer'));
      expect(printerProvider.kitchenConfig!.ipAddress, equals('192.168.1.150'));
      expect(printerProvider.kitchenConfig!.port, equals(9100));
      expect(printerProvider.kitchenConfig!.paperSize, equals('80mm'));

      // Check Hive persistence
      final box = Hive.box('printer_settings');
      final savedJson = box.get('kitchen_printer');
      expect(savedJson, isNotNull);

      final reloadedConfig = PrinterConfig.fromJson(jsonDecode(savedJson));
      expect(reloadedConfig.ipAddress, equals('192.168.1.150'));
      expect(reloadedConfig.port, equals(9100));
      expect(reloadedConfig.connectionType, equals(PrinterConnectionType.wifi));
    });

    test('4. Disabled Printer Routing Guard Checks', () async {
      // Configure but disable counter printer
      final disabledCounter = PrinterConfig(
        id: 'counter_printer',
        name: 'Receipt Printer',
        connectionType: PrinterConnectionType.usb,
        role: PrinterRole.counter,
        isEnabled: false,
      );
      await printerProvider.savePrinterConfig(disabledCounter);

      final order = OrderModel(
        id: 'order_1',
        cafeId: 'cafe_1',
        type: 'dine_in',
        tableId: 'table_1',
        tableName: 'Table 1',
        billNumber: 102,
        subtotal: 500.0,
        taxAmount: 65.0,
        serviceCharge: 0.0,
        discount: 0.0,
        grandTotal: 565.0,
        status: 'paid',
        paymentMethod: 'cash',
        createdAt: DateTime.now(),
      );

      // Verify print receipt routed throws Exception when disabled
      expect(
        () => printerProvider.printReceiptRouted(
          order: order,
          items: [],
          cafeName: 'Test Cafe',
          panVat: '987654321',
          cashierName: 'Aria',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('5. WiFi Empty IP Routing Guard Checks', () async {
      // Configure kitchen printer to WiFi, but leave IP address blank
      final emptyIpConfig = PrinterConfig(
        id: 'kitchen_printer',
        name: 'Kitchen WiFi',
        connectionType: PrinterConnectionType.wifi,
        role: PrinterRole.kitchen,
        ipAddress: '',
        isEnabled: true,
      );
      await printerProvider.savePrinterConfig(emptyIpConfig);

      final product = ProductModel(
        id: 'p_1',
        cafeId: 'cafe_1',
        name: 'Espresso',
        sellingPrice: 120.0,
      );
      final cartItem = CartItem(product: product, quantity: 2);

      // Verify print KOT routed throws exception because WiFi IP is not configured
      expect(
        () => printerProvider.printKOTRouted(
          tableNumber: 'Table 5',
          orderType: 'Dine-in',
          items: [cartItem],
        ),
        throwsA(isA<Exception>()),
      );
    });
   group('Printer Config Model Tests', () {
      test('toJson and fromJson matching', () {
        final config = PrinterConfig(
          id: 'test_id',
          name: 'Thermal Test',
          connectionType: PrinterConnectionType.usb,
          role: PrinterRole.counter,
          usbDeviceName: 'USB-POS-Printer',
          isEnabled: true,
          paperSize: '80mm',
        );

        final json = config.toJson();
        final reloaded = PrinterConfig.fromJson(json);

        expect(reloaded.id, equals(config.id));
        expect(reloaded.name, equals(config.name));
        expect(reloaded.connectionType, equals(config.connectionType));
        expect(reloaded.role, equals(config.role));
        expect(reloaded.usbDeviceName, equals(config.usbDeviceName));
        expect(reloaded.isEnabled, equals(config.isEnabled));
        expect(reloaded.paperSize, equals(config.paperSize));
      });

      test('copyWith functionality', () {
        final config = PrinterConfig(
          id: 'copy_id',
          name: 'Original',
          connectionType: PrinterConnectionType.bluetooth,
          role: PrinterRole.kitchen,
        );

        final updated = config.copyWith(
          name: 'Copied and Modified',
          status: 'Connected',
          lastError: 'None',
        );

        expect(updated.id, equals('copy_id'));
        expect(updated.name, equals('Copied and Modified'));
        expect(updated.status, equals('Connected'));
        expect(updated.lastError, equals('None'));
        expect(updated.role, equals(PrinterRole.kitchen)); // unchanged
      });
    });
  });
}
