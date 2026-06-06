import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../../core/utils/either.dart';
import '../../data/models/profile_model.dart';
import '../repositories/auth_repository.dart';

class GetCurrentProfileUseCase implements UseCase<ProfileModel, NoParams> {
  final AuthRepository repository;
  GetCurrentProfileUseCase(this.repository);

  @override
  Future<Either<Failure, ProfileModel>> call(NoParams params) {
    return repository.getCurrentProfile();
  }
}
