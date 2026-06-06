import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../../core/utils/either.dart';
import '../../data/models/product_model.dart';
import '../repositories/product_repository.dart';

class UpdateProductParams {
  final ProductModel product;
  UpdateProductParams(this.product);
}

class UpdateProductUseCase implements UseCase<ProductModel, UpdateProductParams> {
  final ProductRepository repository;
  UpdateProductUseCase(this.repository);

  @override
  Future<Either<Failure, ProductModel>> call(UpdateProductParams params) {
    return repository.updateProduct(params.product);
  }
}
