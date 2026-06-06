import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../../core/utils/either.dart';
import '../../data/models/cafe_model.dart';
import '../repositories/cafe_repository.dart';

class GetCafeDetailsParams {
  final String cafeId;
  GetCafeDetailsParams(this.cafeId);
}

class GetCafeDetailsUseCase implements UseCase<CafeModel, GetCafeDetailsParams> {
  final CafeRepository repository;
  GetCafeDetailsUseCase(this.repository);

  @override
  Future<Either<Failure, CafeModel>> call(GetCafeDetailsParams params) {
    return repository.getCafeDetails(params.cafeId);
  }
}
