import '../models/supplier_model.dart';
import '../models/purchase_invoice_model.dart';
import '../models/expense_model.dart';
import '../models/customer_due_model.dart';

abstract class OperationsLocalDataSource {
  // Suppliers
  Future<List<SupplierModel>> getSuppliers(String cafeId);
  Future<void> addSupplier(SupplierModel supplier);
  
  // Purchases
  Future<List<PurchaseInvoiceModel>> getPurchaseInvoices(String cafeId);
  Future<void> addPurchaseInvoice(PurchaseInvoiceModel invoice);
  
  // Expenses
  Future<List<ExpenseModel>> getExpenses(String cafeId);
  Future<void> addExpense(ExpenseModel expense);

  // Customer Dues
  Future<List<CustomerDueModel>> getCustomerDues(String cafeId);
  Future<void> addCustomerDue(CustomerDueModel due);
  Future<void> updateCustomerDue(CustomerDueModel due);
}

class OperationsLocalDataSourceImpl implements OperationsLocalDataSource {
  final List<SupplierModel> _suppliers = [];
  final List<PurchaseInvoiceModel> _invoices = [];
  final List<ExpenseModel> _expenses = [];
  final List<CustomerDueModel> _dues = [];

  @override
  Future<List<SupplierModel>> getSuppliers(String cafeId) async {
    return _suppliers.where((s) => s.cafeId == cafeId).toList();
  }

  @override
  Future<void> addSupplier(SupplierModel supplier) async {
    _suppliers.add(supplier);
  }

  @override
  Future<List<PurchaseInvoiceModel>> getPurchaseInvoices(String cafeId) async {
    return _invoices.where((i) => i.cafeId == cafeId).toList();
  }

  @override
  Future<void> addPurchaseInvoice(PurchaseInvoiceModel invoice) async {
    _invoices.add(invoice);
  }

  @override
  Future<List<ExpenseModel>> getExpenses(String cafeId) async {
    return _expenses.where((e) => e.cafeId == cafeId).toList();
  }

  @override
  Future<void> addExpense(ExpenseModel expense) async {
    _expenses.add(expense);
  }

  @override
  Future<List<CustomerDueModel>> getCustomerDues(String cafeId) async {
    return _dues.where((d) => d.cafeId == cafeId).toList();
  }

  @override
  Future<void> addCustomerDue(CustomerDueModel due) async {
    _dues.add(due);
  }

  @override
  Future<void> updateCustomerDue(CustomerDueModel due) async {
    final index = _dues.indexWhere((d) => d.id == due.id);
    if (index >= 0) {
      _dues[index] = due;
    }
  }
}
