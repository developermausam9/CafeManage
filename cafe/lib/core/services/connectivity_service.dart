import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class ConnectivityService extends ChangeNotifier {
  final Connectivity _connectivity = Connectivity();
  late StreamSubscription<List<ConnectivityResult>> _subscription;

  bool _isOnline = true;
  bool get isOnline => _isOnline;

  ConnectivityService() {
    _init();
  }

  Future<void> _init() async {
    // On web, connectivity_plus can't detect wifi/mobile properly.
    // Always assume online on web and let Supabase requests fail naturally.
    if (kIsWeb) {
      _isOnline = true;
      // Still subscribe but use the web-aware update logic
      _subscription = _connectivity.onConnectivityChanged.listen(_updateStatus);
      return;
    }

    // Mobile/desktop: check initial status
    try {
      final results = await _connectivity.checkConnectivity();
      _updateStatus(results);
    } catch (e) {
      _isOnline = true; // Default to true if check fails
    }

    // Listen for changes
    _subscription = _connectivity.onConnectivityChanged.listen(_updateStatus);
  }

  void _updateStatus(List<ConnectivityResult> results) {
    bool hasConnection;

    if (kIsWeb) {
      // On web: default to true unless results explicitly contains ONLY none.
      if (results.isEmpty) {
        hasConnection = true;
      } else {
        hasConnection = !results.every((result) => result == ConnectivityResult.none);
      }
    } else {
      // Mobile/desktop: require an explicit known connection type
      hasConnection = results.any((result) =>
          result == ConnectivityResult.mobile ||
          result == ConnectivityResult.wifi ||
          result == ConnectivityResult.ethernet ||
          result == ConnectivityResult.other);
    }

    if (_isOnline != hasConnection) {
      _isOnline = hasConnection;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
