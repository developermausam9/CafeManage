import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../../core/presentation/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/models/order_model.dart';
import '../../data/models/order_item_model.dart';
import '../providers/pos_provider.dart';
import '../../../home/presentation/pages/dashboard_shell.dart';
import 'receipt_screen.dart';

class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  final _client = Supabase.instance.client;
  List<OrderModel> _orders = [];
  bool _isLoading = false;
  String? _errorMessage;
  bool _isUsingCachedData = false;
  int _pendingSyncCount = 0;

  @override
  void initState() {
    super.initState();
    _loadOrderHistory();
  }

  Future<void> _loadOrderHistory() async {
    final cafeId = context.read<AuthProvider>().cafeId;
    if (cafeId == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _isUsingCachedData = false;
    });

    final cacheBox = Hive.box('cache');
    final cacheKey = 'order_history_$cafeId';

    // 1. Get offline queued orders
    List<OrderModel> pendingOrders = [];
    try {
      final offlineBox = Hive.box('offline_orders');
      for (var key in offlineBox.keys) {
        final orderJsonString = offlineBox.get(key);
        if (orderJsonString != null) {
          final Map<String, dynamic> data = jsonDecode(orderJsonString);
          final orderJson = data['order'] as Map<String, dynamic>;
          // Mark them clearly as pending sync
          final rawOrder = OrderModel.fromJson(orderJson);
          final pendingOrder = rawOrder.copyWith(status: 'pending_sync');
          pendingOrders.add(pendingOrder);
        }
      }
    } catch (e) {
      debugPrint('Error loading pending offline orders: $e');
    }

    try {
      final res = await _client
          .from('orders')
          .select()
          .eq('cafe_id', cafeId)
          .order('created_at', ascending: false);

      final onlineOrders = (res as List).map((json) => OrderModel.fromJson(json)).toList();
      
      // Cache the loaded history
      await cacheBox.put(cacheKey, jsonEncode(res));

      if (mounted) {
        setState(() {
          _orders = [...pendingOrders, ...onlineOrders];
          _pendingSyncCount = pendingOrders.length;
          _isUsingCachedData = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading order history online, falling back to cache: $e');
      // Offline fallback: load cached history
      final cachedData = cacheBox.get(cacheKey);
      List<OrderModel> cachedOrders = [];
      if (cachedData != null) {
        final List<dynamic> jsonList = jsonDecode(cachedData);
        cachedOrders = jsonList.map((json) => OrderModel.fromJson(json)).toList();
      }
      if (mounted) {
        setState(() {
          _orders = [...pendingOrders, ...cachedOrders];
          _pendingSyncCount = pendingOrders.length;
          _isUsingCachedData = true;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _viewReceipt(OrderModel order) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text('Loading receipt details...', style: TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );

    // 1. Check if it is a pending offline order
    final offlineBox = Hive.box('offline_orders');
    List<OrderItemModel>? offlineItems;
    try {
      for (var key in offlineBox.keys) {
        final orderJsonString = offlineBox.get(key);
        if (orderJsonString != null) {
          final Map<String, dynamic> data = jsonDecode(orderJsonString);
          final orderJson = data['order'] as Map<String, dynamic>;
          if (orderJson['id'] == order.id) {
            final itemsJson = (data['items'] as List).cast<Map<String, dynamic>>();
            offlineItems = itemsJson.map((json) => OrderItemModel.fromJson(json)).toList();
            break;
          }
        }
      }
    } catch (e) {
      debugPrint('Error scanning offline box for receipt: $e');
    }

    if (offlineItems != null) {
      if (mounted) {
        Navigator.pop(context); // Pop loading dialog
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ReceiptScreen(
              order: order,
              items: offlineItems!,
            ),
          ),
        );
      }
      return;
    }

    final cacheBox = Hive.box('cache');
    final cacheKey = 'order_items_${order.id}';

    try {
      final res = await _client.from('order_items').select().eq('order_id', order.id);
      final items = (res as List).map((json) => OrderItemModel.fromJson(json)).toList();

      // Cache it
      await cacheBox.put(cacheKey, jsonEncode(res));

      if (mounted) {
        Navigator.pop(context); // Pop loading dialog
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ReceiptScreen(
              order: order,
              items: items,
            ),
          ),
        );
      }
    } catch (e) {
      // Fallback to cached items
      final cachedData = cacheBox.get(cacheKey);
      if (cachedData != null) {
        final List<dynamic> jsonList = jsonDecode(cachedData);
        final items = jsonList.map((json) => OrderItemModel.fromJson(json)).toList();
        if (mounted) {
          Navigator.pop(context); // Pop loading dialog
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ReceiptScreen(
                order: order,
                items: items,
              ),
            ),
          );
        }
      } else {
        if (mounted) {
          Navigator.pop(context); // Pop loading dialog
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to load receipt details: $e'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  Future<void> _editOrder(BuildContext context, OrderModel order, String cafeId, String userRole) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    final success = await context.read<PosProvider>().loadOrderForEditing(order.id, cafeId, userRole);

    if (mounted) {
      Navigator.pop(context); // Pop loading spinner
      if (success) {
        final shellState = context.findAncestorStateOfType<DashboardShellState>();
        if (shellState != null) {
          shellState.switchToTab('POS');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Order loaded into POS for editing'), backgroundColor: Colors.green),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Order loaded, please switch to POS tab to edit'), backgroundColor: Colors.green),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load order for editing: ${context.read<PosProvider>().errorMessage}'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _showCancelDialog(BuildContext context, OrderModel order, String profileId) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Order', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to cancel Order #${order.billNumber ?? order.id.substring(0, 8)}?'),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason for Cancellation',
                border: OutlineInputBorder(),
                hintText: 'Enter reason...',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No, Keep Order'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, Cancel Order'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final reason = reasonController.text.trim();
      if (reason.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cancellation reason is required'), backgroundColor: Colors.orange),
        );
        return;
      }

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(child: CircularProgressIndicator()),
      );

      final success = await context.read<PosProvider>().cancelOrder(order.id, profileId, reason: reason);
      
      if (mounted) {
        Navigator.pop(context); // Pop loading spinner
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Order cancelled successfully'), backgroundColor: Colors.green),
          );
          _loadOrderHistory();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to cancel order: ${context.read<PosProvider>().errorMessage}'), backgroundColor: Colors.redAccent),
          );
        }
      }
    }
  }

  Future<void> _showDeleteDialog(BuildContext context, OrderModel order, String profileId) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Order Permanently', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to permanently delete Order #${order.billNumber ?? order.id.substring(0, 8)}? This action CANNOT be undone.'),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason for Deletion',
                border: OutlineInputBorder(),
                hintText: 'Enter reason...',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final reason = reasonController.text.trim();
      if (reason.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Deletion reason is required'), backgroundColor: Colors.orange),
        );
        return;
      }

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(child: CircularProgressIndicator()),
      );

      final success = await context.read<PosProvider>().deleteOrder(order.id, profileId, reason: reason);
      
      if (mounted) {
        Navigator.pop(context); // Pop loading spinner
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Order deleted permanently'), backgroundColor: Colors.green),
          );
          _loadOrderHistory();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete order: ${context.read<PosProvider>().errorMessage}'), backgroundColor: Colors.redAccent),
          );
        }
      }
    }
  }

  Future<void> _showVoidRefundDialog(BuildContext context, OrderModel order, String profileId, String cafeId) async {
    final reasonController = TextEditingController();
    String actionType = 'Void'; // Default

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Void / Refund Paid Order', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Correct or reverse payment for Order #${order.billNumber ?? order.id.substring(0, 8)}:'),
              const SizedBox(height: 16),
              const Text('Select Action Type:', style: TextStyle(fontWeight: FontWeight.w600)),
              Row(
                children: [
                  Radio<String>(
                    value: 'Void',
                    groupValue: actionType,
                    onChanged: (val) => setDialogState(() => actionType = val!),
                  ),
                  const Text('Void (Correction)'),
                  const SizedBox(width: 16),
                  Radio<String>(
                    value: 'Refund',
                    groupValue: actionType,
                    onChanged: (val) => setDialogState(() => actionType = val!),
                  ),
                  const Text('Refund'),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(
                  labelText: 'Reason for Void/Refund',
                  border: OutlineInputBorder(),
                  hintText: 'Enter reason...',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Confirm $actionType'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      final reason = reasonController.text.trim();
      if (reason.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reason is required for Void/Refund'), backgroundColor: Colors.orange),
        );
        return;
      }

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(child: CircularProgressIndicator()),
      );

      final success = await context.read<PosProvider>().voidRefundOrder(
        order.id,
        profileId,
        actionType,
        reason,
        cafeId,
      );
      
      if (mounted) {
        Navigator.pop(context); // Pop loading spinner
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Order $actionType completed successfully'), backgroundColor: Colors.green),
          );
          _loadOrderHistory();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to void/refund: ${context.read<PosProvider>().errorMessage}'), backgroundColor: Colors.redAccent),
          );
        }
      }
    }
  }

  Widget _buildPaymentStatusBadge(OrderModel order) {
    final status = order.paymentStatus?.toLowerCase() ?? (order.paymentMethod == 'due' ? 'unpaid' : 'paid');
    
    Color bgColor;
    Color textColor;
    String label;
    IconData icon;
    
    switch (status) {
      case 'paid':
        bgColor = Colors.green.shade50;
        textColor = Colors.green.shade700;
        label = 'Paid';
        icon = Icons.check_circle_outline;
        break;
      case 'partial':
        bgColor = Colors.orange.shade50;
        textColor = Colors.orange.shade900;
        label = 'Partial Due';
        icon = Icons.pending_outlined;
        break;
      case 'unpaid':
      case 'unpaid due':
        bgColor = Colors.red.shade50;
        textColor = Colors.red.shade700;
        label = 'Unpaid Due';
        icon = Icons.error_outline;
        break;
      case 'refunded':
        bgColor = Colors.purple.shade50;
        textColor = Colors.purple.shade700;
        label = 'Refunded';
        icon = Icons.undo;
        break;
      default:
        bgColor = Colors.grey.shade50;
        textColor = Colors.grey.shade700;
        label = status.toUpperCase();
        icon = Icons.help_outline;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: textColor.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: textColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderStatusBadge(OrderModel order) {
    final status = order.status.toLowerCase();
    
    Color bgColor;
    Color textColor;
    String label;
    IconData icon;
    
    switch (status) {
      case 'pending_sync':
        bgColor = Colors.amber.shade100;
        textColor = Colors.amber.shade900;
        label = 'Pending Sync';
        icon = Icons.cloud_upload_outlined;
        break;
      case 'active':
        bgColor = Colors.blue.shade50;
        textColor = Colors.blue.shade700;
        label = 'Active';
        icon = Icons.hourglass_empty;
        break;
      case 'kitchen_sent':
        bgColor = Colors.amber.shade50;
        textColor = Colors.amber.shade900;
        label = 'KOT Sent';
        icon = Icons.soup_kitchen_outlined;
        break;
      case 'ready':
        bgColor = Colors.teal.shade50;
        textColor = Colors.teal.shade700;
        label = 'Ready';
        icon = Icons.restaurant;
        break;
      case 'served':
        bgColor = Colors.indigo.shade50;
        textColor = Colors.indigo.shade700;
        label = 'Served';
        icon = Icons.room_service_outlined;
        break;
      case 'billed':
        bgColor = Colors.orange.shade50;
        textColor = Colors.orange.shade700;
        label = 'Billed';
        icon = Icons.receipt;
        break;
      case 'paid':
      case 'completed':
        bgColor = Colors.green.shade50;
        textColor = Colors.green.shade700;
        label = 'Paid';
        icon = Icons.payments_outlined;
        break;
      case 'cancelled':
        bgColor = Colors.grey.shade100;
        textColor = Colors.grey.shade600;
        label = 'Cancelled';
        icon = Icons.cancel_outlined;
        break;
      case 'voided':
        bgColor = Colors.red.shade50;
        textColor = Colors.red.shade700;
        label = 'Voided';
        icon = Icons.block;
        break;
      case 'refunded':
        bgColor = Colors.purple.shade50;
        textColor = Colors.purple.shade700;
        label = 'Refunded';
        icon = Icons.undo;
        break;
      default:
        bgColor = Colors.grey.shade50;
        textColor = Colors.grey.shade700;
        label = status.toUpperCase();
        icon = Icons.help_outline;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: textColor.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: textColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final profileId = auth.currentProfile?.id ?? '';
    final role = auth.currentProfile?.role?.toLowerCase() ?? '';
    final cafeId = auth.currentProfile?.cafeId;

    final isMobile = MediaQuery.of(context).size.width <= 600;

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header section
          Container(
            padding: const EdgeInsets.all(24),
            color: Colors.white,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Order History',
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                      ),
                      if (!isMobile) ...[
                        const SizedBox(height: 4),
                        Text(
                          'View completed sales invoices and reprint receipts.',
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                  onPressed: _loadOrderHistory,
                ),
              ],
            ),
          ),

          // Main list section
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadOrderHistory,
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                      ? SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: Container(
                            height: MediaQuery.of(context).size.height - 200,
                            alignment: Alignment.center,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                                const SizedBox(height: 16),
                                Text('Error: $_errorMessage', style: const TextStyle(color: Colors.redAccent)),
                                const SizedBox(height: 16),
                                ElevatedButton(onPressed: _loadOrderHistory, child: const Text('Retry')),
                              ],
                            ),
                          ),
                        )
                      : _orders.isEmpty
                          ? SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              child: Container(
                                height: MediaQuery.of(context).size.height - 200,
                                alignment: Alignment.center,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _isUsingCachedData ? Icons.wifi_off : Icons.history,
                                      color: AppTheme.textSecondary,
                                      size: 64,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      _isUsingCachedData
                                          ? 'No offline data available yet.'
                                          : 'No completed sales found.',
                                      style: const TextStyle(fontSize: 18, color: AppTheme.textSecondary, fontWeight: FontWeight.w600),
                                    ),
                                    if (_isUsingCachedData) ...[
                                      const SizedBox(height: 8),
                                      const Text(
                                        'Connect internet once to sync.',
                                        style: TextStyle(color: AppTheme.textSecondary),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            )
                          : Column(
                              children: [
                                // Offline cache banner
                                if (_isUsingCachedData)
                                  Container(
                                    margin: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.shade50,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: Colors.amber.shade300),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.history, size: 16, color: Colors.amber.shade800),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            _pendingSyncCount > 0
                                                ? 'Offline mode — $_pendingSyncCount order(s) pending sync. Showing cached history.'
                                                : 'Showing cached offline data — go online to refresh.',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.amber.shade900,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                Expanded(
                                  child: ListView.builder(
                                    physics: const AlwaysScrollableScrollPhysics(),
                                    padding: const EdgeInsets.all(24),
                                    itemCount: _orders.length,
                                    itemBuilder: (context, index) {
                                      final order = _orders[index];
                                      final formattedDate = order.createdAt != null
                                          ? order.createdAt!.toLocal().toString().substring(0, 16)
                                          : 'N/A';

                                      final bool isPendingSync = order.status == 'pending_sync';
                                      final bool isUnpaid = !isPendingSync &&
                                          order.status != 'paid' &&
                                          order.status != 'completed' &&
                                          order.status != 'cancelled' &&
                                          order.status != 'voided' &&
                                          order.status != 'refunded';
                                      
                                      final bool isPaid = order.status == 'paid' || order.status == 'completed';
                                      final bool isCancelledOrVoided = order.status == 'cancelled' ||
                                          order.status == 'voided' ||
                                          order.status == 'refunded';

                                      final bool canEdit = isUnpaid && (role == 'owner' || role == 'admin' || role == 'cashier' || role == 'waiter');
                                      final bool canCancel = isUnpaid && (role == 'owner' || role == 'admin' || role == 'cashier');
                                      final bool canDelete = (isUnpaid || order.status == 'cancelled') && (role == 'owner' || role == 'admin');
                                      final bool canVoidRefund = isPaid && (role == 'owner' || role == 'admin');
                                      final bool canReprint = isPaid || isCancelledOrVoided;

                                      final bool hasActions = canEdit || canCancel || canDelete || canVoidRefund || canReprint;

                                      return Card(
                                        margin: const EdgeInsets.only(bottom: 16),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          side: BorderSide(color: Colors.grey.shade200, width: 1),
                                        ),
                                        elevation: 0,
                                        borderOnForeground: true,
                                        child: Padding(
                                          padding: const EdgeInsets.all(16.0),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.stretch,
                                            children: [
                                              Row(
                                                children: [
                                                  // Left side: Status badge & Bill Info
                                                  Container(
                                                    padding: const EdgeInsets.all(12),
                                                    decoration: BoxDecoration(
                                                      color: isPendingSync
                                                          ? Colors.amber.shade50
                                                          : (order.status == 'completed' || order.status == 'paid'
                                                              ? Colors.green.shade50
                                                              : (order.status == 'cancelled' || order.status == 'voided' || order.status == 'refunded'
                                                                  ? Colors.red.shade50
                                                                  : Colors.blue.shade50)),
                                                      borderRadius: BorderRadius.circular(8),
                                                    ),
                                                    child: Icon(
                                                      isPendingSync
                                                          ? Icons.cloud_upload_outlined
                                                          : (order.status == 'completed' || order.status == 'paid'
                                                              ? Icons.check_circle_outline
                                                              : (order.status == 'cancelled' || order.status == 'voided' || order.status == 'refunded'
                                                                  ? Icons.cancel_outlined
                                                                  : Icons.receipt_long)),
                                                      color: isPendingSync
                                                          ? Colors.amber.shade800
                                                          : (order.status == 'completed' || order.status == 'paid'
                                                              ? Colors.green.shade700
                                                              : (order.status == 'cancelled' || order.status == 'voided' || order.status == 'refunded'
                                                                  ? Colors.red.shade700
                                                                  : Colors.blue.shade700)),
                                                      size: 24,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 16),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Row(
                                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                          children: [
                                                            Text(
                                                              'Bill #${order.billNumber ?? order.id.substring(0, 8)}',
                                                              style: const TextStyle(
                                                                fontWeight: FontWeight.bold,
                                                                fontSize: 16,
                                                              ),
                                                            ),
                                                            _buildOrderStatusBadge(order),
                                                          ],
                                                        ),
                                                        const SizedBox(height: 4),
                                                        Row(
                                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                          children: [
                                                            Text(
                                                              formattedDate,
                                                              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                                            ),
                                                            _buildPaymentStatusBadge(order),
                                                          ],
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const Divider(height: 24),
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Text(
                                                    'Type: ${order.type.toUpperCase()}',
                                                    style: TextStyle(
                                                      color: Colors.grey.shade700,
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                  ),
                                                  Text(
                                                    'Rs. ${order.grandTotal.toStringAsFixed(2)}',
                                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                                                  ),
                                                ],
                                              ),
                                              if (hasActions) ...[
                                                const Divider(height: 24),
                                                Row(
                                                  mainAxisAlignment: MainAxisAlignment.end,
                                                  children: [
                                                    if (canEdit) ...[
                                                      OutlinedButton.icon(
                                                        style: OutlinedButton.styleFrom(
                                                          foregroundColor: Colors.blue.shade700,
                                                          side: BorderSide(color: Colors.blue.shade200),
                                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                        ),
                                                        icon: const Icon(Icons.edit, size: 16),
                                                        label: const Text('Edit Order', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                                        onPressed: () => _editOrder(context, order, cafeId!, role),
                                                      ),
                                                      const SizedBox(width: 8),
                                                    ],
                                                    if (canCancel) ...[
                                                      OutlinedButton.icon(
                                                        style: OutlinedButton.styleFrom(
                                                          foregroundColor: Colors.orange.shade800,
                                                          side: BorderSide(color: Colors.orange.shade200),
                                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                        ),
                                                        icon: const Icon(Icons.cancel_outlined, size: 16),
                                                        label: const Text('Cancel', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                                        onPressed: () => _showCancelDialog(context, order, profileId),
                                                      ),
                                                      const SizedBox(width: 8),
                                                    ],
                                                    if (canDelete) ...[
                                                      OutlinedButton.icon(
                                                        style: OutlinedButton.styleFrom(
                                                          foregroundColor: Colors.red.shade700,
                                                          side: BorderSide(color: Colors.red.shade200),
                                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                        ),
                                                        icon: const Icon(Icons.delete_forever, size: 16),
                                                        label: const Text('Delete', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                                        onPressed: () => _showDeleteDialog(context, order, profileId),
                                                      ),
                                                      const SizedBox(width: 8),
                                                    ],
                                                    if (canVoidRefund) ...[
                                                      OutlinedButton.icon(
                                                        style: OutlinedButton.styleFrom(
                                                          foregroundColor: Colors.purple.shade700,
                                                          side: BorderSide(color: Colors.purple.shade200),
                                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                        ),
                                                        icon: const Icon(Icons.undo, size: 16),
                                                        label: const Text('Void / Refund', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                                        onPressed: () => _showVoidRefundDialog(context, order, profileId, cafeId!),
                                                      ),
                                                      const SizedBox(width: 8),
                                                    ],
                                                    if (canReprint) ...[
                                                      ElevatedButton.icon(
                                                        style: ElevatedButton.styleFrom(
                                                          elevation: 0,
                                                          backgroundColor: AppTheme.primaryColor.withOpacity(0.1),
                                                          foregroundColor: AppTheme.primaryColor,
                                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                        ),
                                                        icon: const Icon(Icons.receipt_long, size: 16),
                                                        label: const Text('Reprint / Receipt', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                                        onPressed: () => _viewReceipt(order),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
            ),
          ),
        ],
      ),
    );
  }
}
