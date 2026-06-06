import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/utils/either.dart';
import '../../domain/repositories/expense_repository.dart';
import '../datasources/expense_remote_data_source.dart';
import '../models/expense_model.dart';

class ExpenseRepositoryImpl implements ExpenseRepository {
  final ExpenseRemoteDataSource remoteDataSource;

  ExpenseRepositoryImpl(this.remoteDataSource);

  @override
  Future<Either<Failure, List<ExpenseModel>>> getExpenses(String cafeId) async {
    try {
      final expenses = await remoteDataSource.getExpenses(cafeId);
      return Right(expenses);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    }
  }

  @override
  Future<Either<Failure, ExpenseModel>> addExpense(ExpenseModel expense) async {
    try {
      final addedExpense = await remoteDataSource.addExpense(expense);
      return Right(addedExpense);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    }
  }
}
