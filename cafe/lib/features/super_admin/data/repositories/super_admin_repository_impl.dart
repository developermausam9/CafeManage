import '../../../../core/utils/either.dart';
import '../../../../core/error/failures.dart';
import '../../domain/repositories/super_admin_repository.dart';
import '../datasources/super_admin_remote_data_source.dart';
import '../models/cafe_with_subscription_model.dart';
import '../models/subscription_model.dart';
import '../models/billing_record_model.dart';

class SuperAdminRepositoryImpl implements SuperAdminRepository {
  final SuperAdminRemoteDataSource remoteDataSource;

  SuperAdminRepositoryImpl(this.remoteDataSource);

  @override
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
  }) async {
    try {
      await remoteDataSource.createCafe(
        cafeName: cafeName,
        ownerName: ownerName,
        email: email,
        phone: phone,
        password: password,
        address: address,
        panVat: panVat,
        planType: planType,
        monthlyFee: monthlyFee,
        subscriptionStart: subscriptionStart,
        subscriptionEnd: subscriptionEnd,
        status: status,
      );
      return const Right(null);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
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
  }) async {
    try {
      await remoteDataSource.updateCafe(
        cafeId: cafeId,
        ownerId: ownerId,
        subscriptionId: subscriptionId,
        cafeName: cafeName,
        ownerName: ownerName,
        phone: phone,
        address: address,
        panVat: panVat,
        planType: planType,
        monthlyFee: monthlyFee,
        subscriptionEnd: subscriptionEnd,
        status: status,
      );
      return const Right(null);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<CafeWithSubscriptionModel>>> getAllCafes() async {
    try {
      final res = await remoteDataSource.getAllCafes();
      final list = res.map((json) => CafeWithSubscriptionModel.fromJson(json)).toList();
      return Right(list);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> suspendCafe(String cafeId) async {
    try {
      await remoteDataSource.suspendCafe(cafeId);
      return const Right(null);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> reactivateCafe(String cafeId) async {
    try {
      await remoteDataSource.reactivateCafe(cafeId);
      return const Right(null);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> updateSubscription(SubscriptionModel subscription) async {
    try {
      await remoteDataSource.updateSubscription(subscription);
      return const Right(null);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> addBillingRecord(BillingRecordModel record) async {
    try {
      await remoteDataSource.addBillingRecord(record);
      return const Right(null);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<BillingRecordModel>>> getBillingRecords(String cafeId) async {
    try {
      final list = await remoteDataSource.getBillingRecords(cafeId);
      return Right(list);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> getSuperAdminStats() async {
    try {
      final stats = await remoteDataSource.getSuperAdminStats();
      return Right(stats);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }
}
