import 'dart:convert';
import 'dart:io';
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

      // Check internet connectivity to avoid long DNS query timeouts on startup when offline
      bool online = true;
      try {
        final lookup = await InternetAddress.lookup('google.com').timeout(const Duration(seconds: 1));
        online = lookup.isNotEmpty && lookup[0].rawAddress.isNotEmpty;
      } catch (_) {
        online = false;
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
            .timeout(const Duration(seconds: 3));
        
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
}

