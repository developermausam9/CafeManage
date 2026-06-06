import '../../../../core/error/failures.dart';
import '../../../../core/utils/either.dart';
import '../repositories/super_admin_repository.dart';

class CreateCafeParams {
  final String cafeName;
  final String ownerName;
  final String email;
  final String phone;
  final String password;
  final String address;
  final String panVat;
  final String planType;
  final double monthlyFee;
  final DateTime subscriptionStart;
  final DateTime subscriptionEnd;
  final String status;

  CreateCafeParams({
    required this.cafeName,
    required this.ownerName,
    required this.email,
    required this.phone,
    required this.password,
    required this.address,
    required this.panVat,
    required this.planType,
    required this.monthlyFee,
    required this.subscriptionStart,
    required this.subscriptionEnd,
    required this.status,
  });
}

class CreateCafeUseCase {
  final SuperAdminRepository repository;

  CreateCafeUseCase(this.repository);

  Future<Either<Failure, void>> call(CreateCafeParams params) async {
    return await repository.createCafe(
      cafeName: params.cafeName,
      ownerName: params.ownerName,
      email: params.email,
      phone: params.phone,
      password: params.password,
      address: params.address,
      panVat: params.panVat,
      planType: params.planType,
      monthlyFee: params.monthlyFee,
      subscriptionStart: params.subscriptionStart,
      subscriptionEnd: params.subscriptionEnd,
      status: params.status,
    );
  }
}
