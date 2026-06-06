import 'package:flutter/foundation.dart';
import '../../data/models/cafe_model.dart';
import '../../domain/usecases/get_cafe_details_usecase.dart';

enum BusinessSetupState { initial, loading, loaded, error }

class BusinessSetupProvider extends ChangeNotifier {
  final GetCafeDetailsUseCase getCafeDetailsUseCase;

  BusinessSetupState _state = BusinessSetupState.initial;
  BusinessSetupState get state => _state;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  CafeModel? _cafeDetails;
  CafeModel? get cafeDetails => _cafeDetails;

  BusinessSetupProvider({required this.getCafeDetailsUseCase});

  Future<void> loadCafeDetails(String cafeId) async {
    _setState(BusinessSetupState.loading);
    final result = await getCafeDetailsUseCase(GetCafeDetailsParams(cafeId));
    
    result.fold(
      (failure) {
        _errorMessage = failure.message;
        _setState(BusinessSetupState.error);
      },
      (cafe) {
        _cafeDetails = cafe;
        _setState(BusinessSetupState.loaded);
      },
    );
  }

  void _setState(BusinessSetupState newState) {
    _state = newState;
    notifyListeners();
  }
}
