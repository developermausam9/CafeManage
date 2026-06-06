import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../../core/error/exceptions.dart';
import '../../../orders/data/models/order_model.dart';
import '../../../orders/data/models/order_item_model.dart';

abstract class AnalyticsRemoteDataSource {
  Future<List<OrderModel>> getOrdersByDateRange(String cafeId, DateTime start, DateTime end);
  Future<List<OrderItemModel>> getOrderItemsByOrderIds(List<String> orderIds);
  Future<Map<String, double>> getProductCostPrices(String cafeId);
  Future<List<Map<String, dynamic>>> getDuePaymentsByDateRange(String cafeId, DateTime start, DateTime end);
}

class AnalyticsRemoteDataSourceImpl implements AnalyticsRemoteDataSource {
  final SupabaseClient client;

  AnalyticsRemoteDataSourceImpl(this.client);

  @override
  Future<List<OrderModel>> getOrdersByDateRange(String cafeId, DateTime start, DateTime end) async {
    try {
      final response = await client
          .from('orders')
          .select()
          .eq('cafe_id', cafeId)
          .gte('created_at', start.toUtc().toIso8601String())
          .lte('created_at', end.toUtc().toIso8601String())
          .order('created_at', ascending: true);
          
      return (response as List).map((json) => OrderModel.fromJson(json)).toList();
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  @override
  Future<List<OrderItemModel>> getOrderItemsByOrderIds(List<String> orderIds) async {
    if (orderIds.isEmpty) return [];
    
    try {
      final response = await client
          .from('order_items')
          .select()
          .inFilter('order_id', orderIds);
          
      return (response as List).map((json) => OrderItemModel.fromJson(json)).toList();
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  @override
  Future<Map<String, double>> getProductCostPrices(String cafeId) async {
    try {
      final response = await client
          .from('products')
          .select('id, cost_price')
          .eq('cafe_id', cafeId);
          
      final Map<String, double> costPrices = {};
      for (var json in (response as List)) {
        final id = json['id'] as String;
        final cost = (json['cost_price'] as num?)?.toDouble() ?? 0.0;
        costPrices[id] = cost;
      }
      return costPrices;
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getDuePaymentsByDateRange(String cafeId, DateTime start, DateTime end) async {
    try {
      final response = await client
          .from('due_payments')
          .select()
          .eq('cafe_id', cafeId)
          .gte('payment_date', start.toUtc().toIso8601String())
          .lte('payment_date', end.toUtc().toIso8601String());
          
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      throw ServerException(e.toString());
    }
  }
}
