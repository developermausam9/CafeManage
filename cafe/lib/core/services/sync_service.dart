import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/orders/data/models/order_model.dart';
import '../../features/orders/data/models/order_item_model.dart';
import 'connectivity_service.dart';
import 'notification_service.dart';

class SyncService {
  final SupabaseClient client;
  final ConnectivityService connectivityService;
  bool _isSyncing = false;

  SyncService({required this.client, required this.connectivityService}) {
    connectivityService.addListener(_onConnectivityChanged);
    if (connectivityService.isOnline) {
      Future.microtask(() => syncOfflineOrders());
    }
  }

  void _onConnectivityChanged() {
    if (connectivityService.isOnline && !_isSyncing) {
      syncOfflineOrders();
    }
  }

  Future<void> syncOfflineOrders() async {
    if (_isSyncing) return;
    _isSyncing = true;

    final cacheBox = Hive.box('cache');

    try {
      final box = Hive.box('offline_orders');
      final keys = box.keys.toList();
      int successCount = 0;

      for (var key in keys) {
        final orderJsonString = box.get(key);
        if (orderJsonString != null) {
          final Map<String, dynamic> data = jsonDecode(orderJsonString);
          final orderJson = data['order'] as Map<String, dynamic>;
          final itemsJson = (data['items'] as List).cast<Map<String, dynamic>>();

          final String localOrderId = orderJson['id'];
          String supabaseOrderId = localOrderId;

          // 1. Conflict check: Does this order already exist in Supabase?
          final checkRes = await client.from('orders')
              .select('id, bill_number')
              .eq('id', localOrderId)
              .maybeSingle();

          if (checkRes != null) {
            // Already exists in Supabase (e.g. table active order created online but updated offline)
            // Perform an update, preserving the database-assigned sequential bill_number
            final updatedJson = Map<String, dynamic>.from(orderJson);
            updatedJson.remove('bill_number');
            
            await client.from('orders')
                .update(updatedJson)
                .eq('id', localOrderId);
          } else {
            // Completely new order created offline!
            // Perform an insert. Remove 'id' and 'bill_number' so Supabase assigns them uniquely
            final insertJson = Map<String, dynamic>.from(orderJson);
            insertJson.remove('id');
            insertJson.remove('bill_number');

            final orderRes = await client.from('orders')
                .insert(insertJson)
                .select()
                .single();

            supabaseOrderId = orderRes['id'];
          }

          // 2. Upload Order Items using safe upserts by mapping to the finalized order ID
          if (itemsJson.isNotEmpty) {
            final itemsToInsert = itemsJson.map((item) {
              final itemMap = Map<String, dynamic>.from(item);
              itemMap['order_id'] = supabaseOrderId;
              // Keep the item's original UUID to prevent duplicates if sync is retried!
              return itemMap;
            }).toList();

            await client.from('order_items').upsert(itemsToInsert);

            // 3. Deduct Stock remotely & Record Inventory Movements
            for (var item in itemsJson) {
              if (item['product_id'] != null) {
                try {
                  final prodRes = await client.from('products')
                      .select('stock_quantity, is_stock_tracked')
                      .eq('id', item['product_id'])
                      .single();

                  final isTracked = prodRes['is_stock_tracked'] as bool? ?? false;
                  if (isTracked) {
                    final currentStock = (prodRes['stock_quantity'] as num).toInt();
                    await client.from('products')
                        .update({'stock_quantity': currentStock - (item['quantity'] as int)})
                        .eq('id', item['product_id']);
                  }

                  // Record movement
                  await client.from('inventory_movements').insert({
                    'cafe_id': orderJson['cafe_id'],
                    'product_id': item['product_id'],
                    'movement_type': 'out',
                    'quantity': item['quantity'],
                    'reference_id': supabaseOrderId,
                  });
                } catch (e) {
                  debugPrint('Stock deduction sync failure for product ${item['product_id']}: $e');
                }
              }
            }
          }

          // 4. Sync Customer Dues if payment method is 'due'
          final isDue = orderJson['payment_method']?.toString().toLowerCase() == 'due';
          final customerDueId = orderJson['customer_due_id'];
          if (isDue && customerDueId != null) {
            try {
              final customerDueRes = await client.from('customer_dues')
                  .select('total_due')
                  .eq('id', customerDueId)
                  .single();

              final currentDue = (customerDueRes['total_due'] as num).toDouble();
              await client.from('customer_dues').update({
                'total_due': currentDue + (orderJson['grand_total'] as num).toDouble(),
                'last_updated_at': DateTime.now().toUtc().toIso8601String(),
              }).eq('id', customerDueId);
            } catch (e) {
              debugPrint('Dues sync error: $e');
            }
          }

          // 5. Sync Audit Logs
          try {
            await client.from('order_audit_logs').insert({
              'order_id': supabaseOrderId,
              'action': 'sync_offline_order',
              'old_value': 'offline',
              'new_value': orderJson['status'],
              'reason': 'Offline sync completed',
              'performed_by': orderJson['cashier_id'] ?? orderJson['waiter_id'],
              'performed_at': DateTime.now().toUtc().toIso8601String(),
            });
          } catch (e) {
            debugPrint('Audit log sync error: $e');
          }

          // 6. Sync Notifications
          try {
            await client.from('notifications').insert({
              'cafe_id': orderJson['cafe_id'],
              'recipient_role': 'owner',
              'title': 'Offline Order Synced',
              'message': 'Order #${orderJson['bill_number'] ?? "N/A"} was synced from offline cache.',
              'type': 'payment_completed',
              'metadata': {'order_id': supabaseOrderId},
            });
          } catch (e) {
            debugPrint('Notification sync error: $e');
          }

          // Remove from local queue on successful sync
          await box.delete(key);
          successCount++;
        }
      }

      // Record successful sync time and clear errors
      await cacheBox.put('last_synced_time', DateTime.now().toUtc().toIso8601String());
      await cacheBox.put('last_sync_error', null);

      if (successCount > 0) {
        await NotificationService().showSyncStatus(success: true, count: successCount);
      }
    } catch (e) {
      debugPrint('Sync queue failed: $e');
      await cacheBox.put('last_sync_error', e.toString());
      await NotificationService().showSyncStatus(success: false);
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> queueOrderOffline(OrderModel order, List<OrderItemModel> items) async {
    final box = Hive.box('offline_orders');
    final data = {
      'order': order.toJson(),
      'items': items.map((i) => i.toJson()).toList(),
    };
    await box.add(jsonEncode(data));
    
    // Try syncing immediately if online
    if (connectivityService.isOnline) {
      syncOfflineOrders();
    } else {
      await NotificationService().showOfflineWarning();
    }
  }
}
