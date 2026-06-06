import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../features/orders/data/models/order_model.dart';
import '../../features/menu/data/models/product_model.dart';
import '../../features/operations/data/models/expense_model.dart';
import '../../features/operations/data/models/customer_due_model.dart';

class ExportService {
  static final ExportService _instance = ExportService._internal();
  factory ExportService() => _instance;
  ExportService._internal();

  Future<void> exportSales(List<OrderModel> orders) async {
    List<List<dynamic>> rows = [
      ['Bill Number', 'Date', 'Type', 'Subtotal', 'Discount', 'VAT', 'Grand Total', 'Payment Method', 'Cashier', 'Status']
    ];

    for (var order in orders) {
      rows.add([
        order.billNumber,
        order.createdAt?.toIso8601String() ?? 'N/A',
        order.type,
        order.subtotal,
        order.discount,
        order.taxAmount,
        order.grandTotal,
        order.paymentMethod,
        order.cashierId ?? '',
        order.status,
      ]);
    }

    await _generateAndShareCsv(rows, 'Sales_Export');
  }

  Future<void> exportInventory(List<ProductModel> products) async {
    List<List<dynamic>> rows = [
      ['Product Name', 'Category', 'Stock Quantity', 'Cost Price', 'Selling Price', 'Status']
    ];

    for (var p in products) {
      rows.add([
        p.name,
        p.categoryId ?? '',
        p.stockQuantity,
        p.costPrice,
        p.sellingPrice,
        p.isAvailable ? 'Available' : 'Unavailable',
      ]);
    }

    await _generateAndShareCsv(rows, 'Inventory_Export');
  }

  Future<void> exportExpenses(List<ExpenseModel> expenses) async {
    List<List<dynamic>> rows = [
      ['Date', 'Category', 'Amount', 'Description', 'Recorded By']
    ];

    for (var e in expenses) {
      rows.add([
        e.date.toIso8601String(),
        e.category,
        e.amount,
        e.description,
        'N/A', // no recordedBy
      ]);
    }

    await _generateAndShareCsv(rows, 'Expenses_Export');
  }

  Future<void> exportDues(List<CustomerDueModel> dues) async {
    List<List<dynamic>> rows = [
      ['Customer Name', 'Phone', 'Total Due', 'Last Payment Date', 'Status']
    ];

    for (var d in dues) {
      rows.add([
        d.name,
        d.phone,
        d.totalDue,
        d.lastUpdatedAt.toIso8601String(),
        'N/A', // no status
      ]);
    }

    await _generateAndShareCsv(rows, 'Customer_Dues_Export');
  }

  Future<void> _generateAndShareCsv(List<List<dynamic>> rows, String fileNamePrefix) async {
    try {
      String csvContent = csv.encode(rows);
      
      final directory = await getApplicationDocumentsDirectory();
      final path = '${directory.path}/${fileNamePrefix}_${DateTime.now().millisecondsSinceEpoch}.csv';
      final file = File(path);
      await file.writeAsString(csvContent);

      final xFile = XFile(path);
      await Share.shareXFiles([xFile], text: '$fileNamePrefix CSV Export');
    } catch (e) {
      print('Export error: $e');
      throw Exception('Failed to export CSV: $e');
    }
  }
}
