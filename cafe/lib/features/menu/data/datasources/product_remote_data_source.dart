import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../../core/error/exceptions.dart';
import '../models/product_model.dart';

abstract class ProductRemoteDataSource {
  Future<List<ProductModel>> getProducts(String cafeId);
  Future<ProductModel> addProduct(ProductModel product);
  Future<ProductModel> updateProduct(ProductModel product);
  Future<void> deleteProduct(String id, String cafeId);
}

class ProductRemoteDataSourceImpl implements ProductRemoteDataSource {
  final SupabaseClient client;

  ProductRemoteDataSourceImpl(this.client);

  @override
  Future<List<ProductModel>> getProducts(String cafeId) async {
    final box = Hive.box('cache');
    final cacheKey = 'products_$cafeId';

    try {
      final response = await client
          .from('products')
          .select()
          .eq('cafe_id', cafeId)
          .order('name');
          
      final products = (response as List)
          .map((json) => ProductModel.fromJson(json))
          .toList();

      // Cache the result
      box.put(cacheKey, jsonEncode(response));

      return products;
    } catch (e) {
      // Fallback to cache
      final cachedData = box.get(cacheKey);
      if (cachedData != null) {
        final List<dynamic> jsonList = jsonDecode(cachedData);
        return jsonList.map((json) => ProductModel.fromJson(json)).toList();
      }
      throw ServerException(e.toString());
    }
  }

  @override
  Future<ProductModel> addProduct(ProductModel product) async {
    try {
      final response = await client
          .from('products')
          .insert(product.toJson()..remove('id')) // DB will generate UUID if we remove it, or we can keep it if generating locally. Let's keep it if we generated UUID in Dart.
          .select()
          .single();
          
      return ProductModel.fromJson(response);
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  @override
  Future<ProductModel> updateProduct(ProductModel product) async {
    try {
      final response = await client
          .from('products')
          .update(product.toJson())
          .eq('id', product.id)
          .eq('cafe_id', product.cafeId) // Double check isolation
          .select()
          .single();
          
      return ProductModel.fromJson(response);
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  @override
  Future<void> deleteProduct(String id, String cafeId) async {
    try {
      await client
          .from('products')
          .delete()
          .eq('id', id)
          .eq('cafe_id', cafeId);
    } catch (e) {
      throw ServerException(e.toString());
    }
  }
}
