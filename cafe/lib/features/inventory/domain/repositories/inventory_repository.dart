import '../../../../core/error/failures.dart';
import '../../../../core/utils/either.dart';
import '../../data/models/inventory_log_model.dart';

abstract class InventoryRepository {
  Future<Either<Failure, List<InventoryLogModel>>> getInventoryLogs(String cafeId);
  Future<Either<Failure, InventoryLogModel>> addInventoryLog(InventoryLogModel log);
}
