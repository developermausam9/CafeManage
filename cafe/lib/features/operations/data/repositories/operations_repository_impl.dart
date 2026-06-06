import '../../../../../core/error/failures.dart';
import '../../../../../core/utils/either.dart';
import '../../domain/repositories/operations_repository.dart';
import '../datasources/operations_remote_data_source.dart';
import '../models/supplier_model.dart';
import '../models/purchase_invoice_model.dart';
import '../models/expense_model.dart';
import '../models/customer_due_model.dart';

class OperationsRepositoryImpl implements OperationsRepository {
  final OperationsRemoteDataSource remoteDataSource;

  OperationsRepositoryImpl(this.remoteDataSource);

  @override
  Future<Either<Failure, List<SupplierModel>>> getSuppliers(String cafeId) async {
    try {
      final res = await remoteDataSource.getSuppliers(cafeId);
      return Right(res);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> addSupplier(SupplierModel supplier) async {
    try {
      await remoteDataSource.addSupplier(supplier);
      return Right(null);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<PurchaseInvoiceModel>>> getPurchaseInvoices(String cafeId) async {
    try {
      final res = await remoteDataSource.getPurchaseInvoices(cafeId);
      return Right(res);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> addPurchaseInvoice(PurchaseInvoiceModel invoice) async {
    try {
      await remoteDataSource.addPurchaseInvoice(invoice);
      return Right(null);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<ExpenseModel>>> getExpenses(String cafeId) async {
    try {
      final res = await remoteDataSource.getExpenses(cafeId);
      return Right(res);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> addExpense(ExpenseModel expense) async {
    try {
      await remoteDataSource.addExpense(expense);
      return Right(null);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<CustomerDueModel>>> getCustomerDues(String cafeId) async {
    try {
      final res = await remoteDataSource.getCustomerDues(cafeId);
      return Right(res);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> addCustomerDue(CustomerDueModel due) async {
    try {
      await remoteDataSource.addCustomerDue(due);
      return Right(null);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> updateCustomerDue(CustomerDueModel due) async {
    try {
      await remoteDataSource.updateCustomerDue(due);
      return Right(null);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }
}
