import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/utils/either.dart';
import '../../domain/repositories/product_repository.dart';
import '../datasources/product_remote_data_source.dart';
import '../models/product_model.dart';

class ProductRepositoryImpl implements ProductRepository {
  final ProductRemoteDataSource remoteDataSource;

  ProductRepositoryImpl(this.remoteDataSource);

  @override
  Future<Either<Failure, List<ProductModel>>> getProducts(String cafeId) async {
    try {
      final products = await remoteDataSource.getProducts(cafeId);
      return Right(products);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    }
  }

  @override
  Future<Either<Failure, ProductModel>> addProduct(ProductModel product) async {
    try {
      final addedProduct = await remoteDataSource.addProduct(product);
      return Right(addedProduct);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    }
  }

  @override
  Future<Either<Failure, ProductModel>> updateProduct(ProductModel product) async {
    try {
      final updatedProduct = await remoteDataSource.updateProduct(product);
      return Right(updatedProduct);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    }
  }

  @override
  Future<Either<Failure, void>> deleteProduct(String id, String cafeId) async {
    try {
      await remoteDataSource.deleteProduct(id, cafeId);
      return const Right(null);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    }
  }
}
