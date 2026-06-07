import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter/foundation.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// NotificationService
///   - Singleton that wraps flutter_local_notifications v21+
///   - Creates 5 separate Android notification channels per role/workflow
///   - Requests POST_NOTIFICATIONS permission at runtime (Android 13+)
///   - Provides typed helper methods for every workflow event
/// ─────────────────────────────────────────────────────────────────────────────
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  // ── Channel IDs ─────────────────────────────────────────────────────────────
  static const String _chKot      = 'cafe_kot';
  static const String _chKitchen  = 'cafe_kitchen';
  static const String _chBilling  = 'cafe_billing';
  static const String _chAdmin    = 'cafe_admin';
  static const String _chSystem   = 'cafe_system';

  // ── Notification IDs (unique per type to allow update-in-place) ──────────────
  static const int _idKot                  = 100;
  static const int _idItemAdded            = 101;
  static const int _idItemCancelled        = 102;
  static const int _idOrderCancelled       = 103;
  static const int _idKitchenPreparing     = 200;
  static const int _idKitchenReady         = 201;
  static const int _idReadyToServe         = 202;
  static const int _idBillingPending       = 300;
  static const int _idOrderReadyForBilling = 301;
  static const int _idDuePaymentReceived   = 302;
  static const int _idReceiptPrintFailed   = 303;
  static const int _idLowStock             = 400;
  static const int _idLargeDiscount        = 401;
  static const int _idOrderVoided          = 402;
  static const int _idDailySummary         = 403;
  static const int _idSyncFailed           = 500;
  static const int _idPrinterDisconnected  = 501;
  static const int _idNewCafe              = 600;
  static const int _idSubscriptionExpiring = 601;
  static const int _idCafeSuspended        = 602;
  static const int _idTest                 = 999;

  /// ── Initialization ──────────────────────────────────────────────────────────
  Future<void> init() async {
    if (_isInitialized || kIsWeb) return;

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings darwinSettings =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
    );

    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    // Create Android notification channels
    await _createChannels();

    _isInitialized = true;
  }

  /// Create all notification channels on Android (no-op on iOS)
  Future<void> _createChannels() async {
    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return;

    // Note: Color() is non-const at runtime, so channels are created as mutable objects
    final channels = [
      AndroidNotificationChannel(
        _chKot,
        'KOT Alerts',
        description: 'New Kitchen Order Tickets - high priority alerts for kitchen staff',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        enableLights: true,
        ledColor: const Color(0xFFFF6B00),
      ),
      AndroidNotificationChannel(
        _chKitchen,
        'Kitchen Status',
        description: 'Order preparing, ready to serve notifications for waiters',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        enableLights: true,
        ledColor: const Color(0xFF00C853),
      ),
      AndroidNotificationChannel(
        _chBilling,
        'Billing Alerts',
        description: 'Payment and billing notifications for cashiers',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        enableLights: true,
        ledColor: const Color(0xFF1565C0),
      ),
      const AndroidNotificationChannel(
        _chAdmin,
        'Admin Alerts',
        description: 'Low stock, voids, refunds, and daily summaries for owners',
        importance: Importance.defaultImportance,
        playSound: true,
        enableVibration: false,
      ),
      const AndroidNotificationChannel(
        _chSystem,
        'System Alerts',
        description: 'Sync status, printer, and connectivity alerts',
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
      ),
    ];

    for (final ch in channels) {
      await androidPlugin.createNotificationChannel(ch);
    }
  }

  /// ── Runtime Permission Request (Android 13+ / API 33+) ─────────────────────
  Future<bool> requestPermission() async {
    if (kIsWeb) return false;

    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      final granted = await androidPlugin.requestNotificationsPermission();
      return granted ?? false;
    }

    final iosPlugin =
        _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (iosPlugin != null) {
      final granted = await iosPlugin.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }

    return true; // Other platforms assumed granted
  }

  /// ── Permission Status Check ─────────────────────────────────────────────────
  Future<bool> areNotificationsEnabled() async {
    if (kIsWeb) return false;
    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      return await androidPlugin.areNotificationsEnabled() ?? false;
    }
    return true;
  }

  // ── Notification Response Handler ────────────────────────────────────────────
  void _onNotificationResponse(NotificationResponse response) {
    debugPrint('Notification tapped: ${response.payload}');
  }

  // ── Core Display Method ──────────────────────────────────────────────────────
  Future<void> _show({
    required int id,
    required String title,
    required String body,
    required String channelId,
    String? payload,
  }) async {
    if (!_isInitialized || kIsWeb) return;

    final androidDetails = AndroidNotificationDetails(
      channelId,
      _channelName(channelId),
      channelDescription: _channelDesc(channelId),
      importance: _channelImportance(channelId),
      priority: channelId == _chKot ? Priority.max : Priority.high,
      showWhen: true,
      autoCancel: true,
      styleInformation: BigTextStyleInformation(body),
    );

    final details = NotificationDetails(android: androidDetails);

    // flutter_local_notifications v21+ uses show() with named params:
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload,
    );
  }

  String _channelName(String id) {
    switch (id) {
      case _chKot:      return 'KOT Alerts';
      case _chKitchen:  return 'Kitchen Status';
      case _chBilling:  return 'Billing Alerts';
      case _chAdmin:    return 'Admin Alerts';
      case _chSystem:   return 'System Alerts';
      default:          return 'Café OS';
    }
  }

  String _channelDesc(String id) {
    switch (id) {
      case _chKot:     return 'New Kitchen Order Tickets';
      case _chKitchen: return 'Order status updates for waiters';
      case _chBilling: return 'Payment and billing updates';
      case _chAdmin:   return 'Admin and owner alerts';
      case _chSystem:  return 'System status alerts';
      default:         return 'Café OS notification';
    }
  }

  Importance _channelImportance(String id) {
    switch (id) {
      case _chKot:     return Importance.max;
      case _chKitchen: return Importance.high;
      case _chBilling: return Importance.high;
      case _chAdmin:   return Importance.defaultImportance;
      case _chSystem:  return Importance.low;
      default:         return Importance.defaultImportance;
    }
  }

  // ── Public Generic Method (used as fallback in NotificationProvider) ─────────
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
    String channelId = _chAdmin,
  }) async {
    await _show(id: id, title: title, body: body, channelId: channelId, payload: payload);
  }

  // ════════════════════════════════════════════════════════════════════════════
  // KITCHEN ROLE NOTIFICATIONS
  // ════════════════════════════════════════════════════════════════════════════

  Future<void> showKotReceived(String tableNo, int itemCount) async {
    final cleanTable = tableNo.toLowerCase().startsWith('room') ? tableNo : 'Table $tableNo';
    await _show(
      id: _idKot,
      title: '🍽️ New KOT — $cleanTable',
      body: '$itemCount item(s) sent to kitchen. Start preparing!',
      channelId: _chKot,
      payload: 'kot:$tableNo',
    );
  }

  Future<void> showItemAddedAfterKot(String tableNo, String itemName) async {
    final cleanTable = tableNo.toLowerCase().startsWith('room') ? tableNo : 'Table $tableNo';
    await _show(
      id: _idItemAdded,
      title: '➕ Item Added — $cleanTable',
      body: '"$itemName" was added after KOT. Please prepare this additional item.',
      channelId: _chKot,
      payload: 'item_added:$tableNo',
    );
  }

  Future<void> showItemCancelledAfterKot(String tableNo, String itemName, String reason) async {
    final cleanTable = tableNo.toLowerCase().startsWith('room') ? tableNo : 'Table $tableNo';
    await _show(
      id: _idItemCancelled,
      title: '❌ Item Cancelled — $cleanTable',
      body: '"$itemName" was CANCELLED. Reason: $reason. Stop preparing if not started.',
      channelId: _chKot,
      payload: 'item_cancelled:$tableNo',
    );
  }

  Future<void> showOrderCancelled(String tableNo, String reason) async {
    final cleanTable = tableNo.toLowerCase().startsWith('room') ? tableNo : 'Table $tableNo';
    await _show(
      id: _idOrderCancelled,
      title: '🚫 Order Cancelled — $cleanTable',
      body: 'Full order for $cleanTable was cancelled. Reason: $reason.',
      channelId: _chKot,
      payload: 'order_cancelled:$tableNo',
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // WAITER ROLE NOTIFICATIONS
  // ════════════════════════════════════════════════════════════════════════════

  Future<void> showKitchenPreparing(String tableNo) async {
    final cleanTable = tableNo.toLowerCase().startsWith('room') ? tableNo : 'Table $tableNo';
    await _show(
      id: _idKitchenPreparing,
      title: '👨‍🍳 Kitchen Preparing — $cleanTable',
      body: 'The kitchen has started preparing the order for $cleanTable.',
      channelId: _chKitchen,
      payload: 'preparing:$tableNo',
    );
  }

  Future<void> showKitchenReady(String tableNo) async {
    final cleanTable = tableNo.toLowerCase().startsWith('room') ? tableNo : 'Table $tableNo';
    await _show(
      id: _idKitchenReady,
      title: '✅ Order Ready — $cleanTable',
      body: 'Order for $cleanTable is READY in the kitchen. Please serve now!',
      channelId: _chKitchen,
      payload: 'kitchen_ready:$tableNo',
    );
  }

  Future<void> showReadyToServe(String tableNo) async {
    final cleanTable = tableNo.toLowerCase().startsWith('room') ? tableNo : 'Table $tableNo';
    await _show(
      id: _idReadyToServe,
      title: '🛎️ Ready to Serve — $cleanTable',
      body: 'All items for $cleanTable are ready. Time to serve the customer!',
      channelId: _chKitchen,
      payload: 'ready_to_serve:$tableNo',
    );
  }

  Future<void> showBillingPending(String tableNo, double amount) async {
    final cleanTable = tableNo.toLowerCase().startsWith('room') ? tableNo : 'Table $tableNo';
    await _show(
      id: _idBillingPending,
      title: '🧾 Billing Pending — $cleanTable',
      body: '$cleanTable is requesting the bill. Total: Rs. ${amount.toStringAsFixed(2)}',
      channelId: _chBilling,
      payload: 'billing_pending:$tableNo',
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // CASHIER ROLE NOTIFICATIONS
  // ════════════════════════════════════════════════════════════════════════════

  Future<void> showOrderReadyForBilling(String tableNo, double amount) async {
    final cleanTable = tableNo.toLowerCase().startsWith('room') ? tableNo : 'Table $tableNo';
    await _show(
      id: _idOrderReadyForBilling,
      title: '💳 Ready for Billing — $cleanTable',
      body: '$cleanTable order is served. Amount due: Rs. ${amount.toStringAsFixed(2)}',
      channelId: _chBilling,
      payload: 'ready_for_billing:$tableNo',
    );
  }

  Future<void> showDuePaymentReceived(String customerName, double amount) async {
    await _show(
      id: _idDuePaymentReceived,
      title: '💰 Due Payment Received',
      body: 'Rs. ${amount.toStringAsFixed(2)} received from $customerName.',
      channelId: _chBilling,
      payload: 'due_received:$customerName',
    );
  }

  Future<void> showReceiptPrintFailed(String tableNo) async {
    final cleanTable = tableNo.toLowerCase().startsWith('room') ? tableNo : 'Table $tableNo';
    await _show(
      id: _idReceiptPrintFailed,
      title: '🖨️ Print Failed — $cleanTable',
      body: 'Receipt for $cleanTable could not be printed. Check printer connection.',
      channelId: _chSystem,
    );
  }

  Future<void> showSyncFailed() async {
    await _show(
      id: _idSyncFailed,
      title: '⚠️ Sync Failed',
      body: 'Failed to sync offline orders to the cloud. Will retry automatically.',
      channelId: _chSystem,
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // OWNER / ADMIN ROLE NOTIFICATIONS
  // ════════════════════════════════════════════════════════════════════════════

  Future<void> showLowStockAlert(String productName, int currentStock) async {
    await _show(
      id: _idLowStock,
      title: '📦 Low Stock Alert',
      body: '"$productName" is running low (Remaining: $currentStock). Please restock soon.',
      channelId: _chAdmin,
    );
  }

  Future<void> showLargeDiscountApplied(String orderNo, double discount) async {
    await _show(
      id: _idLargeDiscount,
      title: '🏷️ Large Discount Applied',
      body: 'Order #$orderNo had a discount of Rs. ${discount.toStringAsFixed(2)} applied. Verify.',
      channelId: _chAdmin,
    );
  }

  Future<void> showOrderVoided(String orderNo, String reason) async {
    await _show(
      id: _idOrderVoided,
      title: '🔴 Order Voided — #$orderNo',
      body: 'Order #$orderNo was voided. Reason: $reason. Revenue has been reversed.',
      channelId: _chAdmin,
    );
  }

  Future<void> showDailySalesSummary(double total, int orderCount) async {
    await _show(
      id: _idDailySummary,
      title: '📊 Daily Sales Summary',
      body: 'Today: $orderCount orders | Total Revenue: Rs. ${total.toStringAsFixed(2)}',
      channelId: _chAdmin,
    );
  }

  Future<void> showPrinterDisconnected() async {
    await _show(
      id: _idPrinterDisconnected,
      title: '🖨️ Printer Disconnected',
      body: 'Thermal printer disconnected. Receipts will not print until reconnected.',
      channelId: _chSystem,
    );
  }

  Future<void> showSyncStatus({required bool success, int count = 0}) async {
    if (success) {
      await _show(
        id: _idSyncFailed + 1,
        title: '✅ Sync Completed',
        body: 'Successfully synced $count orders to the cloud.',
        channelId: _chSystem,
      );
    } else {
      await showSyncFailed();
    }
  }

  Future<void> showOfflineWarning() async {
    await _show(
      id: _idSyncFailed + 2,
      title: '📡 Offline Mode Active',
      body: 'You are offline. Orders will be saved locally and synced when reconnected.',
      channelId: _chSystem,
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // SUPER ADMIN NOTIFICATIONS
  // ════════════════════════════════════════════════════════════════════════════

  Future<void> showNewCafeCreated(String cafeName) async {
    await _show(
      id: _idNewCafe,
      title: '🏪 New Café Created',
      body: '"$cafeName" has been successfully created and is now active.',
      channelId: _chAdmin,
    );
  }

  Future<void> showSubscriptionExpiring(String cafeName, int daysLeft) async {
    await _show(
      id: _idSubscriptionExpiring,
      title: '⏰ Subscription Expiring',
      body: '"$cafeName" subscription expires in $daysLeft day(s). Renew to avoid disruption.',
      channelId: _chAdmin,
    );
  }

  Future<void> showSubscriptionOverdue(String cafeName) async {
    await _show(
      id: _idSubscriptionExpiring + 1,
      title: '🔴 Subscription Overdue',
      body: '"$cafeName" subscription is overdue. Services may be suspended soon.',
      channelId: _chAdmin,
    );
  }

  Future<void> showCafeSuspended(String cafeName) async {
    await _show(
      id: _idCafeSuspended,
      title: '🚫 Café Suspended',
      body: '"$cafeName" has been suspended due to overdue subscription.',
      channelId: _chAdmin,
    );
  }

  Future<void> showCafeReactivated(String cafeName) async {
    await _show(
      id: _idCafeSuspended + 1,
      title: '✅ Café Reactivated',
      body: '"$cafeName" has been successfully reactivated.',
      channelId: _chAdmin,
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // TEST NOTIFICATION — for Settings "Send Test Notification" button
  // ════════════════════════════════════════════════════════════════════════════

  Future<void> showTestNotification() async {
    await _show(
      id: _idTest,
      title: '🔔 Test Notification — Café OS',
      body: 'Android notifications are working! KOT, billing, kitchen, '
            'and admin alerts will reach this device correctly.',
      channelId: _chKot,
      payload: 'test',
    );
  }
}
