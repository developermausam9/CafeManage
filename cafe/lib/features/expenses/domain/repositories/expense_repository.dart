import '../../../../core/error/failures.dart';
import '../../../../core/utils/either.dart';
import '../../data/models/expense_model.dart';

abstract class ExpenseRepository {
  Future<Either<Failure, List<ExpenseModel>>> getExpenses(String cafeId);
  Future<Either<Failure, ExpenseModel>> addExpense(ExpenseModel expense);
}
