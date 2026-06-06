import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../../core/network/supabase_config.dart';
import '../../../menu/data/models/product_model.dart';
import '../../data/models/order_model.dart';
import '../../data/models/order_item_model.dart';
import '../../data/models/table_model.dart';
import '../../data/models/order_status_history_model.dart';
import '../../../../core/services/sync_service.dart';
import '../../../../core/services/connectivity_service.dart';
import '../../domain/usecases/create_order_usecase.dart';
import '../models/cart_item.dart';
import '../../../../core/services/notification_service.dart';

enum PosState { initial, loading, success, error }

class PosProvider extends ChangeNotifier {
  final CreateOrderUseCase createOrderUseCase;
  final ConnectivityService connectivityService;
  final SyncService syncService;
  final SupabaseClient _client = SupabaseConfig.client;

  PosState _state = PosState.initial;
  PosState get state => _state;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;
  OrderModel? _lastCompletedOrder;
  OrderModel? get lastCompletedOrder => _lastCompletedOrder;
  List<OrderItemModel> _lastCompletedOrderItems = [];
  List<OrderItemModel> get lastCompletedOrderItems => _lastCompletedOrderItems;

  final List<CartItem> _cart = [];
  List<CartItem> get cart => _cart;

  String _orderType = 'Dine-in';
  String get orderType => _orderType;

  String _paymentMethod = 'Cash';
  String get paymentMethod => _paymentMethod;

  String _selectedTable = '1';
  String get selectedTable => _selectedTable;

  double _discountAmount = 0;
  double get discountAmount => _discountAmount;

  double _taxRate = 0.13; // 13% VAT standard
  double get taxRate => _taxRate;

  // New Table Operations State
  String? activeTableId;
  OrderModel? activeOrder;

  // Waiter Billing Permission State
  bool _waiterBillingEnabled = false;
  bool get waiterBillingEnabled => _waiterBillingEnabled;

  // Order Status History Timeline State
  List<OrderStatusHistoryModel> _orderStatusHistory = [];
  List<OrderStatusHistoryModel> get orderStatusHistory => _orderStatusHistory;

  StreamSubscription? _orderSubscription;
  StreamSubscription? _historySubscription;

  PosProvider({
    required this.createOrderUseCase,
    required this.connectivityService,
    required this.syncService,
  });

  // Math Getters
  double get subtotal => _cart.fold(0, (sum, item) => sum + item.totalPrice);
  double get taxableAmount => (subtotal - _discountAmount) > 0 ? (subtotal - _discountAmount) : 0;
  double get taxAmount => taxableAmount * _taxRate;
  double get grandTotal => taxableAmount + taxAmount;

  // Cart Operations
  void addToCart(ProductModel product) {
    final existingIndex = _cart.indexWhere((i) => i.product.id == product.id);
    if (existingIndex >= 0) {
      _cart[existingIndex].quantity += 1;
    } else {
      _cart.add(CartItem(product: product));
    }
    notifyListeners();
  }

  void updateQuantity(ProductModel product, double newQuantity) {
    if (newQuantity <= 0) {
      removeFromCart(product);
      return;
    }
    final existingIndex = _cart.indexWhere((i) => i.product.id == product.id);
    if (existingIndex >= 0) {
      _cart[existingIndex].quantity = newQuantity;
      notifyListeners();
    }
  }

  void removeFromCart(ProductModel product) {
    _cart.removeWhere((i) => i.product.id == product.id);
    notifyListeners();
  }

  void updateNote(ProductModel product, String note) {
    final existingIndex = _cart.indexWhere((i) => i.product.id == product.id);
    if (existingIndex >= 0) {
      _cart[existingIndex].note = note;
      notifyListeners();
    }
  }

  void clearCart() {
    _cart.clear();
    _discountAmount = 0;
    notifyListeners();
  }

  // Setters
  void setOrderType(String type) {
    _orderType = type;
    if (type != 'Dine-in') {
      activeTableId = null;
      activeOrder = null;
    }
    notifyListeners();
  }

  void setPaymentMethod(String method) {
    _paymentMethod = method;
    notifyListeners();
  }

  void setTable(String table) {
    _selectedTable = table;
    notifyListeners();
  }

  void setDiscount(double discount) {
    _discountAmount = discount;
    notifyListeners();
  }

  void setTaxRate(double rate) {
    _taxRate = rate;
    notifyListeners();
  }

  Future<void> fetchSettings(String cafeId) async {
    final box = Hive.box('cache');
    final cacheKey = 'waiter_billing_enabled_$cafeId';
    try {
      final res = await _client
          .from('settings')
          .select('waiter_billing_enabled')
          .eq('cafe_id', cafeId)
          .maybeSingle();
      if (res != null) {
        _waiterBillingEnabled = res['waiter_billing_enabled'] as bool? ?? false;
        await box.put(cacheKey, _waiterBillingEnabled);
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Error fetching waiter billing permission online: $e. Using cache fallback...");
      final cached = box.get(cacheKey);
      if (cached != null) {
        _waiterBillingEnabled = cached as bool;
        notifyListeners();
      }
    }
  }

  Future<bool> updateWaiterBillingOverride(String cafeId, bool enabled) async {
    final box = Hive.box('cache');
    final cacheKey = 'waiter_billing_enabled_$cafeId';
    try {
      await _client.from('settings').upsert({
        'cafe_id': cafeId,
        'waiter_billing_enabled': enabled,
      }, onConflict: 'cafe_id');
      _waiterBillingEnabled = enabled;
      await box.put(cacheKey, enabled);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint("Error updating waiter billing permission: $e. Updating locally only...");
      _waiterBillingEnabled = enabled;
      await box.put(cacheKey, enabled);
      notifyListeners();
      return true;
    }
  }

  Future<void> fetchOrderStatusHistory(String orderId) async {
    try {
      final res = await _client
          .from('order_status_history')
          .select('*, profiles:profiles!changed_by(full_name)')
          .eq('order_id', orderId)
          .order('changed_at', ascending: true);

      _orderStatusHistory = (res as List)
          .map((json) => OrderStatusHistoryModel.fromJson(json))
          .toList();
      notifyListeners();
    } catch (e) {
      debugPrint("Error fetching order status history: $e");
    }
  }

  void _subscribeToActiveOrder(String orderId) {
    _orderSubscription?.cancel();
    _orderSubscription = _client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('id', orderId)
        .listen((data) async {
          if (data.isNotEmpty) {
            final updatedOrder = OrderModel.fromJson(data.first);
            if (activeOrder == null || activeOrder!.status != updatedOrder.status) {
              activeOrder = updatedOrder;
              notifyListeners();
              await fetchOrderStatusHistory(orderId);
            }
          }
        }, onError: (err) {
          debugPrint("Realtime active order stream error: $err");
        });

    _historySubscription?.cancel();
    _historySubscription = _client
        .from('order_status_history')
        .stream(primaryKey: ['id'])
        .eq('order_id', orderId)
        .listen((data) async {
          await fetchOrderStatusHistory(orderId);
        }, onError: (err) {
          debugPrint("Realtime order status history stream error: $err");
        });
  }

  // Table Selection & Order Restoration
  Future<void> selectTable(TableModel table, String cafeId, {String? userRole}) async {
    activeTableId = table.id;
    _selectedTable = table.name;
    _orderType = 'Dine-in';

    if (table.status == 'free') {
      _orderSubscription?.cancel();
      _historySubscription?.cancel();
      _orderStatusHistory.clear();
      activeOrder = null;
      clearCart();
    } else {
      _setState(PosState.loading);
      try {
        final orderResponse = await _client
            .from('orders')
            .select('*, waiter:profiles!waiter_id(full_name), table:tables!table_id(name)')
            .eq('table_id', table.id)
            .neq('status', 'completed')
            .neq('status', 'cancelled')
            .maybeSingle();

        if (orderResponse != null) {
          activeOrder = OrderModel.fromJson(orderResponse);
          _discountAmount = activeOrder!.discount;
          _paymentMethod = _restorePaymentMethod(activeOrder!.paymentMethod);

          // If the user opening the table is a Cashier, Admin, or Owner, and the order is not yet billed/completed/cancelled, transition to 'billed'
          if ((userRole == 'cashier' || userRole == 'admin' || userRole == 'owner') &&
              activeOrder!.status != 'billed' &&
              activeOrder!.status != 'completed' &&
              activeOrder!.status != 'cancelled') {
            try {
              await _client
                  .from('orders')
                  .update({'status': 'billed'})
                  .eq('id', activeOrder!.id);
              activeOrder = activeOrder!.copyWith(status: 'billed');
            } catch (e) {
              debugPrint("Error updating order to billed: $e");
            }
          }

          // Fetch items for this active order
          final itemsRes = await _client
              .from('order_items')
              .select()
              .eq('order_id', activeOrder!.id);

          final List<OrderItemModel> items = (itemsRes as List)
              .map((json) => OrderItemModel.fromJson(json))
              .toList();

          _cart.clear();
          for (var item in items) {
            final productRes = await _client
                .from('products')
                .select()
                .eq('id', item.productId ?? '')
                .maybeSingle();

            ProductModel product;
            if (productRes != null) {
              product = ProductModel.fromJson(productRes);
            } else {
              product = ProductModel(
                id: item.productId ?? '',
                cafeId: cafeId,
                name: item.productName,
                sellingPrice: item.unitPrice,
                costPrice: item.unitPrice,
                stockQuantity: 9999,
                isAvailable: true,
                isStockTracked: false,
                categoryId: 'Food',
              );
            }

            final cartItem = CartItem(product: product)
              ..quantity = item.quantity.toDouble()
              ..note = item.notes ?? '';
            _cart.add(cartItem);
          }

          // Subscribe to active order changes and fetch timeline
          _subscribeToActiveOrder(activeOrder!.id);
          await fetchOrderStatusHistory(activeOrder!.id);

          _setState(PosState.success);
        } else {
          _orderSubscription?.cancel();
          _historySubscription?.cancel();
          _orderStatusHistory.clear();
          activeOrder = null;
          clearCart();
          _setState(PosState.success);
        }
      } catch (e) {
        _errorMessage = e.toString();
        _setState(PosState.error);
      }
    }
    notifyListeners();
  }

  // Send Order to Kitchen (KOT) without payment
  Future<bool> sendToKitchen(String cafeId, String waiterId) async {
    if (_cart.isEmpty) {
      _errorMessage = "Cart is empty.";
      _setState(PosState.error);
      return false;
    }

    _setState(PosState.loading);

    if (!connectivityService.isOnline) {
      try {
        final orderId = activeOrder?.id ?? const Uuid().v4();
        final billNumber = activeOrder?.billNumber ?? (DateTime.now().millisecondsSinceEpoch % 1000000);
        final isNewOrder = activeOrder == null;

        final order = OrderModel(
          id: orderId,
          cafeId: cafeId,
          customerId: null,
          tableId: activeTableId,
          waiterId: activeOrder?.waiterId ?? waiterId,
          cashierId: null,
          status: 'kitchen_sent',
          paymentMethod: null,
          type: 'dine_in',
          subtotal: subtotal,
          discount: _discountAmount,
          taxAmount: taxAmount,
          serviceCharge: 0,
          grandTotal: grandTotal,
          billNumber: billNumber,
          createdAt: activeOrder?.createdAt?.toUtc() ?? DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        );

        final List<OrderItemModel> items = _cart.map((cartItem) {
          return OrderItemModel(
            id: const Uuid().v4(),
            orderId: orderId,
            productId: cartItem.product.id,
            productName: cartItem.product.name,
            quantity: cartItem.quantity.toInt(),
            unitPrice: cartItem.product.sellingPrice,
            totalPrice: cartItem.totalPrice,
            notes: cartItem.note,
            createdAt: DateTime.now().toUtc(),
            status: 'sent',
          );
        }).toList();

        // Queue order offline
        await syncService.queueOrderOffline(order, items);

        // Update local cache stock so inventory counts reduce offline
        final box = Hive.box('cache');
        final cacheKey = 'products_$cafeId';
        final cachedData = box.get(cacheKey);
        if (cachedData != null) {
          final List<dynamic> jsonList = jsonDecode(cachedData);
          for (var item in _cart) {
            final prodIndex = jsonList.indexWhere((p) => p['id'] == item.product.id);
            if (prodIndex != -1) {
              final oldQty = jsonList[prodIndex]['stock_quantity'] as num? ?? 0;
              jsonList[prodIndex]['stock_quantity'] = (oldQty - item.quantity.toInt()).clamp(0, 999999);
            }
          }
          await box.put(cacheKey, jsonEncode(jsonList));
        }

        clearCart();
        activeTableId = null;
        activeOrder = null;
        _setState(PosState.success);
        return true;
      } catch (e) {
        _errorMessage = e.toString();
        _setState(PosState.error);
        return false;
      }
    }

    try {
      final orderId = activeOrder?.id ?? const Uuid().v4();
      final billNumber = activeOrder?.billNumber ?? (DateTime.now().millisecondsSinceEpoch % 1000000);
      final isNewOrder = activeOrder == null;

      final order = OrderModel(
        id: orderId,
        cafeId: cafeId,
        customerId: null,
        tableId: activeTableId,
        waiterId: activeOrder?.waiterId ?? waiterId,
        cashierId: null,
        status: 'kitchen_sent',
        paymentMethod: null,
        type: 'dine_in',
        subtotal: subtotal,
        discount: _discountAmount,
        taxAmount: taxAmount,
        serviceCharge: 0,
        grandTotal: grandTotal,
        billNumber: billNumber,
        createdAt: activeOrder?.createdAt?.toUtc() ?? DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

      if (isNewOrder) {
        await _client.from('orders').insert(order.toJson()..remove('bill_number'));
        
        // For new order, insert all cart items as 'sent'
        final List<OrderItemModel> items = _cart.map((cartItem) {
          return OrderItemModel(
            id: const Uuid().v4(),
            orderId: orderId,
            productId: cartItem.product.id,
            productName: cartItem.product.name,
            quantity: cartItem.quantity.toInt(),
            unitPrice: cartItem.product.sellingPrice,
            totalPrice: cartItem.totalPrice,
            notes: cartItem.note,
            createdAt: DateTime.now().toUtc(),
            status: 'sent',
          );
        }).toList();

        final itemsToInsert = items.map((item) {
          final json = item.toJson();
          json.remove('id');
          return json;
        }).toList();

        await _client.from('order_items').insert(itemsToInsert);

        // Deduct stock for all items
        for (var item in _cart) {
          if (item.product.isStockTracked) {
            final prodRes = await _client.from('products').select('stock_quantity').eq('id', item.product.id).single();
            final currentStock = (prodRes['stock_quantity'] as num).toInt();
            await _client.from('products').update({'stock_quantity': currentStock - item.quantity.toInt()}).eq('id', item.product.id);
            await _client.from('inventory_movements').insert({
              'cafe_id': cafeId,
              'product_id': item.product.id,
              'movement_type': 'out',
              'quantity': item.quantity.toInt(),
              'reference_id': orderId,
            });
          }
        }

        // Send KOT notification
        await _client.from('notifications').insert({
          'cafe_id': cafeId,
          'recipient_role': 'kitchen',
          'title': 'New KOT Received',
          'message': 'New order sent to kitchen for Table $_selectedTable.',
          'type': 'kot_sent',
          'metadata': {'order_id': orderId},
        });
      } else {
        // Edit order flow: Fetch existing order items that are not cancelled
        final existingRes = await _client.from('order_items').select().eq('order_id', orderId);
        final List<OrderItemModel> existingItems = (existingRes as List)
            .map((json) => OrderItemModel.fromJson(json))
            .where((item) => item.status != 'cancelled')
            .toList();

        await _client
            .from('orders')
            .update(order.toJson()..remove('id')..remove('bill_number'))
            .eq('id', orderId);

        List<String> addedItemNames = [];
        List<String> cancelledItemNames = [];

        // Check each cart item against existing items
        for (var cartItem in _cart) {
          final match = existingItems.where((i) => i.productId == cartItem.product.id).toList();
          
          if (match.isEmpty) {
            // Completely new item added
            final newItem = OrderItemModel(
              id: const Uuid().v4(),
              orderId: orderId,
              productId: cartItem.product.id,
              productName: cartItem.product.name,
              quantity: cartItem.quantity.toInt(),
              unitPrice: cartItem.product.sellingPrice,
              totalPrice: cartItem.totalPrice,
              notes: cartItem.note,
              createdAt: DateTime.now().toUtc(),
              status: 'added',
            );
            final json = newItem.toJson()..remove('id');
            await _client.from('order_items').insert(json);

            // Deduct stock
            if (cartItem.product.isStockTracked) {
              final prodRes = await _client.from('products').select('stock_quantity').eq('id', cartItem.product.id).single();
              final currentStock = (prodRes['stock_quantity'] as num).toInt();
              await _client.from('products').update({'stock_quantity': currentStock - cartItem.quantity.toInt()}).eq('id', cartItem.product.id);
              await _client.from('inventory_movements').insert({
                'cafe_id': cafeId,
                'product_id': cartItem.product.id,
                'movement_type': 'out',
                'quantity': cartItem.quantity.toInt(),
                'reference_id': orderId,
              });
            }
            addedItemNames.add('${cartItem.quantity.toInt()}x ${cartItem.product.name}');
          } else {
            // Match found: compare quantities
            final existingQty = match.fold(0, (sum, i) => sum + i.quantity);
            final diff = cartItem.quantity.toInt() - existingQty;

            if (diff > 0) {
              // Quantity increased: insert the difference as 'added'
              final newItem = OrderItemModel(
                id: const Uuid().v4(),
                orderId: orderId,
                productId: cartItem.product.id,
                productName: cartItem.product.name,
                quantity: diff,
                unitPrice: cartItem.product.sellingPrice,
                totalPrice: diff * cartItem.product.sellingPrice,
                notes: cartItem.note,
                createdAt: DateTime.now().toUtc(),
                status: 'added',
              );
              final json = newItem.toJson()..remove('id');
              await _client.from('order_items').insert(json);

              // Deduct stock for diff
              if (cartItem.product.isStockTracked) {
                final prodRes = await _client.from('products').select('stock_quantity').eq('id', cartItem.product.id).single();
                final currentStock = (prodRes['stock_quantity'] as num).toInt();
                await _client.from('products').update({'stock_quantity': currentStock - diff}).eq('id', cartItem.product.id);
                await _client.from('inventory_movements').insert({
                  'cafe_id': cafeId,
                  'product_id': cartItem.product.id,
                  'movement_type': 'out',
                  'quantity': diff,
                  'reference_id': orderId,
                });
              }
              addedItemNames.add('${diff}x ${cartItem.product.name}');
            } else if (diff < 0) {
              // Quantity decreased: mark the difference as cancelled!
              final cancelQty = diff.abs();
              final primaryItem = match.first;
              
              if (primaryItem.quantity > cancelQty) {
                await _client.from('order_items').update({
                  'quantity': primaryItem.quantity - cancelQty,
                  'total_price': (primaryItem.quantity - cancelQty) * primaryItem.unitPrice,
                }).eq('id', primaryItem.id);
              } else {
                await _client.from('order_items').delete().eq('id', primaryItem.id);
              }

              final cancelItem = OrderItemModel(
                id: const Uuid().v4(),
                orderId: orderId,
                productId: cartItem.product.id,
                productName: cartItem.product.name,
                quantity: cancelQty,
                unitPrice: cartItem.product.sellingPrice,
                totalPrice: cancelQty * cartItem.product.sellingPrice,
                notes: cartItem.note,
                createdAt: DateTime.now().toUtc(),
                status: 'cancelled',
                cancelledBy: waiterId,
                cancellationReason: 'Order edited by Waiter',
                cancelledAt: DateTime.now().toUtc(),
              );
              final json = cancelItem.toJson()..remove('id');
              await _client.from('order_items').insert(json);

              // Restore stock for cancelQty
              if (cartItem.product.isStockTracked) {
                final prodRes = await _client.from('products').select('stock_quantity').eq('id', cartItem.product.id).single();
                final currentStock = (prodRes['stock_quantity'] as num).toInt();
                await _client.from('products').update({'stock_quantity': currentStock + cancelQty}).eq('id', cartItem.product.id);
                await _client.from('inventory_movements').insert({
                  'cafe_id': cafeId,
                  'product_id': cartItem.product.id,
                  'movement_type': 'in',
                  'quantity': cancelQty,
                  'reference_id': orderId,
                });
              }
              cancelledItemNames.add('${cancelQty}x ${cartItem.product.name}');
            }
          }
        }

        // Check for items completely missing in the cart
        for (var existingItem in existingItems) {
          final inCart = _cart.any((i) => i.product.id == existingItem.productId);
          if (!inCart) {
            await _client.from('order_items').update({
              'status': 'cancelled',
              'cancelled_by': waiterId,
              'cancellation_reason': 'Item removed during order edit',
              'cancelled_at': DateTime.now().toUtc().toIso8601String(),
            }).eq('id', existingItem.id);

            // Restore stock
            if (existingItem.productId != null) {
              final prodRes = await _client.from('products').select().eq('id', existingItem.productId!).maybeSingle();
              if (prodRes != null && (prodRes['is_stock_tracked'] as bool? ?? false)) {
                final currentStock = (prodRes['stock_quantity'] as num).toInt();
                await _client.from('products').update({'stock_quantity': currentStock + existingItem.quantity}).eq('id', existingItem.productId!);
                await _client.from('inventory_movements').insert({
                  'cafe_id': cafeId,
                  'product_id': existingItem.productId!,
                  'movement_type': 'in',
                  'quantity': existingItem.quantity,
                  'reference_id': orderId,
                });
              }
            }
            cancelledItemNames.add('${existingItem.quantity}x ${existingItem.productName}');
          }
        }

        // Write audit log
        await _logAudit(orderId, 'modify_item', 'kitchen_sent', 'kitchen_sent', 
            'Order edited. Added: ${addedItemNames.join(", ")}, Cancelled: ${cancelledItemNames.join(", ")}', waiterId);

        // Send notifications to Kitchen
        if (addedItemNames.isNotEmpty) {
          await _client.from('notifications').insert({
            'cafe_id': cafeId,
            'recipient_role': 'kitchen',
            'title': 'Items Added to Order',
            'message': 'Table $_selectedTable added: ${addedItemNames.join(", ")}.',
            'type': 'item_added',
            'metadata': {'order_id': orderId},
          });
        }
        if (cancelledItemNames.isNotEmpty) {
          await _client.from('notifications').insert({
            'cafe_id': cafeId,
            'recipient_role': 'kitchen',
            'title': 'Items Cancelled',
            'message': 'Table $_selectedTable cancelled: ${cancelledItemNames.join(", ")}.',
            'type': 'item_cancelled',
            'metadata': {'order_id': orderId},
          });
        }
      }

      if (activeTableId != null) {
        await _client.from('tables').update({
          'status': 'preparing',
          'is_occupied': true,
        }).eq('id', activeTableId!);
      }

      clearCart();
      activeTableId = null;
      activeOrder = null;
      _setState(PosState.success);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _setState(PosState.error);
      return false;
    }
  }

  // Cancel a specific KOT order item
  Future<bool> cancelOrderItem(String orderId, String orderItemId, String staffId, String reason, String cafeId) async {
    _setState(PosState.loading);
    try {
      final itemRes = await _client.from('order_items').select().eq('id', orderItemId).single();
      final String prodId = itemRes['product_id'] as String;
      final String prodName = itemRes['product_name'] as String;
      final int qty = (itemRes['quantity'] as num).toInt();

      await _client.from('order_items').update({
        'status': 'cancelled',
        'cancelled_by': staffId,
        'cancellation_reason': reason,
        'cancelled_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', orderItemId);

      final prodRes = await _client.from('products').select().eq('id', prodId).maybeSingle();
      if (prodRes != null && (prodRes['is_stock_tracked'] as bool? ?? false)) {
        final currentStock = (prodRes['stock_quantity'] as num).toInt();
        await _client.from('products').update({'stock_quantity': currentStock + qty}).eq('id', prodId);
        
        await _client.from('inventory_movements').insert({
          'cafe_id': cafeId,
          'product_id': prodId,
          'movement_type': 'in',
          'quantity': qty,
          'reference_id': orderId,
        });
      }

      final activeItemsRes = await _client.from('order_items').select().eq('order_id', orderId);
      final list = (activeItemsRes as List).map((json) => OrderItemModel.fromJson(json)).toList();
      final activeItems = list.where((item) => item.status != 'cancelled').toList();
      final newSubtotal = activeItems.fold(0.0, (sum, item) => sum + item.totalPrice);
      
      final orderRes = await _client.from('orders').select('discount').eq('id', orderId).single();
      final discount = (orderRes['discount'] as num).toDouble();
      
      final newTaxable = (newSubtotal - discount) > 0 ? (newSubtotal - discount) : 0.0;
      final newTax = newTaxable * _taxRate;
      final newGrandTotal = newTaxable + newTax;

      await _client.from('orders').update({
        'subtotal': newSubtotal,
        'tax_amount': newTax,
        'grand_total': newGrandTotal,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', orderId);

      await _logAudit(orderId, 'cancel_item', 'quantity: $qty', 'status: cancelled', 'Item: $prodName cancelled. Reason: $reason', staffId);

      await _client.from('notifications').insert({
        'cafe_id': cafeId,
        'recipient_role': 'kitchen',
        'title': 'KOT Item Cancelled',
        'message': 'Item "$prodName" (x$qty) was cancelled on Table $_selectedTable. Reason: $reason',
        'type': 'item_cancelled',
        'metadata': {'order_id': orderId},
      });

      _setState(PosState.success);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _setState(PosState.error);
      return false;
    }
  }

  // Mark order as served (Waiter Flow)
  Future<bool> markAsServed(String orderId, String staffId, String cafeId) async {
    _setState(PosState.loading);
    try {
      await _client.from('orders').update({
        'status': 'served',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', orderId);

      await _logAudit(orderId, 'served', 'ready', 'served', 'Order marked as served by Waiter', staffId);

      await _client.from('notifications').insert({
        'cafe_id': cafeId,
        'recipient_role': 'cashier',
        'title': 'Table Served & Ready',
        'message': 'Table $_selectedTable has been served and is ready for billing.',
        'type': 'billing_pending',
        'metadata': {'order_id': orderId},
      });

      _setState(PosState.success);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _setState(PosState.error);
      return false;
    }
  }

  // Finalize payment for Table/Takeaway orders (Cashier/Owner Flow)
  Future<bool> finalizePayment(String cafeId, String cashierId, {String? customerDueId}) async {
    if (_cart.isEmpty) {
      _errorMessage = "Cart is empty.";
      _setState(PosState.error);
      return false;
    }

    _setState(PosState.loading);

    if (!connectivityService.isOnline) {
      try {
        final orderId = activeOrder?.id ?? const Uuid().v4();
        final billNumber = activeOrder?.billNumber ?? (DateTime.now().millisecondsSinceEpoch % 1000000);
        final isDue = _paymentMethod.toLowerCase() == 'due';
        final isNewOrder = activeOrder == null;

        final order = OrderModel(
          id: orderId,
          cafeId: cafeId,
          customerId: null,
          tableId: activeTableId,
          waiterId: activeOrder?.waiterId ?? cashierId,
          cashierId: cashierId,
          status: 'completed',
          paymentMethod: _paymentMethod.toLowerCase(),
          type: _mapOrderType(_orderType),
          subtotal: subtotal,
          discount: _discountAmount,
          taxAmount: taxAmount,
          serviceCharge: 0,
          grandTotal: grandTotal,
          billNumber: billNumber,
          createdAt: activeOrder?.createdAt?.toUtc() ?? DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
          paymentStatus: isDue ? 'unpaid' : 'paid',
          paidAmount: isDue ? 0.0 : grandTotal,
          remainingDue: isDue ? grandTotal : 0.0,
          paidAt: isDue ? null : DateTime.now().toUtc(),
          completedAt: DateTime.now().toUtc(),
          customerDueId: customerDueId,
        );

        final List<OrderItemModel> items = _cart.map((cartItem) {
          return OrderItemModel(
            id: const Uuid().v4(),
            orderId: orderId,
            productId: cartItem.product.id,
            productName: cartItem.product.name,
            quantity: cartItem.quantity.toInt(),
            unitPrice: cartItem.product.sellingPrice,
            totalPrice: cartItem.totalPrice,
            notes: cartItem.note,
            createdAt: DateTime.now().toUtc(),
            status: 'sent',
          );
        }).toList();

        // If the order already exists in our offline queue, replace/update it!
        final offlineBox = Hive.box('offline_orders');
        bool found = false;
        for (var key in offlineBox.keys) {
          final orderJsonString = offlineBox.get(key);
          if (orderJsonString != null) {
            final Map<String, dynamic> data = jsonDecode(orderJsonString);
            final orderJson = data['order'] as Map<String, dynamic>;
            if (orderJson['id'] == orderId) {
              await offlineBox.put(key, jsonEncode({
                'order': order.toJson(),
                'items': items.map((i) => i.toJson()).toList(),
              }));
              found = true;
              break;
            }
          }
        }

        if (!found) {
          // If not found, queue it!
          await syncService.queueOrderOffline(order, items);
        }

        // Update local cache stock so inventory counts reduce offline
        final box = Hive.box('cache');
        final cacheKey = 'products_$cafeId';
        final cachedData = box.get(cacheKey);
        if (cachedData != null) {
          final List<dynamic> jsonList = jsonDecode(cachedData);
          for (var item in _cart) {
            final prodIndex = jsonList.indexWhere((p) => p['id'] == item.product.id);
            if (prodIndex != -1) {
              final oldQty = jsonList[prodIndex]['stock_quantity'] as num? ?? 0;
              jsonList[prodIndex]['stock_quantity'] = (oldQty - item.quantity.toInt()).clamp(0, 999999);
            }
          }
          await box.put(cacheKey, jsonEncode(jsonList));
        }

        // Cache this completed order so it shows in local Order History immediately!
        final historyKey = 'order_history_$cafeId';
        final cachedHistory = box.get(historyKey);
        List<dynamic> historyList = [];
        if (cachedHistory != null) {
          historyList = jsonDecode(cachedHistory);
        }
        final existingIdx = historyList.indexWhere((o) => o['id'] == orderId);
        if (existingIdx != -1) {
          historyList[existingIdx] = order.toJson();
        } else {
          historyList.insert(0, order.toJson());
        }
        await box.put(historyKey, jsonEncode(historyList));

        // Update local table status in table cache to be free!
        if (activeTableId != null) {
          final tablesKey = 'tables_$cafeId';
          final cachedTables = box.get(tablesKey);
          if (cachedTables != null) {
            final List<dynamic> tablesList = jsonDecode(cachedTables);
            final tableIdx = tablesList.indexWhere((t) => t['id'] == activeTableId);
            if (tableIdx != -1) {
              tablesList[tableIdx]['status'] = 'free';
              tablesList[tableIdx]['is_occupied'] = false;
              await box.put(tablesKey, jsonEncode(tablesList));
            }
          }
        }

        clearCart();
        activeTableId = null;
        activeOrder = null;
        _setState(PosState.success);
        return true;
      } catch (e) {
        _errorMessage = e.toString();
        _setState(PosState.error);
        return false;
      }
    }

    try {
      final orderId = activeOrder?.id ?? const Uuid().v4();
      final billNumber = activeOrder?.billNumber ?? (DateTime.now().millisecondsSinceEpoch % 1000000);
      final isDue = _paymentMethod.toLowerCase() == 'due';
      final isNewOrder = activeOrder == null;

      final order = OrderModel(
        id: orderId,
        cafeId: cafeId,
        customerId: null,
        tableId: activeTableId,
        waiterId: activeOrder?.waiterId ?? cashierId,
        cashierId: cashierId,
        status: 'completed',
        paymentMethod: _paymentMethod.toLowerCase(),
        type: _mapOrderType(_orderType),
        subtotal: subtotal,
        discount: _discountAmount,
        taxAmount: taxAmount,
        serviceCharge: 0,
        grandTotal: grandTotal,
        billNumber: billNumber,
        createdAt: activeOrder?.createdAt?.toUtc() ?? DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        paymentStatus: isDue ? 'unpaid' : 'paid',
        paidAmount: isDue ? 0.0 : grandTotal,
        remainingDue: isDue ? grandTotal : 0.0,
        paidAt: isDue ? null : DateTime.now().toUtc(),
        completedAt: DateTime.now().toUtc(),
        customerDueId: customerDueId,
      );

      if (isNewOrder) {
        await _client.from('orders').insert(order.toJson()..remove('bill_number'));
        
        final List<OrderItemModel> items = _cart.map((cartItem) {
          return OrderItemModel(
            id: const Uuid().v4(),
            orderId: orderId,
            productId: cartItem.product.id,
            productName: cartItem.product.name,
            quantity: cartItem.quantity.toInt(),
            unitPrice: cartItem.product.sellingPrice,
            totalPrice: cartItem.totalPrice,
            notes: cartItem.note,
            createdAt: DateTime.now().toUtc(),
            status: 'sent',
          );
        }).toList();

        final itemsToInsert = items.map((item) {
          final json = item.toJson();
          json.remove('id');
          return json;
        }).toList();

        await _client.from('order_items').insert(itemsToInsert);

        for (var item in _cart) {
          if (item.product.isStockTracked) {
            try {
              final prodRes = await _client.from('products').select('stock_quantity').eq('id', item.product.id).single();
              final currentStock = (prodRes['stock_quantity'] as num).toInt();
              await _client.from('products').update({'stock_quantity': currentStock - item.quantity.toInt()}).eq('id', item.product.id);

              await _client.from('inventory_movements').insert({
                'cafe_id': cafeId,
                'product_id': item.product.id,
                'movement_type': 'out',
                'quantity': item.quantity.toInt(),
                'reference_id': orderId,
              });
            } catch (e) {
              debugPrint("Inventory deduction error: $e");
            }
          }
        }
      } else {
        await _client
            .from('orders')
            .update(order.toJson()..remove('id')..remove('bill_number'))
            .eq('id', orderId);
      }

      if (isDue && customerDueId != null) {
        final customerDueRes = await _client.from('customer_dues').select('total_due').eq('id', customerDueId).single();
        final currentDue = (customerDueRes['total_due'] as num).toDouble();
        await _client.from('customer_dues').update({
          'total_due': currentDue + grandTotal,
          'last_updated_at': DateTime.now().toIso8601String(),
        }).eq('id', customerDueId);

        await _client.from('notifications').insert({
          'cafe_id': cafeId,
          'recipient_role': 'owner',
          'title': 'Due Payment Logged',
          'message': 'Due payment of Rs. ${grandTotal.toStringAsFixed(2)} logged for order #$billNumber.',
          'type': 'due_payment_received',
          'metadata': {'order_id': orderId},
        });
      }

      if (activeTableId != null) {
        await _client.from('tables').update({
          'status': 'free',
          'is_occupied': false,
        }).eq('id', activeTableId!);
      }

      await _client.from('notifications').insert({
        'cafe_id': cafeId,
        'recipient_role': 'owner',
        'title': 'Order Completed',
        'message': 'Order #$billNumber completed by Cashier for Rs. ${grandTotal.toStringAsFixed(2)}.',
        'type': 'payment_completed',
        'metadata': {'order_id': orderId},
      });

      _lastCompletedOrderItems = _cart.map((cartItem) {
        return OrderItemModel(
          id: const Uuid().v4(),
          orderId: orderId,
          productId: cartItem.product.id,
          productName: cartItem.product.name,
          quantity: cartItem.quantity.toInt(),
          unitPrice: cartItem.product.sellingPrice,
          totalPrice: cartItem.totalPrice,
          notes: cartItem.note,
          createdAt: DateTime.now().toUtc(),
          status: 'sent',
        );
      }).toList();
      _lastCompletedOrder = order;
      _checkLowStockAfterOrder();
      clearCart();
      activeTableId = null;
      activeOrder = null;
      _setState(PosState.success);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _setState(PosState.error);
      return false;
    }
  }

  // Legacy/Default Checkout wrapper (Takeaway/Delivery)
  Future<bool> checkout(String cafeId, String cashierId, {String? customerDueId}) async {
    return finalizePayment(cafeId, cashierId, customerDueId: customerDueId);
  }

  // Write audit logs
  Future<void> _logAudit(String orderId, String action, String? oldValue, String? newValue, String? reason, String staffId) async {
    try {
      await _client.from('order_audit_logs').insert({
        'order_id': orderId,
        'action': action,
        'old_value': oldValue,
        'new_value': newValue,
        'reason': reason,
        'performed_by': staffId,
        'performed_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      debugPrint("Error writing audit log: $e");
    }
  }

  // Restore product stock
  Future<void> _restoreStock(String orderId, String cafeId) async {
    try {
      final itemsRes = await _client.from('order_items').select().eq('order_id', orderId);
      final List items = itemsRes as List;
      for (var item in items) {
        final prodId = item['product_id'] as String?;
        final qty = (item['quantity'] as num).toInt();
        if (prodId != null) {
          final prodRes = await _client.from('products').select().eq('id', prodId).maybeSingle();
          if (prodRes != null && (prodRes['is_stock_tracked'] as bool? ?? false)) {
            final currentStock = (prodRes['stock_quantity'] as num).toInt();
            await _client.from('products').update({'stock_quantity': currentStock + qty}).eq('id', prodId);
            
            // Record inventory movement
            await _client.from('inventory_movements').insert({
              'cafe_id': cafeId,
              'product_id': prodId,
              'movement_type': 'in',
              'quantity': qty,
              'reference_id': orderId,
            });
          }
        }
      }
    } catch (e) {
      debugPrint("Error restoring stock: $e");
    }
  }

  // Void/Refund already paid orders (Cashier/Admin Flow)
  Future<bool> voidRefundOrder(String orderId, String staffId, String actionType, String reason, String cafeId) async {
    _setState(PosState.loading);
    try {
      final orderRes = await _client.from('orders').select().eq('id', orderId).single();
      final oldStatus = orderRes['status'] as String;
      final oldPaymentMethod = orderRes['payment_method'] as String?;
      final grandTotal = (orderRes['grand_total'] as num).toDouble();
      final customerDueId = orderRes['customer_due_id'] as String?;
      final isDue = oldPaymentMethod == 'due';

      final newStatus = actionType.toLowerCase() == 'void' ? 'voided' : 'refunded';
      await _client.from('orders').update({
        'status': newStatus,
        'payment_status': 'refunded',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', orderId);

      await _restoreStock(orderId, cafeId);

      if (isDue && customerDueId != null) {
        final customerDueRes = await _client.from('customer_dues').select('total_due').eq('id', customerDueId).single();
        final currentDue = (customerDueRes['total_due'] as num).toDouble();
        final newDue = (currentDue - grandTotal) > 0 ? (currentDue - grandTotal) : 0.0;
        await _client.from('customer_dues').update({
          'total_due': newDue,
          'last_updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', customerDueId);
      }

      await _logAudit(orderId, actionType.toLowerCase(), oldStatus, newStatus, reason, staffId);

      _setState(PosState.success);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _setState(PosState.error);
      return false;
    }
  }

  // Cancel unpaid order (Waiter/Cashier Flow)
  Future<bool> cancelOrder(String orderId, String staffId, {String? reason}) async {
    _setState(PosState.loading);
    try {
      final orderRes = await _client.from('orders').select().eq('id', orderId).single();
      final oldStatus = orderRes['status'] as String;
      final cafeId = orderRes['cafe_id'] as String;
      final tableId = orderRes['table_id'] as String?;
      final oldPaymentMethod = orderRes['payment_method'] as String?;
      final grandTotal = (orderRes['grand_total'] as num).toDouble();
      final customerDueId = orderRes['customer_due_id'] as String?;
      final isDue = oldPaymentMethod == 'due';

      await _client.from('orders').update({
        'status': 'cancelled',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', orderId);

      if (oldStatus != 'active' && oldStatus != 'pending') {
        await _restoreStock(orderId, cafeId);
      }

      if (isDue && customerDueId != null) {
        final customerDueRes = await _client.from('customer_dues').select('total_due').eq('id', customerDueId).single();
        final currentDue = (customerDueRes['total_due'] as num).toDouble();
        final newDue = (currentDue - grandTotal) > 0 ? (currentDue - grandTotal) : 0.0;
        await _client.from('customer_dues').update({
          'total_due': newDue,
          'last_updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', customerDueId);
      }

      if (tableId != null) {
        await _client.from('tables').update({
          'status': 'free',
          'is_occupied': false,
        }).eq('id', tableId);
      }

      await _logAudit(orderId, 'cancel', oldStatus, 'cancelled', reason ?? 'Cancelled by operator', staffId);

      if (activeOrder?.id == orderId) {
        activeTableId = null;
        activeOrder = null;
        clearCart();
      }

      _setState(PosState.success);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _setState(PosState.error);
      return false;
    }
  }

  // Delete unpaid order (Admin/Owner Flow)
  Future<bool> deleteOrder(String orderId, String staffId, {String? reason}) async {
    _setState(PosState.loading);
    try {
      await _logAudit(orderId, 'delete', null, null, reason ?? 'Deleted by admin', staffId);
      await _client.from('orders').delete().eq('id', orderId);
      _setState(PosState.success);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _setState(PosState.error);
      return false;
    }
  }

  // Modify active/unpaid orders (Waiter/Cashier Flow)
  Future<bool> modifyActiveOrder(String orderId, String staffId, List<CartItem> newCart, double discount, String paymentMethod, {String? newTableId}) async {
    _setState(PosState.loading);
    try {
      final orderRes = await _client.from('orders').select().eq('id', orderId).single();
      final cafeId = orderRes['cafe_id'] as String;
      final oldStatus = orderRes['status'] as String;
      final oldTableId = orderRes['table_id'] as String?;

      final newSubtotal = newCart.fold(0.0, (sum, item) => sum + item.totalPrice);
      final newTaxable = (newSubtotal - discount) > 0 ? (newSubtotal - discount) : 0.0;
      final newTax = newTaxable * _taxRate;
      final newGrandTotal = newTaxable + newTax;

      await _client.from('orders').update({
        'subtotal': newSubtotal,
        'discount': discount,
        'tax_amount': newTax,
        'grand_total': newGrandTotal,
        'payment_method': paymentMethod.toLowerCase(),
        'table_id': newTableId ?? oldTableId,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', orderId);

      await _client.from('order_items').delete().eq('order_id', orderId);

      final List<OrderItemModel> items = newCart.map((cartItem) {
        return OrderItemModel(
          id: const Uuid().v4(),
          orderId: orderId,
          productId: cartItem.product.id,
          productName: cartItem.product.name,
          quantity: cartItem.quantity.toInt(),
          unitPrice: cartItem.product.sellingPrice,
          totalPrice: cartItem.totalPrice,
          notes: cartItem.note,
          createdAt: DateTime.now().toUtc(),
        );
      }).toList();

      final itemsToInsert = items.map((item) {
        final json = item.toJson();
        json.remove('id');
        return json;
      }).toList();

      await _client.from('order_items').insert(itemsToInsert);

      if (newTableId != null && newTableId != oldTableId) {
        if (oldTableId != null) {
          await _client.from('tables').update({'status': 'free', 'is_occupied': false}).eq('id', oldTableId);
        }
        await _client.from('tables').update({'status': 'occupied', 'is_occupied': true}).eq('id', newTableId);
      }

      await _logAudit(orderId, 'modify_item', oldStatus, oldStatus, 'Order items modified', staffId);

      _setState(PosState.success);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _setState(PosState.error);
      return false;
    }
  }

  void _checkLowStockAfterOrder() {
    for (var item in _cart) {
      if (item.product.isStockTracked) {
        final remaining = item.product.stockQuantity - item.quantity.toInt();
        if (remaining <= 10 && remaining >= 0) {
          NotificationService().showLowStockAlert(item.product.name, remaining);
        }
      }
    }
  }

  void _setState(PosState newState) {
    _state = newState;
    notifyListeners();
  }

  String _mapOrderType(String type) {
    switch (type.toLowerCase()) {
      case 'dine-in':
      case 'dine_in':
        return 'dine_in';
      case 'takeaway':
        return 'takeaway';
      case 'delivery':
        return 'delivery';
      default:
        return 'dine_in';
    }
  }

  String _restorePaymentMethod(String? dbMethod) {
    if (dbMethod == null) return 'Cash';
    switch (dbMethod) {
      case 'cash':
        return 'Cash';
      case 'qr':
        return 'QR';
      case 'card':
        return 'Card';
      case 'due':
        return 'Due';
      case 'mixed':
        return 'Mixed';
      default:
        return 'Cash';
    }
  }

  String _restoreOrderType(String type) {
    switch (type.toLowerCase()) {
      case 'dine_in':
      case 'dine-in':
        return 'Dine-in';
      case 'takeaway':
        return 'Takeaway';
      case 'delivery':
        return 'Delivery';
      default:
        return 'Dine-in';
    }
  }

  Future<bool> loadOrderForEditing(String orderId, String cafeId, String userRole) async {
    _setState(PosState.loading);
    try {
      // 1. Scan offline_orders box first to load offline order details & items
      final offlineBox = Hive.box('offline_orders');
      Map<String, dynamic>? offlineOrderData;
      for (var key in offlineBox.keys) {
        try {
          final orderJsonString = offlineBox.get(key);
          if (orderJsonString != null) {
            final Map<String, dynamic> data = jsonDecode(orderJsonString);
            final orderJson = data['order'] as Map<String, dynamic>;
            if (orderJson['id'] == orderId) {
              offlineOrderData = data;
              break;
            }
          }
        } catch (_) {}
      }

      if (offlineOrderData != null) {
        final orderJson = offlineOrderData['order'];
        activeOrder = OrderModel.fromJson(orderJson);
        activeTableId = activeOrder!.tableId;
        _discountAmount = activeOrder!.discount;
        _paymentMethod = _restorePaymentMethod(activeOrder!.paymentMethod);
        _orderType = _restoreOrderType(activeOrder!.type);

        final List itemsJson = offlineOrderData['items'] ?? [];
        final List<OrderItemModel> items = itemsJson.map((i) => OrderItemModel.fromJson(i)).toList();

        _cart.clear();
        final box = Hive.box('cache');
        final cacheKey = 'products_$cafeId';
        final cachedData = box.get(cacheKey);
        List<dynamic> cachedProducts = [];
        if (cachedData != null) {
          try {
            cachedProducts = jsonDecode(cachedData);
          } catch (_) {}
        }

        for (var item in items) {
          final prodIndex = cachedProducts.indexWhere((p) => p['id'] == item.productId);
          ProductModel product;
          if (prodIndex != -1) {
            product = ProductModel.fromJson(cachedProducts[prodIndex]);
          } else {
            product = ProductModel(
              id: item.productId ?? '',
              cafeId: cafeId,
              name: item.productName,
              sellingPrice: item.unitPrice,
              costPrice: item.unitPrice,
              stockQuantity: 9999,
              isAvailable: true,
              isStockTracked: false,
              categoryId: 'Food',
            );
          }

          final cartItem = CartItem(product: product)
            ..quantity = item.quantity.toDouble()
            ..note = item.notes ?? '';
          _cart.add(cartItem);
        }

        _setState(PosState.success);
        return true;
      }

      final orderResponse = await _client
          .from('orders')
          .select('*, waiter:profiles!waiter_id(full_name), table:tables!table_id(name)')
          .eq('id', orderId)
          .single();

      activeOrder = OrderModel.fromJson(orderResponse);
      activeTableId = activeOrder!.tableId;
      _discountAmount = activeOrder!.discount;
      _paymentMethod = _restorePaymentMethod(activeOrder!.paymentMethod);
      _orderType = _restoreOrderType(activeOrder!.type);

      // Fetch items for this order
      final itemsRes = await _client
          .from('order_items')
          .select()
          .eq('order_id', orderId);

      final List<OrderItemModel> items = (itemsRes as List)
          .map((json) => OrderItemModel.fromJson(json))
          .toList();

      _cart.clear();
      for (var item in items) {
        final productRes = await _client
            .from('products')
            .select()
            .eq('id', item.productId ?? '')
            .maybeSingle();

        ProductModel product;
        if (productRes != null) {
          product = ProductModel.fromJson(productRes);
        } else {
          product = ProductModel(
            id: item.productId ?? '',
            cafeId: cafeId,
            name: item.productName,
            sellingPrice: item.unitPrice,
            costPrice: item.unitPrice,
            stockQuantity: 9999,
            isAvailable: true,
            isStockTracked: false,
            categoryId: 'Food',
          );
        }

        final cartItem = CartItem(product: product)
          ..quantity = item.quantity.toDouble()
          ..note = item.notes ?? '';
        _cart.add(cartItem);
      }

      // Subscribe to active order changes and fetch timeline
      _subscribeToActiveOrder(activeOrder!.id);
      await fetchOrderStatusHistory(activeOrder!.id);

      _setState(PosState.success);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _setState(PosState.error);
      return false;
    }
  }

  @override
  void dispose() {
    _orderSubscription?.cancel();
    _historySubscription?.cancel();
    super.dispose();
  }
}
