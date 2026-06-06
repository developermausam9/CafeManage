import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../../core/utils/either.dart';
import '../repositories/product_repository.dart';

class DeleteProductParams {
  final String id;
  final String cafeId;
  DeleteProductParams({required this.id, required this.cafeId});
}

class DeleteProductUseCase implements UseCase<void, DeleteProductParams> {
  final ProductRepository repository;
  DeleteProductUseCase(this.repository);

  @override
  Future<Either<Failure, void>> call(DeleteProductParams params) {
    return repository.deleteProduct(params.id, params.cafeId);
  }
}
