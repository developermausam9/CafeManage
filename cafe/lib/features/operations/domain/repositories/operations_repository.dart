import '../../../../core/utils/either.dart';
import '../../../../core/error/failures.dart';
import '../../data/models/supplier_model.dart';
import '../../data/models/purchase_invoice_model.dart';
import '../../data/models/expense_model.dart';
import '../../data/models/customer_due_model.dart';

abstract class OperationsRepository {
  Future<Either<Failure, List<SupplierModel>>> getSuppliers(String cafeId);
  Future<Either<Failure, void>> addSupplier(SupplierModel supplier);

  Future<Either<Failure, List<PurchaseInvoiceModel>>> getPurchaseInvoices(String cafeId);
  Future<Either<Failure, void>> addPurchaseInvoice(PurchaseInvoiceModel invoice);

  Future<Either<Failure, List<ExpenseModel>>> getExpenses(String cafeId);
  Future<Either<Failure, void>> addExpense(ExpenseModel expense);

  Future<Either<Failure, List<CustomerDueModel>>> getCustomerDues(String cafeId);
  Future<Either<Failure, void>> addCustomerDue(CustomerDueModel due);
  Future<Either<Failure, void>> updateCustomerDue(CustomerDueModel due);
}
