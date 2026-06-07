import 'dart:io';
import 'dart:typed_data';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import '../../features/orders/data/models/order_model.dart';
import '../../features/orders/data/models/order_item_model.dart';
import '../../features/orders/presentation/models/cart_item.dart';
import 'models/printer_config_model.dart';

class PrinterService {
  final BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;

  Future<List<BluetoothDevice>> getDevices() async {
    try {
      return await bluetooth.getBondedDevices();
    } catch (e) {
      return [];
    }
  }

  Future<bool> connect(BluetoothDevice device) async {
    try {
      final isConnected = await bluetooth.isConnected;
      if (isConnected == true) {
        await bluetooth.disconnect();
      }
      await bluetooth.connect(device);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> disconnect() async {
    try {
      await bluetooth.disconnect();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> get isConnected async => await bluetooth.isConnected ?? false;

  /// Low-level helper to write bytes to a WiFi / LAN Printer
  Future<bool> printToWifi(String ip, int port, List<int> bytes) async {
    try {
      final socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 3));
      socket.add(bytes);
      await socket.flush();
      await socket.close();
      return true;
    } catch (e) {
      rethrow;
    }
  }

  /// Low-level helper to write bytes to a USB Printer (mock/stub implementation)
  Future<bool> printToUsb(String deviceName, List<int> bytes) async {
    // Stub implementation for platform compatibility
    await Future.delayed(const Duration(milliseconds: 500));
    if (deviceName.isEmpty) {
      throw Exception('USB Printer device name cannot be empty');
    }
    return true;
  }

  /// Master method to print customer receipt to a configured printer
  Future<void> printReceipt({
    required PrinterConfig config,
    required OrderModel order,
    required List<OrderItemModel> items,
    required String cafeName,
    required String panVat,
    required String cashierName,
    String? qrString,
  }) async {
    if (!config.isEnabled) return;

    final profile = await CapabilityProfile.load();
    final PaperSize paperSize = config.paperSize == '80mm' ? PaperSize.mm80 : PaperSize.mm58;
    final generator = Generator(paperSize, profile);
    List<int> bytes = [];

    // Header
    bytes += generator.text(cafeName,
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2));
    bytes += generator.text('PAN/VAT: $panVat', styles: const PosStyles(align: PosAlign.center));
    bytes += generator.emptyLines(1);
    
    // Meta
    bytes += generator.text('Bill No: ${order.billNumber}');
    bytes += generator.text('Date: ${order.createdAt.toString().substring(0, 16)}');
    bytes += generator.text('Cashier: $cashierName');
    bytes += generator.text('Type: ${order.type} ${order.tableId != null ? "(T-${order.tableId})" : ""}');
    bytes += generator.emptyLines(1);
    
    // Items table columns adjusted by paper size
    final int itemWidth = paperSize == PaperSize.mm80 ? 7 : 6;
    final int qtyWidth = paperSize == PaperSize.mm80 ? 2 : 2;
    final int totalWidth = paperSize == PaperSize.mm80 ? 3 : 4;

    bytes += generator.row([
      PosColumn(text: 'Item', width: itemWidth, styles: const PosStyles(bold: true)),
      PosColumn(text: 'Qty', width: qtyWidth, styles: const PosStyles(bold: true, align: PosAlign.right)),
      PosColumn(text: 'Total', width: totalWidth, styles: const PosStyles(bold: true, align: PosAlign.right)),
    ]);
    bytes += generator.hr();
    
    for (var item in items) {
      bytes += generator.row([
        PosColumn(text: item.productName, width: itemWidth),
        PosColumn(text: item.quantity.toInt().toString(), width: qtyWidth, styles: const PosStyles(align: PosAlign.right)),
        PosColumn(text: item.totalPrice.toStringAsFixed(2), width: totalWidth, styles: const PosStyles(align: PosAlign.right)),
      ]);
    }
    bytes += generator.hr();

    // Totals
    bytes += generator.row([
      PosColumn(text: 'Subtotal:', width: 6),
      PosColumn(text: order.subtotal.toStringAsFixed(2), width: 6, styles: const PosStyles(align: PosAlign.right)),
    ]);
    if (order.discount > 0) {
      bytes += generator.row([
        PosColumn(text: 'Discount:', width: 6),
        PosColumn(text: '-${order.discount.toStringAsFixed(2)}', width: 6, styles: const PosStyles(align: PosAlign.right)),
      ]);
    }
    bytes += generator.row([
      PosColumn(text: 'VAT (13%):', width: 6),
      PosColumn(text: order.taxAmount.toStringAsFixed(2), width: 6, styles: const PosStyles(align: PosAlign.right)),
    ]);
    if (order.roomCharge != null && order.roomCharge! > 0) {
      bytes += generator.row([
        PosColumn(text: 'Room Charges:', width: 6),
        PosColumn(text: order.roomCharge!.toStringAsFixed(2), width: 6, styles: const PosStyles(align: PosAlign.right)),
      ]);
    }
    bytes += generator.hr();
    
    bytes += generator.row([
      PosColumn(text: 'Grand Total:', width: 6, styles: const PosStyles(bold: true)),
      PosColumn(text: order.grandTotal.toStringAsFixed(2), width: 6, styles: const PosStyles(bold: true, align: PosAlign.right)),
    ]);
    
    bytes += generator.emptyLines(1);
    bytes += generator.text('Payment: ${order.paymentMethod}', styles: const PosStyles(align: PosAlign.center));
    
    if (qrString != null && qrString.isNotEmpty) {
      bytes += generator.emptyLines(1);
      bytes += generator.qrcode(qrString);
      bytes += generator.text('Scan to Pay', styles: const PosStyles(align: PosAlign.center));
    }
    
    bytes += generator.emptyLines(1);
    bytes += generator.text('Thank you! Please visit again.', styles: const PosStyles(align: PosAlign.center));
    
    bytes += generator.feed(2);
    bytes += generator.cut();

    await _dispatchBytes(config, bytes);
  }

  /// Master method to print KOT to a configured printer
  Future<void> printKOT({
    required PrinterConfig config,
    required String tableNumber,
    required String orderType,
    required List<CartItem> items,
  }) async {
    if (!config.isEnabled) return;

    final profile = await CapabilityProfile.load();
    final PaperSize paperSize = config.paperSize == '80mm' ? PaperSize.mm80 : PaperSize.mm58;
    final generator = Generator(paperSize, profile);
    List<int> bytes = [];

    bytes += generator.text('KOT',
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2));
    bytes += generator.text('Type: $orderType', styles: const PosStyles(align: PosAlign.center));
    if (tableNumber.isNotEmpty) {
      bytes += generator.text('Table: $tableNumber', styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
    }
    bytes += generator.text('Date: ${DateTime.now().toString().substring(0, 16)}');
    bytes += generator.hr();

    bytes += generator.row([
      PosColumn(text: 'Qty', width: 2, styles: const PosStyles(bold: true)),
      PosColumn(text: 'Item', width: 10, styles: const PosStyles(bold: true)),
    ]);
    bytes += generator.hr();

    for (var item in items) {
      bytes += generator.row([
        PosColumn(text: item.quantity.toInt().toString(), width: 2, styles: const PosStyles(bold: true)),
        PosColumn(text: item.product.name, width: 10, styles: const PosStyles(bold: true)),
      ]);
      if (item.note != null && item.note!.isNotEmpty) {
         bytes += generator.text(' Note: ${item.note}', styles: const PosStyles(align: PosAlign.left));
      }
    }
    
    bytes += generator.feed(2);
    bytes += generator.cut();

    await _dispatchBytes(config, bytes);
  }

  /// Master test print method for inline verification
  Future<void> printTest({required PrinterConfig config}) async {
    final profile = await CapabilityProfile.load();
    final PaperSize paperSize = config.paperSize == '80mm' ? PaperSize.mm80 : PaperSize.mm58;
    final generator = Generator(paperSize, profile);
    List<int> bytes = [];

    bytes += generator.text('TEST PRINT',
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2));
    bytes += generator.text('Role: ${config.role.name.toUpperCase()}', styles: const PosStyles(align: PosAlign.center));
    bytes += generator.text('Connection: ${config.connectionType.name.toUpperCase()}', styles: const PosStyles(align: PosAlign.center));
    bytes += generator.text('Width: ${config.paperSize}', styles: const PosStyles(align: PosAlign.center));
    bytes += generator.emptyLines(1);
    bytes += generator.text('If you can read this, your printer is configured and connected correctly!',
        styles: const PosStyles(align: PosAlign.center));
    bytes += generator.hr();
    bytes += generator.feed(2);
    bytes += generator.cut();

    await _dispatchBytes(config, bytes);
  }

  /// Direct routing helper that selects output connection streams
  Future<void> _dispatchBytes(PrinterConfig config, List<int> bytes) async {
    switch (config.connectionType) {
      case PrinterConnectionType.bluetooth:
        final connected = await isConnected;
        if (!connected) {
          throw Exception('Bluetooth printer is disconnected');
        }
        await bluetooth.writeBytes(Uint8List.fromList(bytes));
        break;
      case PrinterConnectionType.wifi:
        if (config.ipAddress == null || config.ipAddress!.isEmpty) {
          throw Exception('WiFi IP Address is not configured');
        }
        await printToWifi(config.ipAddress!, config.port, bytes);
        break;
      case PrinterConnectionType.usb:
        if (config.usbDeviceName == null || config.usbDeviceName!.isEmpty) {
          throw Exception('USB Printer is not configured');
        }
        await printToUsb(config.usbDeviceName!, bytes);
        break;
    }
  }
}
