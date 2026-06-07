import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../../core/presentation/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../../core/network/supabase_config.dart';

class DeliveryManagementScreen extends StatefulWidget {
  const DeliveryManagementScreen({super.key});

  @override
  State<DeliveryManagementScreen> createState() => _DeliveryManagementScreenState();
}

class _DeliveryManagementScreenState extends State<DeliveryManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _client = SupabaseConfig.client;
  String? _cafeId;
  bool _isLoading = true;

  List<Map<String, dynamic>> _pending = [];
  List<Map<String, dynamic>> _preparing = [];
  List<Map<String, dynamic>> _outForDelivery = [];
  List<Map<String, dynamic>> _history = [];

  final _driverNameCtrl = TextEditingController();
  final _driverPhoneCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cafeId = context.read<AuthProvider>().cafeId;
      _loadDeliveries();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _driverNameCtrl.dispose();
    _driverPhoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDeliveries() async {
    if (_cafeId == null) return;
    setState(() => _isLoading = true);
    try {
      final data = await _client
          .from('deliveries')
          .select('*, orders(*, order_items(*))')
          .eq('cafe_id', _cafeId!)
          .order('created_at', ascending: false);

      final deliveries = List<Map<String, dynamic>>.from(data);
      setState(() {
        _pending = deliveries.where((d) => d['status'] == 'pending').toList();
        _preparing = deliveries.where((d) => d['status'] == 'preparing').toList();
        _outForDelivery = deliveries.where((d) => d['status'] == 'out_for_delivery').toList();
        _history = deliveries.where((d) => d['status'] == 'delivered' || d['status'] == 'cancelled').toList();
      });
    } catch (e) {
      _showError('Failed to load deliveries: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.green),
    );
  }

  // ── OPERATIONS ────────────────────────────────────────────────────────────

  Future<void> _confirmOrder(Map<String, dynamic> delivery) async {
    try {
      await _client
          .from('deliveries')
          .update({'status': 'preparing', 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', delivery['id']);
      
      // Also update linked order status to kitchen/preparing if linked
      if (delivery['order_id'] != null) {
        await _client
            .from('orders')
            .update({'status': 'kitchen', 'updated_at': DateTime.now().toIso8601String()})
            .eq('id', delivery['order_id']);
      }

      _showSuccess('Order confirmed! Moved to kitchen/preparing.');
      _loadDeliveries();
    } catch (e) {
      _showError('Failed to confirm order: $e');
    }
  }

  Future<void> _showDispatchDialog(Map<String, dynamic> delivery) async {
    _driverNameCtrl.clear();
    _driverPhoneCtrl.clear();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Assign Rider & Dispatch'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _driverNameCtrl,
              decoration: const InputDecoration(
                labelText: 'Rider Name',
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _driverPhoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Rider Phone Number',
                prefixIcon: Icon(Icons.phone),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (_driverNameCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter driver name')),
                );
                return;
              }
              Navigator.pop(context, true);
            },
            child: const Text('Dispatch'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _client.from('deliveries').update({
          'status': 'out_for_delivery',
          'driver_name': _driverNameCtrl.text.trim(),
          'driver_phone': _driverPhoneCtrl.text.trim(),
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', delivery['id']);

        _showSuccess('Rider assigned! Order is out for delivery.');
        _loadDeliveries();
      } catch (e) {
        _showError('Failed to dispatch order: $e');
      }
    }
  }

  Future<void> _markDelivered(Map<String, dynamic> delivery) async {
    try {
      await _client.from('deliveries').update({
        'status': 'delivered',
        'payment_status': 'paid',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', delivery['id']);

      if (delivery['order_id'] != null) {
        await _client.from('orders').update({
          'status': 'completed',
          'payment_method': (delivery['payment_method'] as String? ?? 'cash').toLowerCase(),
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', delivery['order_id']);
      }

      _showSuccess('Delivery marked as completed & payment updated to Paid.');
      _loadDeliveries();
    } catch (e) {
      _showError('Failed to complete delivery: $e');
    }
  }

  Future<void> _cancelOrder(Map<String, dynamic> delivery) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancel Delivery Order'),
        content: const Text('Are you sure you want to cancel this delivery order?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _client.from('deliveries').update({
          'status': 'cancelled',
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', delivery['id']);

        if (delivery['order_id'] != null) {
          await _client.from('orders').update({
            'status': 'cancelled',
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', delivery['order_id']);
        }

        _showSuccess('Order cancelled successfully.');
        _loadDeliveries();
      } catch (e) {
        _showError('Failed to cancel order: $e');
      }
    }
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Delivery Tracking', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDeliveries,
            tooltip: 'Refresh',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primaryColor,
          unselectedLabelColor: Colors.grey,
          indicatorColor: AppTheme.primaryColor,
          tabs: [
            Tab(text: 'Pending (${_pending.length})'),
            Tab(text: 'Preparing (${_preparing.length})'),
            Tab(text: 'Out (${_outForDelivery.length})'),
            const Tab(text: 'History'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildList(_pending, status: 'pending'),
                _buildList(_preparing, status: 'preparing'),
                _buildList(_outForDelivery, status: 'out_for_delivery'),
                _buildList(_history, status: 'history'),
              ],
            ),
    );
  }

  Widget _buildList(List<Map<String, dynamic>> list, {required String status}) {
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delivery_dining, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text('No $status deliveries', style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadDeliveries,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: list.length,
        itemBuilder: (context, index) => _buildDeliveryCard(list[index], status: status),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'preparing':
        return Colors.blue;
      case 'out_for_delivery':
        return Colors.purple;
      case 'delivered':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Widget _buildDeliveryCard(Map<String, dynamic> delivery, {required String status}) {
    final statusColor = _statusColor(delivery['status'] as String? ?? 'pending');
    final formattedDate = delivery['created_at'] != null
        ? DateFormat('hh:mm a • MMM dd').format(DateTime.parse(delivery['created_at']).toLocal())
        : '';

    // Extract items
    List<dynamic> items = [];
    if (delivery['orders'] != null && delivery['orders']['order_items'] != null) {
      items = delivery['orders']['order_items'] as List<dynamic>;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.delivery_dining, color: AppTheme.primaryColor, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(delivery['customer_name'] ?? 'Customer', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text(delivery['customer_phone'] ?? '', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    (delivery['status'] as String? ?? '').replaceAll('_', ' ').toUpperCase(),
                    style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),

            _infoRow(Icons.location_on_outlined, 'Address', delivery['delivery_address'] ?? 'No Address'),
            const SizedBox(height: 8),

            if (delivery['notes'] != null && delivery['notes'].toString().trim().isNotEmpty) ...[
              _infoRow(Icons.note_alt_outlined, 'Instructions', delivery['notes']),
              const SizedBox(height: 8),
            ],

            if (delivery['driver_name'] != null) ...[
              _infoRow(Icons.motorcycle, 'Rider', '${delivery['driver_name']} (${delivery['driver_phone'] ?? "No Phone"})'),
              const SizedBox(height: 8),
            ],

            _infoRow(Icons.payment_outlined, 'Payment', '${(delivery['payment_method'] as String? ?? "cash").toUpperCase()} • ${(delivery['payment_status'] as String? ?? "pending").toUpperCase()}'),
            const SizedBox(height: 8),

            _infoRow(Icons.access_time, 'Placed At', formattedDate),
            const SizedBox(height: 12),

            // Order items list
            if (items.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade100),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ORDER ITEMS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey)),
                    const SizedBox(height: 6),
                    ...items.map((item) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${item['quantity']}x ${item['product_name'] ?? item['product_name']}',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                            Text(
                              'Rs. ${(item['total_price'] ?? 0).toStringAsFixed(0)}',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Delivery Charge', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        Text('Rs. ${(delivery['delivery_charge'] ?? 0.0).toStringAsFixed(0)}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Grand Total', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        Text(
                          'Rs. ${(delivery['grand_total'] ?? 0.0).toStringAsFixed(0)}',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (delivery['status'] == 'pending') ...[
                  TextButton.icon(
                    onPressed: () => _cancelOrder(delivery),
                    icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                    label: const Text('Cancel', style: TextStyle(color: Colors.red)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                    onPressed: () => _confirmOrder(delivery),
                    icon: const Icon(Icons.check),
                    label: const Text('Confirm Order'),
                  ),
                ],
                if (delivery['status'] == 'preparing') ...[
                  TextButton.icon(
                    onPressed: () => _cancelOrder(delivery),
                    icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                    label: const Text('Cancel', style: TextStyle(color: Colors.red)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
                    onPressed: () => _showDispatchDialog(delivery),
                    icon: const Icon(Icons.motorcycle),
                    label: const Text('Assign & Dispatch'),
                  ),
                ],
                if (delivery['status'] == 'out_for_delivery') ...[
                  TextButton.icon(
                    onPressed: () => _cancelOrder(delivery),
                    icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                    label: const Text('Cancel', style: TextStyle(color: Colors.red)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                    onPressed: () => _markDelivered(delivery),
                    icon: const Icon(Icons.done_all),
                    label: const Text('Delivered'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String title, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade500),
        const SizedBox(width: 8),
        Text('$title: ', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.textSecondary)),
        Expanded(
          child: Text(value, style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary, fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }
}
