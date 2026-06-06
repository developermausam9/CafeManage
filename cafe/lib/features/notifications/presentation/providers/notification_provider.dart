import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/network/supabase_config.dart';
import '../../../../core/services/notification_service.dart';
import '../../data/models/notification_model.dart';

class NotificationProvider extends ChangeNotifier {
  final SupabaseClient _client = SupabaseConfig.client;

  List<NotificationModel> _notifications = [];
  List<NotificationModel> get notifications => _notifications;

  int _unreadCount = 0;
  int get unreadCount => _unreadCount;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _userId;
  String? _role;
  String? _cafeId;
  StreamSubscription? _subscription;
  final Set<String> _localKnownIds = {};

  void init(String cafeId, String userId, String role) {
    _cafeId = cafeId;
    _userId = userId;
    _role = role;
    _localKnownIds.clear();
    _subscribeToNotifications(cafeId, userId, role);
  }

  void _subscribeToNotifications(String cafeId, String userId, String role) {
    _subscription?.cancel();
    _subscription = _client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('cafe_id', cafeId)
        .listen((data) {
          final list = data.map((json) => NotificationModel.fromJson(json)).toList();
          
          // Filter matching the current user or their role
          final filtered = list.where((n) {
            final matchUser = n.recipientUserId == userId;
            final matchRole = n.recipientRole?.toLowerCase() == role.toLowerCase();
            return matchUser || matchRole;
          }).toList();

          // Sort descending by date
          filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));

          // Trigger device push notification for new unread items
          for (var n in filtered) {
            if (!n.isRead && !_localKnownIds.contains(n.id)) {
              _localKnownIds.add(n.id);
              _dispatchSystemNotification(n);
            } else if (n.isRead) {
              _localKnownIds.add(n.id); // skip already-read ones
            }
          }

          _notifications = filtered;
          _unreadCount = filtered.where((n) => !n.isRead).length;
          notifyListeners();
        }, onError: (err) {
          debugPrint("Realtime notifications stream error: $err");
        });
  }

  /// Routes each notification type to the correct channel-specific helper.
  void _dispatchSystemNotification(NotificationModel n) {
    final svc = NotificationService();
    final meta = n.metadata;
    final tableNo = meta['table_no']?.toString() ?? meta['table']?.toString() ?? '?';
    final amount = double.tryParse(meta['amount']?.toString() ?? '0') ?? 0;
    final reason = meta['reason']?.toString() ?? '';
    final itemName = meta['item_name']?.toString() ?? '';
    final count = int.tryParse(meta['item_count']?.toString() ?? '1') ?? 1;

    switch (n.type.toLowerCase()) {
      case 'kot_received':
        svc.showKotReceived(tableNo, count);
        break;
      case 'item_added_after_kot':
        svc.showItemAddedAfterKot(tableNo, itemName);
        break;
      case 'item_cancelled_after_kot':
        svc.showItemCancelledAfterKot(tableNo, itemName, reason);
        break;
      case 'order_cancelled':
        svc.showOrderCancelled(tableNo, reason);
        break;
      case 'preparing':
        svc.showKitchenPreparing(tableNo);
        break;
      case 'kitchen_ready':
        svc.showKitchenReady(tableNo);
        break;
      case 'table_ready_for_serving':
        svc.showReadyToServe(tableNo);
        break;
      case 'billing_pending':
        svc.showBillingPending(tableNo, amount);
        break;
      case 'table_ready_for_billing':
        svc.showOrderReadyForBilling(tableNo, amount);
        break;
      case 'due_payment_received':
        final name = meta['customer_name']?.toString() ?? 'Customer';
        svc.showDuePaymentReceived(name, amount);
        break;
      case 'receipt_print_failed':
        svc.showReceiptPrintFailed(tableNo);
        break;
      case 'sync_failed':
        svc.showSyncFailed();
        break;
      case 'low_stock':
      case 'stock_alert':
        final product = meta['product_name']?.toString() ?? n.title;
        final stock = int.tryParse(meta['current_stock']?.toString() ?? '0') ?? 0;
        svc.showLowStockAlert(product, stock);
        break;
      case 'large_discount':
        final orderNo = meta['order_no']?.toString() ?? '';
        svc.showLargeDiscountApplied(orderNo, amount);
        break;
      case 'order_voided':
      case 'refund':
        final orderNo = meta['order_no']?.toString() ?? '';
        svc.showOrderVoided(orderNo, reason);
        break;
      case 'daily_summary':
        final orderCount = int.tryParse(meta['order_count']?.toString() ?? '0') ?? 0;
        svc.showDailySalesSummary(amount, orderCount);
        break;
      case 'printer_disconnected':
        svc.showPrinterDisconnected();
        break;
      case 'new_cafe_created':
        final cafeName = meta['cafe_name']?.toString() ?? '';
        svc.showNewCafeCreated(cafeName);
        break;
      case 'subscription_expiring':
        final cafeName = meta['cafe_name']?.toString() ?? '';
        final days = int.tryParse(meta['days_left']?.toString() ?? '0') ?? 0;
        svc.showSubscriptionExpiring(cafeName, days);
        break;
      case 'subscription_overdue':
        final cafeName = meta['cafe_name']?.toString() ?? '';
        svc.showSubscriptionOverdue(cafeName);
        break;
      case 'cafe_suspended':
        final cafeName = meta['cafe_name']?.toString() ?? '';
        svc.showCafeSuspended(cafeName);
        break;
      case 'cafe_reactivated':
        final cafeName = meta['cafe_name']?.toString() ?? '';
        svc.showCafeReactivated(cafeName);
        break;
      default:
        // Fallback: generic notification on admin channel
        svc.showNotification(
          id: n.id.hashCode,
          title: n.title,
          body: n.message,
          channelId: 'cafe_admin',
        );
    }
  }

  Future<void> markAsRead(String id) async {
    try {
      await _client.from('notifications').update({'is_read': true}).eq('id', id);
    } catch (e) {
      debugPrint("Error marking notification as read: $e");
    }
  }

  Future<void> markAllAsRead() async {
    try {
      final unread = _notifications.where((n) => !n.isRead).toList();
      for (var n in unread) {
        await _client.from('notifications').update({'is_read': true}).eq('id', n.id);
      }
    } catch (e) {
      debugPrint("Error marking all as read: $e");
    }
  }

  Future<void> sendNotification({
    required String cafeId,
    String? recipientUserId,
    String? recipientRole,
    required String title,
    required String message,
    required String type,
    Map<String, dynamic> metadata = const {},
  }) async {
    try {
      await _client.from('notifications').insert({
        'cafe_id': cafeId,
        'recipient_user_id': recipientUserId,
        'recipient_role': recipientRole,
        'title': title,
        'message': message,
        'type': type,
        'metadata': metadata,
      });
    } catch (e) {
      debugPrint("Error sending notification: $e");
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
