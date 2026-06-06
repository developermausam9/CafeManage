import '../../../../core/error/failures.dart';
import '../../../../core/utils/either.dart';
import '../repositories/super_admin_repository.dart';

class UpdateCafeParams {
  final String cafeId;
  final String ownerId;
  final String subscriptionId;
  final String cafeName;
  final String ownerName;
  final String phone;
  final String address;
  final String panVat;
  final String planType;
  final double monthlyFee;
  final DateTime subscriptionEnd;
  final String status;

  UpdateCafeParams({
    required this.cafeId,
    required this.ownerId,
    required this.subscriptionId,
    required this.cafeName,
    required this.ownerName,
    required this.phone,
    required this.address,
    required this.panVat,
    required this.planType,
    required this.monthlyFee,
    required this.subscriptionEnd,
    required this.status,
  });
}

class UpdateCafeUseCase {
  final SuperAdminRepository repository;

  UpdateCafeUseCase(this.repository);

  Future<Either<Failure, void>> call(UpdateCafeParams params) async {
    return await repository.updateCafe(
      cafeId: params.cafeId,
      ownerId: params.ownerId,
      subscriptionId: params.subscriptionId,
      cafeName: params.cafeName,
      ownerName: params.ownerName,
      phone: params.phone,
      address: params.address,
      panVat: params.panVat,
      planType: params.planType,
      monthlyFee: params.monthlyFee,
      subscriptionEnd: params.subscriptionEnd,
      status: params.status,
    );
  }
}
