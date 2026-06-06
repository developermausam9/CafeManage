import 'package:flutter/foundation.dart';
import '../../../../core/usecases/usecase.dart';
import '../../data/models/cafe_with_subscription_model.dart';
import '../../data/models/subscription_model.dart';
import '../../domain/usecases/get_all_cafes_usecase.dart';
import '../../domain/usecases/get_super_admin_stats_usecase.dart';
import '../../domain/usecases/suspend_cafe_usecase.dart';
import '../../domain/usecases/update_subscription_usecase.dart';
import '../../domain/usecases/create_cafe_usecase.dart';
import '../../domain/usecases/update_cafe_usecase.dart';

enum SuperAdminState { initial, loading, loaded, error }

class SuperAdminProvider extends ChangeNotifier {
  final GetAllCafesUseCase getAllCafesUseCase;
  final GetSuperAdminStatsUseCase getSuperAdminStatsUseCase;
  final SuspendCafeUseCase suspendCafeUseCase;
  final ReactivateCafeUseCase reactivateCafeUseCase;
  final UpdateSubscriptionUseCase updateSubscriptionUseCase;
  final CreateCafeUseCase createCafeUseCase;
  final UpdateCafeUseCase updateCafeUseCase;

  SuperAdminState _state = SuperAdminState.initial;
  SuperAdminState get state => _state;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  List<CafeWithSubscriptionModel> _cafes = [];
  List<CafeWithSubscriptionModel> get cafes => _cafes;

  Map<String, dynamic> _stats = {};
  Map<String, dynamic> get stats => _stats;

  SuperAdminProvider({
    required this.getAllCafesUseCase,
    required this.getSuperAdminStatsUseCase,
    required this.suspendCafeUseCase,
    required this.reactivateCafeUseCase,
    required this.updateSubscriptionUseCase,
    required this.createCafeUseCase,
    required this.updateCafeUseCase,
  });

  Future<void> fetchAllCafes() async {
    _state = SuperAdminState.loading;
    notifyListeners();

    final result = await getAllCafesUseCase(NoParams());
    result.fold(
      (failure) {
        _errorMessage = failure.message;
        _state = SuperAdminState.error;
      },
      (data) {
        _cafes = data;
        _state = SuperAdminState.loaded;
      },
    );
    notifyListeners();
  }

  Future<void> fetchStats() async {
    final result = await getSuperAdminStatsUseCase(NoParams());
    result.fold(
      (failure) {
        // Handle error silently for stats or show global error
      },
      (data) {
        _stats = data;
        notifyListeners();
      },
    );
  }

  Future<bool> toggleCafeSuspension(String cafeId, bool currentlySuspended) async {
    final result = currentlySuspended 
      ? await reactivateCafeUseCase(cafeId)
      : await suspendCafeUseCase(cafeId);

    return result.fold(
      (failure) {
        _errorMessage = failure.message;
        return false;
      },
      (_) {
        fetchAllCafes(); // Refresh
        fetchStats();
        return true;
      },
    );
  }

  Future<bool> updateSubscription(SubscriptionModel subscription) async {
    final result = await updateSubscriptionUseCase(subscription);
    return result.fold(
      (failure) {
        _errorMessage = failure.message;
        return false;
      },
      (_) {
        fetchAllCafes();
        fetchStats();
        return true;
      },
    );
  }

  Future<bool> createCafe(CreateCafeParams params) async {
    _state = SuperAdminState.loading;
    notifyListeners();

    final result = await createCafeUseCase(params);

    return result.fold(
      (failure) {
        _errorMessage = failure.message;
        _state = SuperAdminState.error;
        notifyListeners();
        return false;
      },
      (_) {
        _state = SuperAdminState.loaded;
        fetchAllCafes();
        fetchStats();
        return true;
      },
    );
  }

  Future<bool> updateCafe(UpdateCafeParams params) async {
    _state = SuperAdminState.loading;
    notifyListeners();

    final result = await updateCafeUseCase(params);

    return result.fold(
      (failure) {
        _errorMessage = failure.message;
        _state = SuperAdminState.error;
        notifyListeners();
        return false;
      },
      (_) {
        _state = SuperAdminState.loaded;
        fetchAllCafes();
        fetchStats();
        return true;
      },
    );
  }
}
