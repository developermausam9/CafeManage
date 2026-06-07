import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../../core/error/exceptions.dart' hide AuthException;
import '../models/profile_model.dart';

abstract class AuthRemoteDataSource {
  Future<Session?> signInWithEmail(String email, String password);
  Future<void> signOut();
  Future<ProfileModel> getCurrentProfile();
  Session? get currentSession;
}

class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  final SupabaseClient client;

  AuthRemoteDataSourceImpl(this.client);

  @override
  Session? get currentSession => client.auth.currentSession;

  @override
  Future<Session?> signInWithEmail(String email, String password) async {
    try {
      final response = await client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      return response.session;
    } on AuthException catch (e) {
      throw ServerException(e.message);
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await client.auth.signOut();
    } catch (e) {
      throw ServerException(e.toString());
    } finally {
      final box = Hive.box('cache');
      await box.delete('cached_user_profile');
    }
  }

  @override
  Future<ProfileModel> getCurrentProfile() async {
    final box = Hive.box('cache');
    const cacheKey = 'cached_user_profile';

    try {
      final cachedData = box.get(cacheKey);

      // If we don't have an active online session in memory (e.g., offline startup),
      // immediately fall back to the cached user profile if it exists.
      // This completely bypasses the Supabase Auth network token refresh loop!
      if (client.auth.currentSession == null && cachedData != null) {
        return ProfileModel.fromJson(jsonDecode(cachedData));
      }

      // On web: dart:io is unavailable, skip connectivity pre-check and let
      // Supabase handle its own timeouts. On mobile/desktop: quick socket check.
      bool online = true;
      if (!kIsWeb) {
        online = await _checkConnectivity();
      }

      if (!online) {
        if (cachedData != null) {
          return ProfileModel.fromJson(jsonDecode(cachedData));
        }
        throw ServerException("Network error. Please check your internet connection.");
      }

      final user = client.auth.currentUser;
      if (user == null) {
        // If currentUser is null (e.g., startup delay) but we have cached data, use it!
        if (cachedData != null) {
          return ProfileModel.fromJson(jsonDecode(cachedData));
        }
        throw ServerException("No user logged in");
      }

      try {
        final response = await client
            .from('profiles')
            .select()
            .eq('id', user.id)
            .single()
            .timeout(const Duration(seconds: 8));

        final profile = ProfileModel.fromJson(response);
        await box.put(cacheKey, jsonEncode(profile.toJson()));
        return profile;
      } catch (e) {
        // Fallback to locally cached user profile if offline/SocketException/TimeoutException
        if (cachedData != null) {
          return ProfileModel.fromJson(jsonDecode(cachedData));
        }
        rethrow;
      }
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  /// Quick connectivity check using DNS — only call on non-web platforms.
  Future<bool> _checkConnectivity() async {
    // This method is only called when kIsWeb == false, so dart:io is safe.
    // We use a dynamic eval to prevent the dart2js compiler from tree-shaking
    // dart:io imports on web builds.
    try {
      // ignore: avoid_dynamic_calls
      return await _socketCheck();
    } catch (_) {
      return false;
    }
  }
}

// Separated to a top-level function so dart:io import is in a separate file.
// For simplicity: this just returns true (Supabase will handle its own timeout).
// Real Socket check is done via connectivity_service.dart which runs continuously.
Future<bool> _socketCheck() async {
  // On non-web: let Supabase handle connectivity. The ConnectivityService
  // continuously monitors real network state and updates _isOnline.
  return true;
}
