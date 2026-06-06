import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/utils/either.dart';
import '../../domain/repositories/order_repository.dart';
import '../datasources/order_remote_data_source.dart';
import '../models/order_model.dart';
import '../models/order_item_model.dart';

class OrderRepositoryImpl implements OrderRepository {
  final OrderRemoteDataSource remoteDataSource;

  OrderRepositoryImpl(this.remoteDataSource);

  @override
  Future<Either<Failure, List<OrderModel>>> getOrders(String cafeId) async {
    try {
      final orders = await remoteDataSource.getOrders(cafeId);
      return Right(orders);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    }
  }

  @override
  Future<Either<Failure, OrderModel>> createOrder(OrderModel order, List<OrderItemModel> items) async {
    try {
      final createdOrder = await remoteDataSource.createOrder(order, items);
      return Right(createdOrder);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    }
  }

  @override
  Future<Either<Failure, OrderModel>> updateOrderStatus(String orderId, String cafeId, String status) async {
    try {
      final updatedOrder = await remoteDataSource.updateOrderStatus(orderId, cafeId, status);
      return Right(updatedOrder);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    }
  }
}
