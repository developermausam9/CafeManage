import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/utils/either.dart';
import '../../domain/repositories/inventory_repository.dart';
import '../datasources/inventory_remote_data_source.dart';
import '../models/inventory_log_model.dart';

class InventoryRepositoryImpl implements InventoryRepository {
  final InventoryRemoteDataSource remoteDataSource;

  InventoryRepositoryImpl(this.remoteDataSource);

  @override
  Future<Either<Failure, List<InventoryLogModel>>> getInventoryLogs(String cafeId) async {
    try {
      final logs = await remoteDataSource.getInventoryLogs(cafeId);
      return Right(logs);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    }
  }

  @override
  Future<Either<Failure, InventoryLogModel>> addInventoryLog(InventoryLogModel log) async {
    try {
      final addedLog = await remoteDataSource.addInventoryLog(log);
      return Right(addedLog);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    }
  }
}
