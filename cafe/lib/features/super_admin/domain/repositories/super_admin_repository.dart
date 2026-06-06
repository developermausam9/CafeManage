import '../../../../core/utils/either.dart';
import '../../../../core/error/failures.dart';
import '../../data/models/cafe_with_subscription_model.dart';
import '../../data/models/subscription_model.dart';
import '../../data/models/billing_record_model.dart';

abstract class SuperAdminRepository {
  Future<Either<Failure, void>> createCafe({
    required String cafeName,
    required String ownerName,
    required String email,
    required String phone,
    required String password,
    required String address,
    required String panVat,
    required String planType,
    required double monthlyFee,
    required DateTime subscriptionStart,
    required DateTime subscriptionEnd,
    required String status,
  });
  Future<Either<Failure, void>> updateCafe({
    required String cafeId,
    required String ownerId,
    required String subscriptionId,
    required String cafeName,
    required String ownerName,
    required String phone,
    required String address,
    required String panVat,
    required String planType,
    required double monthlyFee,
    required DateTime subscriptionEnd,
    required String status,
  });
  Future<Either<Failure, List<CafeWithSubscriptionModel>>> getAllCafes();
  Future<Either<Failure, void>> suspendCafe(String cafeId);
  Future<Either<Failure, void>> reactivateCafe(String cafeId);
  Future<Either<Failure, void>> updateSubscription(SubscriptionModel subscription);
  Future<Either<Failure, void>> addBillingRecord(BillingRecordModel record);
  Future<Either<Failure, List<BillingRecordModel>>> getBillingRecords(String cafeId);
  Future<Either<Failure, Map<String, dynamic>>> getSuperAdminStats();
}
