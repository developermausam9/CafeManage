import '../../../../core/utils/either.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/super_admin_repository.dart';

class SuspendCafeUseCase implements UseCase<void, String> {
  final SuperAdminRepository repository;

  SuspendCafeUseCase(this.repository);

  @override
  Future<Either<Failure, void>> call(String cafeId) async {
    return await repository.suspendCafe(cafeId);
  }
}

class ReactivateCafeUseCase implements UseCase<void, String> {
  final SuperAdminRepository repository;

  ReactivateCafeUseCase(this.repository);

  @override
  Future<Either<Failure, void>> call(String cafeId) async {
    return await repository.reactivateCafe(cafeId);
  }
}
