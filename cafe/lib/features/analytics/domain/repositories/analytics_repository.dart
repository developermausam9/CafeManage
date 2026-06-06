import '../../../../../core/error/failures.dart';
import '../../../../../core/utils/either.dart';
import '../../../orders/data/models/order_model.dart';
import '../../../orders/data/models/order_item_model.dart';

abstract class AnalyticsRepository {
  Future<Either<Failure, Map<String, dynamic>>> getDashboardData(String cafeId, DateTime start, DateTime end);
}
