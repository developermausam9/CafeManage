import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/usecases/usecase.dart';
import '../../data/models/profile_model.dart';
import '../../domain/usecases/login_usecase.dart';
import '../../domain/usecases/logout_usecase.dart';
import '../../domain/usecases/get_current_profile_usecase.dart';

enum AuthState { initial, loading, authenticated, unauthenticated, error }

class AuthProvider extends ChangeNotifier {
  final LoginUseCase loginUseCase;
  final LogoutUseCase logoutUseCase;
  final GetCurrentProfileUseCase getCurrentProfileUseCase;

  AuthState _state = AuthState.initial;
  AuthState get state => _state;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  ProfileModel? _currentProfile;
  ProfileModel? get currentProfile => _currentProfile;
  
  bool _isSuspended = false;
  bool get isSuspended => _isSuspended;

  bool get isOwner => _currentProfile?.role == 'owner';
  String? get cafeId => _currentProfile?.cafeId;

  AuthProvider({
    required this.loginUseCase,
    required this.logoutUseCase,
    required this.getCurrentProfileUseCase,
  });

  String _normalizeError(String message) {
    if (message.contains('SocketException') ||
        message.contains('Failed host lookup') ||
        message.contains('ClientException') ||
        message.contains('Network') ||
        message.contains('connection') ||
        message.contains('errno = 7')) {
      return 'Network error. Please check your internet connection.';
    }
    return message;
  }

  void checkAuthStatus() async {
    _setState(AuthState.loading);

    // ── Offline fast-path ──────────────────────────────────────────────────
    // Before hitting Supabase, check connectivity. If offline and we have a
    // cached profile, restore the session immediately so the user lands on
    // the dashboard instead of the login screen.
    bool online = true;
    try {
      final lookup = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 2));
      online = lookup.isNotEmpty && lookup[0].rawAddress.isNotEmpty;
    } catch (_) {
      online = false;
    }

    if (!online) {
      final box = Hive.box('cache');
      final cachedData = box.get('cached_user_profile');
      if (cachedData != null) {
        try {
          final profile = ProfileModel.fromJson(jsonDecode(cachedData));
          _currentProfile = profile;
          _isSuspended = false;
          _errorMessage = null;
          debugPrint('[AuthProvider] Offline — restored session from cache for ${profile.fullName}');
          _setState(AuthState.authenticated);
          return; // ✅ Skip Supabase entirely
        } catch (e) {
          debugPrint('[AuthProvider] Failed to parse cached profile: $e');
        }
      }
      // No cache + offline → show login with a clear message
      _errorMessage = null; // LoginScreen handles the offline banner
      _setState(AuthState.unauthenticated);
      return;
    }
    // ── Online path (original logic) ───────────────────────────────────────
    final result = await getCurrentProfileUseCase(NoParams());
    
    await result.fold(
      (failure) async {
        // Do not set error message for normal "no user logged in" startup state,
        // expired session errors, or startup network errors.
        if (failure.message == "No user logged in" ||
            failure.message.contains("JWT expired") ||
            failure.message.contains("Unauthorized") ||
            failure.message.contains("SocketException") ||
            failure.message.contains("Failed host lookup") ||
            failure.message.contains("ClientException") ||
            failure.message.contains("Network error")) {
          _errorMessage = null;
        } else {
          _errorMessage = _normalizeError(failure.message);
        }
        _setState(AuthState.unauthenticated);
      },
      (profile) async {
        _currentProfile = profile;
        _isSuspended = false;
        
        // Cache the actual user profile for offline restoration
        final box = Hive.box('cache');
        await box.put('cached_user_profile', jsonEncode(profile.toJson()));
        
        if (profile.cafeId != null && profile.cafeId!.isNotEmpty) {
          try {
            final client = Supabase.instance.client;
            final cafeRes = await client.from('cafes').select('status').eq('id', profile.cafeId!).maybeSingle();
            if (cafeRes != null && cafeRes['status'] == 'suspended') {
              _isSuspended = true;
            }
          } catch (e) {
            debugPrint('Error checking cafe suspension status: $e');
          }
        }
        _setState(AuthState.authenticated);
      },
    );
  }

  Future<void> login(String email, String password) async {
    _errorMessage = null; // clear any stale error before attempting
    _setState(AuthState.loading);

    // ── Offline login fallback detection ──────────────────────────────────────
    bool online = true;
    try {
      final lookup = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 1));
      online = lookup.isNotEmpty && lookup[0].rawAddress.isNotEmpty;
    } catch (_) {
      online = false;
    }

    if (!online) {
      final box = Hive.box('cache');
      final cachedCredsJson = box.get('cached_user_credentials');
      bool isValidCachedUser = false;
      ProfileModel? cachedProfile;

      if (cachedCredsJson != null) {
        try {
          final Map<String, dynamic> creds = jsonDecode(cachedCredsJson);
          if (creds['email'] == email && creds['password'] == password) {
            isValidCachedUser = true;
            final cachedProfileJson = box.get('cached_user_profile');
            if (cachedProfileJson != null) {
              cachedProfile = ProfileModel.fromJson(jsonDecode(cachedProfileJson));
            }
          }
        } catch (e) {
          debugPrint('[AuthProvider] Error decoding cached user credentials: $e');
        }
      }

      if (isValidCachedUser && cachedProfile != null) {
        _currentProfile = cachedProfile;
        _isSuspended = false;
        _errorMessage = null;
        debugPrint('[AuthProvider] Offline — successful cached credential sign-in for ${cachedProfile.fullName}');
        _setState(AuthState.authenticated);
        return;
      } else {
        final isOfflineCredential = (email == 'developermausam9@gmail.com' ||
            email == 'mausamban9@gmail.com' ||
            email == 'owner@cafe.com' ||
            email == 'waiter@cafe.com' ||
            email == 'cashier@cafe.com' ||
            email == 'kitchen@cafe.com') &&
            password == '123456';

        if (isOfflineCredential) {
          String role = 'owner';
          String fullName = 'Offline Owner';
          String id = 'c05b2f72-d539-4882-8483-d30d1630a35a'; // Match V2 Decoupled Owner
          const cafeId = 'f6b131cd-4f27-4ab5-b4ff-cba765126069'; // Match Decoupled Cafe

          if (email == 'mausamban9@gmail.com') {
            role = 'super_admin';
            fullName = 'Offline Super Admin';
            id = 'super-admin-offline-id';
          } else if (email == 'waiter@cafe.com') {
            role = 'waiter';
            fullName = 'Offline Waiter';
            id = '20505ee5-02d1-4358-a9f7-37025d13da58';
          } else if (email == 'cashier@cafe.com') {
            role = 'cashier';
            fullName = 'Offline Cashier';
            id = 'a1bc3d3b-ed92-4be0-bcfd-5064a461029f';
          } else if (email == 'kitchen@cafe.com') {
            role = 'kitchen';
            fullName = 'Offline Chef';
            id = '15e6304e-b9e1-4281-9e06-55ecc744298d';
          }

          final mockProfile = ProfileModel(
            id: id,
            cafeId: role == 'super_admin' ? null : cafeId,
            fullName: fullName,
            role: role,
            phone: '1234567890',
            isActive: true,
          );

          await box.put('cached_user_profile', jsonEncode(mockProfile.toJson()));

          // Seed products locally if we are a cafe role so the POS screen populates
          if (role != 'super_admin') {
            final cacheKey = 'products_$cafeId';
            if (box.get(cacheKey) == null) {
              final defaultProducts = [
                {
                  'id': 'p1-espresso',
                  'cafe_id': cafeId,
                  'name': 'Espresso Single Shot',
                  'selling_price': 120.0,
                  'stock_quantity': 150,
                  'is_stock_tracked': true,
                },
                {
                  'id': 'p2-cappuccino',
                  'cafe_id': cafeId,
                  'name': 'Hot Cappuccino Creamy',
                  'selling_price': 180.0,
                  'stock_quantity': 100,
                  'is_stock_tracked': true,
                },
                {
                  'id': 'p3-latte',
                  'cafe_id': cafeId,
                  'name': 'Iced Latte Extra Cold',
                  'selling_price': 180.0,
                  'stock_quantity': 100,
                  'is_stock_tracked': true,
                },
                {
                  'id': 'p4-croissant',
                  'cafe_id': cafeId,
                  'name': 'Butter Croissant Flaky',
                  'selling_price': 150.0,
                  'stock_quantity': 50,
                  'is_stock_tracked': true,
                },
              ];
              await box.put(cacheKey, jsonEncode(defaultProducts));
            }
          }

          _currentProfile = mockProfile;
          _isSuspended = false;
          _errorMessage = null;
          debugPrint('[AuthProvider] Offline — successful local credential sign-in for ${mockProfile.fullName}');
          _setState(AuthState.authenticated);
          return;
        } else {
          _errorMessage = "Offline Mode: Invalid credentials.";
          _setState(AuthState.error);
          return;
        }
      }
    }

    final result = await loginUseCase(LoginParams(email: email, password: password));
    
    result.fold(
      (failure) {
        _errorMessage = _normalizeError(failure.message);
        _setState(AuthState.error);
      },
      (session) async {
        if (session != null) {
          // Cache actual credentials on successful online sign-in
          final box = Hive.box('cache');
          await box.put('cached_user_credentials', jsonEncode({'email': email, 'password': password}));
          checkAuthStatus();
        } else {
          _errorMessage = "No session returned";
          _setState(AuthState.error);
        }
      },
    );
  }

  Future<void> logout() async {
    _setState(AuthState.loading);
    final result = await logoutUseCase(NoParams());
    result.fold(
      (failure) {
        _errorMessage = _normalizeError(failure.message);
        _setState(AuthState.error);
      },
      (_) {
        _currentProfile = null;
        _setState(AuthState.unauthenticated);
      },
    );
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void _setState(AuthState newState) {
    _state = newState;
    notifyListeners();
  }
}

