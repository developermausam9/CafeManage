import '../../../../../core/error/exceptions.dart';
import '../../../../../core/error/failures.dart';
import '../../../../../core/utils/either.dart';
import '../datasources/analytics_remote_data_source.dart';
import '../../domain/repositories/analytics_repository.dart';

class AnalyticsRepositoryImpl implements AnalyticsRepository {
  final AnalyticsRemoteDataSource remoteDataSource;

  AnalyticsRepositoryImpl(this.remoteDataSource);

  @override
  Future<Either<Failure, Map<String, dynamic>>> getDashboardData(String cafeId, DateTime start, DateTime end) async {
    try {
      final orders = await remoteDataSource.getOrdersByDateRange(cafeId, start, end);
      final orderIds = orders.map((o) => o.id).toList();
      final items = await remoteDataSource.getOrderItemsByOrderIds(orderIds);
      final costPrices = await remoteDataSource.getProductCostPrices(cafeId);
      final duePayments = await remoteDataSource.getDuePaymentsByDateRange(cafeId, start, end);
      
      return Right({
        'orders': orders,
        'items': items,
        'costPrices': costPrices,
        'duePayments': duePayments,
      });
    } on ServerException {
      return Left(ServerFailure('Failed to fetch analytics data'));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }
}
