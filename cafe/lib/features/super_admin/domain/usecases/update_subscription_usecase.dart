import '../../../../core/utils/either.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/super_admin_repository.dart';
import '../../data/models/subscription_model.dart';

class UpdateSubscriptionUseCase implements UseCase<void, SubscriptionModel> {
  final SuperAdminRepository repository;

  UpdateSubscriptionUseCase(this.repository);

  @override
  Future<Either<Failure, void>> call(SubscriptionModel params) async {
    return await repository.updateSubscription(params);
  }
}
