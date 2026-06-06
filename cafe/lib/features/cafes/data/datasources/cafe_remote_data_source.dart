import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../../core/error/exceptions.dart';
import '../models/cafe_model.dart';

abstract class CafeRemoteDataSource {
  Future<CafeModel> getCafeDetails(String cafeId);
  Future<CafeModel> updateCafe(CafeModel cafe);
}

class CafeRemoteDataSourceImpl implements CafeRemoteDataSource {
  final SupabaseClient client;

  CafeRemoteDataSourceImpl(this.client);

  @override
  Future<CafeModel> getCafeDetails(String cafeId) async {
    final box = Hive.box('cache');
    final cacheKey = 'cafe_$cafeId';
    try {
      final response = await client
          .from('cafes')
          .select()
          .eq('id', cafeId)
          .single();
          
      await box.put(cacheKey, jsonEncode(response));
      return CafeModel.fromJson(response);
    } catch (e) {
      debugPrint('[CafeRemoteDataSourceImpl] Error fetching cafe details online: $e. Loading from cache...');
      final cached = box.get(cacheKey);
      if (cached != null) {
        try {
          return CafeModel.fromJson(jsonDecode(cached));
        } catch (_) {}
      }
      throw ServerException(e.toString());
    }
  }

  @override
  Future<CafeModel> updateCafe(CafeModel cafe) async {
    final box = Hive.box('cache');
    final cacheKey = 'cafe_${cafe.id}';
    try {
      final response = await client
          .from('cafes')
          .update(cafe.toJson())
          .eq('id', cafe.id)
          .select()
          .single();
          
      await box.put(cacheKey, jsonEncode(response));
      return CafeModel.fromJson(response);
    } catch (e) {
      debugPrint('[CafeRemoteDataSourceImpl] Error updating cafe: $e. Updating locally only...');
      final cafeJson = cafe.toJson();
      await box.put(cacheKey, jsonEncode(cafeJson));
      return cafe;
    }
  }
}
