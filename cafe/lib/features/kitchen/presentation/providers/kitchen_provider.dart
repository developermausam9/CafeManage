import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../../core/network/supabase_config.dart';
import '../../../orders/data/models/order_model.dart';
import '../../../orders/data/models/order_item_model.dart';

enum KitchenState { initial, loading, loaded, error }

class KitchenOrder {
  final OrderModel order;
  final List<OrderItemModel> items;

  KitchenOrder({required this.order, required this.items});
}

class KitchenProvider extends ChangeNotifier {
  final SupabaseClient _client = SupabaseConfig.client;

  KitchenState _state = KitchenState.initial;
  KitchenState get state => _state;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  List<KitchenOrder> _kitchenOrders = [];
  List<KitchenOrder> get kitchenOrders => _kitchenOrders;

  List<KitchenOrder> get pendingOrders => _kitchenOrders.where((o) => o.order.status == 'kitchen_sent' || o.order.status == 'pending').toList();
  List<KitchenOrder> get preparingOrders => _kitchenOrders.where((o) => o.order.status == 'preparing').toList();
  List<KitchenOrder> get readyOrders => _kitchenOrders.where((o) => o.order.status == 'ready').toList();

  String? _cafeId;
  StreamSubscription? _subscription;

  void init(String cafeId) {
    _cafeId = cafeId;
    fetchOrders();
    _subscribeToOrders(cafeId);
  }

  Future<void> fetchOrders() async {
    if (_cafeId == null) return;
    
    // Set loading only if it's the first load to prevent screen flickering
    if (_state == KitchenState.initial) {
      _state = KitchenState.loading;
      notifyListeners();
    }

    final cacheBox = Hive.box('cache');
    final cacheKey = 'kitchen_orders_$_cafeId';

    try {
      // Fetch orders in active kitchen workflow states, joining waiter name, table name, and room number
      final ordersResponse = await _client
          .from('orders')
          .select('*, waiter:profiles!waiter_id(full_name), table:tables!table_id(name), room:rooms!room_id(room_number)')
          .eq('cafe_id', _cafeId!)
          .inFilter('status', ['kitchen_sent', 'pending', 'preparing', 'ready'])
          .order('created_at', ascending: true);


      final List<OrderModel> orders = (ordersResponse as List).map((json) => OrderModel.fromJson(json)).toList();

      if (orders.isEmpty) {
        _kitchenOrders = [];
        await cacheBox.put(cacheKey, jsonEncode([]));
        _state = KitchenState.loaded;
        notifyListeners();
        return;
      }

      final orderIds = orders.map((e) => e.id).toList();

      // Fetch items for these orders
      final itemsResponse = await _client
          .from('order_items')
          .select()
          .inFilter('order_id', orderIds);

      final List<OrderItemModel> allItems = (itemsResponse as List).map((json) => OrderItemModel.fromJson(json)).toList();

      _kitchenOrders = orders.map((order) {
        return KitchenOrder(
          order: order,
          items: allItems.where((i) => i.orderId == order.id).toList(),
        );
      }).toList();

      // Cache this list
      final listToCache = _kitchenOrders.map((ko) => {
        'order': ko.order.toJson(),
        'items': ko.items.map((i) => i.toJson()).toList(),
      }).toList();
      await cacheBox.put(cacheKey, jsonEncode(listToCache));

      _state = KitchenState.loaded;
    } catch (e) {
      debugPrint('[KitchenProvider] Error fetching kitchen orders online: $e. Using cache fallback...');
      _errorMessage = null; // Clear to prevent blocking the UI with red screen
      
      // Load cached online kitchen orders
      final cachedString = cacheBox.get(cacheKey);
      List<KitchenOrder> localOrders = [];
      if (cachedString != null) {
        try {
          final List list = jsonDecode(cachedString);
          localOrders = list.map((json) {
            final order = OrderModel.fromJson(json['order']);
            final List itemsJson = json['items'] ?? [];
            final items = itemsJson.map((i) => OrderItemModel.fromJson(i)).toList();
            return KitchenOrder(order: order, items: items);
          }).toList();
        } catch (_) {}
      }

      // Scan offline_orders box and merge any pending ones
      final offlineBox = Hive.box('offline_orders');
      final List<KitchenOrder> offlineKitchenOrders = [];
      for (var key in offlineBox.keys) {
        try {
          final orderJsonString = offlineBox.get(key);
          if (orderJsonString != null) {
            final Map<String, dynamic> data = jsonDecode(orderJsonString);
            final order = OrderModel.fromJson(data['order']);
            if (['kitchen_sent', 'pending', 'preparing', 'ready'].contains(order.status)) {
              final List itemsJson = data['items'] ?? [];
              final items = itemsJson.map((i) => OrderItemModel.fromJson(i)).toList();
              offlineKitchenOrders.add(KitchenOrder(order: order, items: items));
            }
          }
        } catch (_) {}
      }

      // Merge cached orders and offline orders
      final Map<String, KitchenOrder> merged = {};
      for (var ko in localOrders) {
        merged[ko.order.id] = ko;
      }
      for (var ko in offlineKitchenOrders) {
        merged[ko.order.id] = ko;
      }

      _kitchenOrders = merged.values.toList();
      _kitchenOrders.sort((a, b) => (a.order.createdAt ?? DateTime.now()).compareTo(b.order.createdAt ?? DateTime.now()));
      _state = KitchenState.loaded;
    }
    notifyListeners();
  }

  void _subscribeToOrders(String cafeId) {
    _subscription?.cancel();
    _subscription = _client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('cafe_id', cafeId)
        .listen((data) {
          fetchOrders(); // Refetch fully when there's any change
        }, onError: (err) {
          debugPrint("Realtime kitchen orders stream error: $err");
        });
  }

  Future<void> updateOrderStatus(String orderId, String newStatus) async {
    bool isOnline = true;
    if (!kIsWeb) {
      try {
        final lookup = await InternetAddress.lookup('google.com')
            .timeout(const Duration(seconds: 1));
        isOnline = lookup.isNotEmpty && lookup[0].rawAddress.isNotEmpty;
      } catch (_) {
        isOnline = false;
      }
    }

    if (!isOnline) {
      // 1. Update in local memory list for responsive UI
      final index = _kitchenOrders.indexWhere((o) => o.order.id == orderId);
      if (index >= 0) {
        final current = _kitchenOrders[index];
        final updatedOrder = current.order.copyWith(status: newStatus, updatedAt: DateTime.now().toUtc());
        _kitchenOrders[index] = KitchenOrder(order: updatedOrder, items: current.items);

        // 2. Persist to cache box so it is saved across restarts
        final cacheBox = Hive.box('cache');
        final cacheKey = 'kitchen_orders_$_cafeId';
        final cachedString = cacheBox.get(cacheKey);
        if (cachedString != null) {
          try {
            final List list = jsonDecode(cachedString);
            final idx = list.indexWhere((item) => item['order']['id'] == orderId);
            if (idx >= 0) {
              list[idx]['order']['status'] = newStatus;
              list[idx]['order']['updated_at'] = updatedOrder.updatedAt?.toIso8601String();
              await cacheBox.put(cacheKey, jsonEncode(list));
            }
          } catch (_) {}
        }

        // 3. Save to 'offline_orders' to sync to Supabase when online
        final offlineBox = Hive.box('offline_orders');
        bool foundInOffline = false;
        for (var key in offlineBox.keys) {
          try {
            final orderJsonString = offlineBox.get(key);
            if (orderJsonString != null) {
              final Map<String, dynamic> data = jsonDecode(orderJsonString);
              final orderJson = data['order'] as Map<String, dynamic>;
              if (orderJson['id'] == orderId) {
                orderJson['status'] = newStatus;
                orderJson['updated_at'] = updatedOrder.updatedAt?.toIso8601String();
                await offlineBox.put(key, jsonEncode(data));
                foundInOffline = true;
                break;
              }
            }
          } catch (_) {}
        }

        if (!foundInOffline) {
          final newOfflineData = {
            'order': updatedOrder.toJson(),
            'items': current.items.map((i) => i.toJson()).toList(),
          };
          await offlineBox.add(jsonEncode(newOfflineData));
        }

        notifyListeners();
      }
      return;
    }

    try {
      await _client
          .from('orders')
          .update({'status': newStatus})
          .eq('id', orderId);
      
      try {
        final orderRes = await _client.from('orders').select('*, table:tables!table_id(name), room:rooms!room_id(room_number)').eq('id', orderId).single();
        final isRoomService = orderRes['room_id'] != null;
        final displayName = isRoomService 
            ? 'Room ${orderRes['room']?['room_number'] ?? 'Unknown'}' 
            : (orderRes['table']?['name'] != null ? 'Table ${orderRes['table']['name']}' : 'Takeaway');
        final cleanTableNo = isRoomService 
            ? 'Room ${orderRes['room']?['room_number'] ?? 'Unknown'}'
            : (orderRes['table']?['name'] ?? 'Takeaway');
        final cafeId = orderRes['cafe_id'] as String;
        
        if (newStatus == 'preparing') {
          await _client.from('notifications').insert({
            'cafe_id': cafeId,
            'recipient_role': 'waiter',
            'title': 'Order Preparing',
            'message': 'Kitchen has started preparing items for $displayName.',
            'type': 'preparing',
            'metadata': {
              'order_id': orderId,
              'table_no': cleanTableNo,
            },
          });
        } else if (newStatus == 'ready') {
          await _client.from('notifications').insert({
            'cafe_id': cafeId,
            'recipient_role': 'waiter',
            'title': 'Order Ready to Serve',
            'message': 'Order is READY in the kitchen for $displayName. Please serve!',
            'type': 'kitchen_ready',
            'metadata': {
              'order_id': orderId,
              'table_no': cleanTableNo,
            },
          });
        }
      } catch (ex) {
        debugPrint("Error creating kitchen status notification: $ex");
      }
      
      // Update local state immediately for fast UI response
      final index = _kitchenOrders.indexWhere((o) => o.order.id == orderId);
      if (index >= 0) {
        final current = _kitchenOrders[index];
        final updatedOrder = current.order.copyWith(status: newStatus);
        _kitchenOrders[index] = KitchenOrder(order: updatedOrder, items: current.items);
        notifyListeners();
      }
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
