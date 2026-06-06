import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../../core/utils/either.dart';
import '../../data/models/order_model.dart';
import '../../data/models/order_item_model.dart';
import '../repositories/order_repository.dart';

class CreateOrderParams {
  final OrderModel order;
  final List<OrderItemModel> items;

  CreateOrderParams({required this.order, required this.items});
}

class CreateOrderUseCase implements UseCase<OrderModel, CreateOrderParams> {
  final OrderRepository repository;

  CreateOrderUseCase(this.repository);

  @override
  Future<Either<Failure, OrderModel>> call(CreateOrderParams params) {
    return repository.createOrder(params.order, params.items);
  }
}
