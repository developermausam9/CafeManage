import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../../core/utils/either.dart';
import '../../data/models/product_model.dart';
import '../repositories/product_repository.dart';

class AddProductParams {
  final ProductModel product;
  AddProductParams(this.product);
}

class AddProductUseCase implements UseCase<ProductModel, AddProductParams> {
  final ProductRepository repository;
  AddProductUseCase(this.repository);

  @override
  Future<Either<Failure, ProductModel>> call(AddProductParams params) {
    return repository.addProduct(params.product);
  }
}
