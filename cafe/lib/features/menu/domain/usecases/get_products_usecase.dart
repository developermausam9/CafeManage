import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../../core/utils/either.dart';
import '../../data/models/product_model.dart';
import '../repositories/product_repository.dart';

class GetProductsParams {
  final String cafeId;
  GetProductsParams(this.cafeId);
}

class GetProductsUseCase implements UseCase<List<ProductModel>, GetProductsParams> {
  final ProductRepository repository;
  GetProductsUseCase(this.repository);

  @override
  Future<Either<Failure, List<ProductModel>>> call(GetProductsParams params) {
    return repository.getProducts(params.cafeId);
  }
}
