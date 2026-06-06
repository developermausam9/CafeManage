import '../../../../core/utils/either.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/super_admin_repository.dart';
import '../../data/models/cafe_with_subscription_model.dart';

class GetAllCafesUseCase implements UseCase<List<CafeWithSubscriptionModel>, NoParams> {
  final SuperAdminRepository repository;

  GetAllCafesUseCase(this.repository);

  @override
  Future<Either<Failure, List<CafeWithSubscriptionModel>>> call(NoParams params) async {
    return await repository.getAllCafes();
  }
}
