import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../../core/utils/either.dart';
import '../repositories/analytics_repository.dart';

class GetDashboardDataParams {
  final String cafeId;
  final DateTime start;
  final DateTime end;

  GetDashboardDataParams({required this.cafeId, required this.start, required this.end});
}

class GetDashboardDataUseCase implements UseCase<Map<String, dynamic>, GetDashboardDataParams> {
  final AnalyticsRepository repository;

  GetDashboardDataUseCase(this.repository);

  @override
  Future<Either<Failure, Map<String, dynamic>>> call(GetDashboardDataParams params) {
    return repository.getDashboardData(params.cafeId, params.start, params.end);
  }
}
