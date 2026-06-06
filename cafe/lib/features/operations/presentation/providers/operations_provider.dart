import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/repositories/operations_repository.dart';
import '../../data/models/supplier_model.dart';
import '../../data/models/purchase_invoice_model.dart';
import '../../data/models/expense_model.dart';
import '../../data/models/customer_due_model.dart';

enum OperationsState { initial, loading, loaded, error }

class OperationsProvider extends ChangeNotifier {
  final OperationsRepository repository;

  OperationsProvider({required this.repository});

  String? _cafeId;

  OperationsState _state = OperationsState.initial;
  OperationsState get state => _state;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  List<SupplierModel> suppliers = [];
  List<PurchaseInvoiceModel> purchaseInvoices = [];
  List<ExpenseModel> expenses = [];
  List<CustomerDueModel> customerDues = [];

  double get totalSupplierPayable => suppliers.fold(0, (sum, item) => sum + item.totalPayable);
  double get totalCustomerDue => customerDues.fold(0, (sum, item) => sum + item.totalDue);
  double get totalExpenses => expenses.fold(0, (sum, item) => sum + item.amount);

  void init(String cafeId) {
    _cafeId = cafeId;
    fetchAll();
  }

  Future<void> fetchAll() async {
    if (_cafeId == null) return;
    _state = OperationsState.loading;
    notifyListeners();

    final supRes = await repository.getSuppliers(_cafeId!);
    final invRes = await repository.getPurchaseInvoices(_cafeId!);
    final expRes = await repository.getExpenses(_cafeId!);
    final dueRes = await repository.getCustomerDues(_cafeId!);

    supRes.fold((l) => _errorMessage = l.message, (r) => suppliers = r);
    invRes.fold((l) => _errorMessage = l.message, (r) => purchaseInvoices = r);
    expRes.fold((l) => _errorMessage = l.message, (r) => expenses = r);
    dueRes.fold((l) => _errorMessage = l.message, (r) => customerDues = r);

    _state = OperationsState.loaded;
    notifyListeners();
  }

  Future<void> addSupplier(SupplierModel supplier) async {
    await repository.addSupplier(supplier);
    await fetchAll();
  }

  Future<void> addExpense(ExpenseModel expense) async {
    await repository.addExpense(expense);
    await fetchAll();
  }

  Future<void> addPurchaseInvoice(PurchaseInvoiceModel invoice, Function(String productId, int quantity) increaseStock) async {
    await repository.addPurchaseInvoice(invoice);
    increaseStock(invoice.productId, invoice.quantity);
    await fetchAll();
  }

  Future<void> addCustomerDue(CustomerDueModel due) async {
    await repository.addCustomerDue(due);
    await fetchAll();
  }

  Future<void> processDuePayment(CustomerDueModel due, double amountPaid, String paymentMethod) async {
    final client = Supabase.instance.client;

    // 1. Update customer total due
    final newTotalDue = (due.totalDue - amountPaid) > 0 ? (due.totalDue - amountPaid) : 0.0;
    final updated = due.copyWith(
      totalDue: newTotalDue,
      lastUpdatedAt: DateTime.now(),
    );
    await repository.updateCustomerDue(updated);
    
    // 2. Perform FIFO due order clearance
    double amountLeft = amountPaid;
    
    try {
      // Fetch outstanding due orders for this customer
      final orderRes = await client
          .from('orders')
          .select()
          .eq('customer_due_id', due.id)
          .inFilter('payment_status', ['unpaid', 'partial'])
          .order('created_at', ascending: true);
          
      final List orders = orderRes as List;
      for (var orderJson in orders) {
        if (amountLeft <= 0) break;
        
        final orderId = orderJson['id'] as String;
        final remainingDue = (orderJson['remaining_due'] as num).toDouble();
        final paidAmount = (orderJson['paid_amount'] as num).toDouble();
        
        final apply = amountLeft < remainingDue ? amountLeft : remainingDue;
        
        final newRemaining = remainingDue - apply;
        final newPaid = paidAmount + apply;
        final isFullyPaid = newRemaining <= 0;
        
        // Update order in DB
        await client.from('orders').update({
          'paid_amount': newPaid,
          'remaining_due': newRemaining,
          'payment_status': isFullyPaid ? 'paid' : 'partial',
          'paid_at': isFullyPaid ? DateTime.now().toIso8601String() : null,
        }).eq('id', orderId);
        
        // Insert due_payment record linked to this order
        await client.from('due_payments').insert({
          'id': const Uuid().v4(),
          'cafe_id': due.cafeId,
          'due_id': due.id,
          'amount_paid': apply,
          'payment_date': DateTime.now().toIso8601String(),
          'payment_method': paymentMethod.toLowerCase(),
          'order_id': orderId,
        });
        
        amountLeft -= apply;
      }
      
      // If there is still payment left or no orders are linked, insert a generic due_payment record
      if (amountLeft > 0 || orders.isEmpty) {
        await client.from('due_payments').insert({
          'id': const Uuid().v4(),
          'cafe_id': due.cafeId,
          'due_id': due.id,
          'amount_paid': amountLeft,
          'payment_date': DateTime.now().toIso8601String(),
          'payment_method': paymentMethod.toLowerCase(),
          'order_id': null,
        });
      }
    } catch (e) {
      debugPrint("Error clearing due orders FIFO: $e");
    }

    await fetchAll();
  }
}
