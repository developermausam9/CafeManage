import '../../../../core/utils/either.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/super_admin_repository.dart';

class GetSuperAdminStatsUseCase implements UseCase<Map<String, dynamic>, NoParams> {
  final SuperAdminRepository repository;

  GetSuperAdminStatsUseCase(this.repository);

  @override
  Future<Either<Failure, Map<String, dynamic>>> call(NoParams params) async {
    return await repository.getSuperAdminStats();
  }
}
