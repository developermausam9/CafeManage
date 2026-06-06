import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/error/exceptions.dart';
import '../models/order_model.dart';
import '../models/order_item_model.dart';

abstract class OrderRemoteDataSource {
  Future<List<OrderModel>> getOrders(String cafeId);
  Future<OrderModel> createOrder(OrderModel order, List<OrderItemModel> items);
  Future<OrderModel> updateOrderStatus(String orderId, String cafeId, String status);
}

class OrderRemoteDataSourceImpl implements OrderRemoteDataSource {
  final SupabaseClient client;

  OrderRemoteDataSourceImpl(this.client);

  @override
  Future<List<OrderModel>> getOrders(String cafeId) async {
    try {
      final response = await client
          .from('orders')
          .select()
          .eq('cafe_id', cafeId)
          .order('created_at', ascending: false);
          
      return (response as List).map((json) => OrderModel.fromJson(json)).toList();
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  @override
  Future<OrderModel> createOrder(OrderModel order, List<OrderItemModel> items) async {
    try {
      // In Supabase, inserting order and items can be done via RPC or multiple inserts.
      // We will do order first, then items.
      final orderResponse = await client
          .from('orders')
          .insert(order.toJson()..remove('id')..remove('bill_number'))
          .select()
          .single();
          
      final newOrder = OrderModel.fromJson(orderResponse);
      
      if (items.isNotEmpty) {
        final itemsToInsert = items.map((item) {
          final json = item.toJson();
          json['order_id'] = newOrder.id; // Link to new order
          json.remove('id'); // DB will generate UUID
          return json;
        }).toList();
        
        await client.from('order_items').insert(itemsToInsert);

        // Deduct stock for each item and record movement
        for (var item in items) {
          if (item.productId != null) {
            // Get current stock
            final productRes = await client.from('products').select('stock_quantity').eq('id', item.productId!).single();
            final currentStock = (productRes['stock_quantity'] as num).toInt();
            
            // Deduct
            await client.from('products').update({'stock_quantity': currentStock - item.quantity}).eq('id', item.productId!);

            // Record movement
            await client.from('inventory_movements').insert({
              'cafe_id': order.cafeId,
              'product_id': item.productId,
              'movement_type': 'out',
              'quantity': item.quantity,
              'reference_id': newOrder.id,
            });
          }
        }
      }
      
      return newOrder;
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  @override
  Future<OrderModel> updateOrderStatus(String orderId, String cafeId, String status) async {
    try {
      final response = await client
          .from('orders')
          .update({'status': status})
          .eq('id', orderId)
          .eq('cafe_id', cafeId)
          .select()
          .single();
          
      return OrderModel.fromJson(response);
    } catch (e) {
      throw ServerException(e.toString());
    }
  }
}
