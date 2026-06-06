import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/utils/either.dart';
import '../../domain/repositories/cafe_repository.dart';
import '../datasources/cafe_remote_data_source.dart';
import '../models/cafe_model.dart';

class CafeRepositoryImpl implements CafeRepository {
  final CafeRemoteDataSource remoteDataSource;

  CafeRepositoryImpl(this.remoteDataSource);

  @override
  Future<Either<Failure, CafeModel>> getCafeDetails(String cafeId) async {
    try {
      final cafe = await remoteDataSource.getCafeDetails(cafeId);
      return Right(cafe);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    }
  }

  @override
  Future<Either<Failure, CafeModel>> updateCafe(CafeModel cafe) async {
    try {
      final updatedCafe = await remoteDataSource.updateCafe(cafe);
      return Right(updatedCafe);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    }
  }
}
