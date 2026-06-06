import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/foundation.dart';
import '../../../../../core/error/exceptions.dart';
import '../models/supplier_model.dart';
import '../models/purchase_invoice_model.dart';
import '../models/expense_model.dart';
import '../models/customer_due_model.dart';

abstract class OperationsRemoteDataSource {
  Future<List<SupplierModel>> getSuppliers(String cafeId);
  Future<void> addSupplier(SupplierModel supplier);

  Future<List<PurchaseInvoiceModel>> getPurchaseInvoices(String cafeId);
  Future<void> addPurchaseInvoice(PurchaseInvoiceModel invoice);

  Future<List<ExpenseModel>> getExpenses(String cafeId);
  Future<void> addExpense(ExpenseModel expense);

  Future<List<CustomerDueModel>> getCustomerDues(String cafeId);
  Future<void> addCustomerDue(CustomerDueModel due);
  Future<void> updateCustomerDue(CustomerDueModel due);
}

class OperationsRemoteDataSourceImpl implements OperationsRemoteDataSource {
  final SupabaseClient client;

  OperationsRemoteDataSourceImpl(this.client);

  @override
  Future<List<SupplierModel>> getSuppliers(String cafeId) async {
    final box = Hive.box('cache');
    final cacheKey = 'suppliers_$cafeId';
    try {
      final response = await client.from('suppliers').select().eq('cafe_id', cafeId).order('name', ascending: true);
      await box.put(cacheKey, jsonEncode(response));
      return (response as List).map((json) => SupplierModel.fromJson(json)).toList();
    } catch (e) {
      debugPrint('[OperationsRemoteDataSourceImpl] Error fetching suppliers online: $e. Loading from cache...');
      final cached = box.get(cacheKey);
      if (cached != null) {
        try {
          final List list = jsonDecode(cached);
          return list.map((json) => SupplierModel.fromJson(json)).toList();
        } catch (_) {}
      }
      throw ServerException(e.toString());
    }
  }

  @override
  Future<void> addSupplier(SupplierModel supplier) async {
    try {
      await client.from('suppliers').insert(supplier.toJson());
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  @override
  Future<List<PurchaseInvoiceModel>> getPurchaseInvoices(String cafeId) async {
    final box = Hive.box('cache');
    final cacheKey = 'purchase_invoices_$cafeId';
    try {
      final response = await client.from('purchase_invoices').select().eq('cafe_id', cafeId).order('created_at', ascending: false);
      await box.put(cacheKey, jsonEncode(response));
      return (response as List).map((json) => PurchaseInvoiceModel.fromJson(json)).toList();
    } catch (e) {
      debugPrint('[OperationsRemoteDataSourceImpl] Error fetching purchase invoices online: $e. Loading from cache...');
      final cached = box.get(cacheKey);
      if (cached != null) {
        try {
          final List list = jsonDecode(cached);
          return list.map((json) => PurchaseInvoiceModel.fromJson(json)).toList();
        } catch (_) {}
      }
      throw ServerException(e.toString());
    }
  }

  @override
  Future<void> addPurchaseInvoice(PurchaseInvoiceModel invoice) async {
    try {
      // Create Invoice
      await client.from('purchase_invoices').insert(invoice.toJson());
      
      // Update supplier total payable if supplierId is provided
      if (invoice.supplierId != null) {
        final supplierRes = await client.from('suppliers').select('total_payable').eq('id', invoice.supplierId!).single();
        final currentPayable = (supplierRes['total_payable'] as num).toDouble();
        await client.from('suppliers').update({'total_payable': currentPayable + invoice.totalCost}).eq('id', invoice.supplierId!);
      }
      
      // Update product stock using RPC or two-step
      final productRes = await client.from('products').select('stock_quantity').eq('id', invoice.productId).single();
      final currentStock = (productRes['stock_quantity'] as num).toInt();
      await client.from('products').update({'stock_quantity': currentStock + invoice.quantity}).eq('id', invoice.productId);
      
      // Record inventory movement
      await client.from('inventory_movements').insert({
        'cafe_id': invoice.cafeId,
        'product_id': invoice.productId,
        'movement_type': 'in',
        'quantity': invoice.quantity,
        'reference_id': invoice.id,
      });

    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  @override
  Future<List<ExpenseModel>> getExpenses(String cafeId) async {
    final box = Hive.box('cache');
    final cacheKey = 'expenses_$cafeId';
    try {
      final response = await client.from('expenses').select().eq('cafe_id', cafeId).order('date', ascending: false);
      await box.put(cacheKey, jsonEncode(response));
      return (response as List).map((json) => ExpenseModel.fromJson(json)).toList();
    } catch (e) {
      debugPrint('[OperationsRemoteDataSourceImpl] Error fetching expenses online: $e. Loading from cache...');
      final cached = box.get(cacheKey);
      if (cached != null) {
        try {
          final List list = jsonDecode(cached);
          return list.map((json) => ExpenseModel.fromJson(json)).toList();
        } catch (_) {}
      }
      throw ServerException(e.toString());
    }
  }

  @override
  Future<void> addExpense(ExpenseModel expense) async {
    try {
      await client.from('expenses').insert(expense.toJson());
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  @override
  Future<List<CustomerDueModel>> getCustomerDues(String cafeId) async {
    final box = Hive.box('cache');
    final cacheKey = 'customer_dues_$cafeId';
    try {
      final response = await client.from('customer_dues').select().eq('cafe_id', cafeId).order('name', ascending: true);
      await box.put(cacheKey, jsonEncode(response));
      return (response as List).map((json) => CustomerDueModel.fromJson(json)).toList();
    } catch (e) {
      debugPrint('[OperationsRemoteDataSourceImpl] Error fetching customer dues online: $e. Loading from cache...');
      final cached = box.get(cacheKey);
      if (cached != null) {
        try {
          final List list = jsonDecode(cached);
          return list.map((json) => CustomerDueModel.fromJson(json)).toList();
        } catch (_) {}
      }
      throw ServerException(e.toString());
    }
  }

  @override
  Future<void> addCustomerDue(CustomerDueModel due) async {
    try {
      await client.from('customer_dues').insert(due.toJson());
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  @override
  Future<void> updateCustomerDue(CustomerDueModel due) async {
    try {
      await client.from('customer_dues').update(due.toJson()).eq('id', due.id);
    } catch (e) {
      throw ServerException(e.toString());
    }
  }
}
