import '../../../../core/error/failures.dart';
import '../../../../core/utils/either.dart';
import '../../data/models/cafe_model.dart';

abstract class CafeRepository {
  Future<Either<Failure, CafeModel>> getCafeDetails(String cafeId);
  Future<Either<Failure, CafeModel>> updateCafe(CafeModel cafe);
}
