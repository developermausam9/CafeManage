import '../../../../core/error/failures.dart';
import '../../../../core/utils/either.dart';
import '../../data/models/order_model.dart';
import '../../data/models/order_item_model.dart';

abstract class OrderRepository {
  Future<Either<Failure, List<OrderModel>>> getOrders(String cafeId);
  Future<Either<Failure, OrderModel>> createOrder(OrderModel order, List<OrderItemModel> items);
  Future<Either<Failure, OrderModel>> updateOrderStatus(String orderId, String cafeId, String status);
}
