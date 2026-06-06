import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../../core/presentation/theme/app_theme.dart';
import '../../../../core/presentation/widgets/app_button.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../operations/presentation/providers/operations_provider.dart';
import '../../data/models/order_model.dart';
import '../../data/models/order_item_model.dart';
import '../providers/pos_provider.dart';
import '../providers/table_provider.dart';
import 'receipt_screen.dart';

class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key});

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  final _client = Supabase.instance.client;
  List<OrderModel> _billingOrders = [];
  bool _isLoading = false;
  String? _errorMessage;

  OrderModel? _selectedOrder;
  bool _isLoadingOrderDetails = false;
  List<OrderItemModel> _selectedOrderItems = [];

  String _checkoutPaymentMethod = 'Cash';
  double _checkoutDiscount = 0.0;
  String? _selectedCustomerDueId;

  @override
  void initState() {
    super.initState();
    _loadBillingOrders();
  }

  Future<void> _loadBillingOrders() async {
    final auth = context.read<AuthProvider>();
    final cafeId = auth.cafeId;
    if (cafeId == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final cacheBox = Hive.box('cache');
    final cacheKey = 'billing_orders_$cafeId';

    // 1. Get offline queued orders
    List<OrderModel> pendingOrders = [];
    try {
      final offlineBox = Hive.box('offline_orders');
      for (var key in offlineBox.keys) {
        final orderJsonString = offlineBox.get(key);
        if (orderJsonString != null) {
          final Map<String, dynamic> data = jsonDecode(orderJsonString);
          final orderJson = data['order'] as Map<String, dynamic>;
          final order = OrderModel.fromJson(orderJson);
          pendingOrders.add(order);
        }
      }
    } catch (e) {
      debugPrint('Error loading pending offline orders in billing: $e');
    }

    try {
      final res = await _client
          .from('orders')
          .select('*, waiter:profiles!waiter_id(full_name), table:tables!table_id(name)')
          .eq('cafe_id', cafeId)
          .inFilter('status', ['served', 'ready', 'billed', 'kitchen_sent'])
          .order('created_at', ascending: false);

      final list = (res as List).map((json) => OrderModel.fromJson(json)).toList();
      
      // Cache the loaded orders
      await cacheBox.put(cacheKey, jsonEncode(res));

      // Filter list:
      // Dine-in must be served, ready, or billed.
      // Takeaway can be kitchen_sent or billed.
      final filteredOnline = list.where((order) {
        if (order.type == 'dine_in') {
          return order.status == 'served' || order.status == 'ready' || order.status == 'billed';
        } else {
          return order.status == 'kitchen_sent' || order.status == 'billed';
        }
      }).toList();

      if (mounted) {
        setState(() {
          _billingOrders = [...pendingOrders, ...filteredOnline];
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading billing orders online, falling back to cache: $e');
      // Offline fallback: load cached billing orders
      final cachedData = cacheBox.get(cacheKey);
      List<OrderModel> cachedOrders = [];
      if (cachedData != null) {
        final List<dynamic> jsonList = jsonDecode(cachedData);
        cachedOrders = jsonList.map((json) => OrderModel.fromJson(json)).toList();
      }

      final filteredCached = cachedOrders.where((order) {
        if (order.type == 'dine_in') {
          return order.status == 'served' || order.status == 'ready' || order.status == 'billed';
        } else {
          return order.status == 'kitchen_sent' || order.status == 'billed';
        }
      }).toList();

      if (mounted) {
        setState(() {
          _billingOrders = [...pendingOrders, ...filteredCached];
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _selectOrder(OrderModel order) async {
    setState(() {
      _isLoadingOrderDetails = true;
      _selectedOrder = order;
      _selectedOrderItems = [];
      _checkoutPaymentMethod = 'Cash';
      _checkoutDiscount = order.discount;
      _selectedCustomerDueId = order.customerDueId;
    });

    try {
      final auth = context.read<AuthProvider>();
      final cafeId = auth.cafeId!;
      final role = auth.currentProfile?.role ?? 'cashier';
      
      // Load details into POS Provider to reuse checkout machinery
      await context.read<PosProvider>().loadOrderForEditing(order.id, cafeId, role);

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
        debugPrint('Error scanning offline box for billing items: $e');
      }

      if (offlineItems != null) {
        if (mounted) {
          setState(() {
            _selectedOrderItems = offlineItems!;
            _isLoadingOrderDetails = false;
          });
        }
        return;
      }

      final cacheBox = Hive.box('cache');
      final cacheKey = 'order_items_${order.id}';

      try {
        final res = await _client
            .from('order_items')
            .select()
            .eq('order_id', order.id);

        final items = (res as List)
            .map((json) => OrderItemModel.fromJson(json))
            .where((item) => item.status != 'cancelled')
            .toList();

        // Cache it
        await cacheBox.put(cacheKey, jsonEncode(res));

        if (mounted) {
          setState(() {
            _selectedOrderItems = items;
            _isLoadingOrderDetails = false;
          });
        }
      } catch (e) {
        debugPrint('Error loading order items online, falling back to cache: $e');
        final cachedData = cacheBox.get(cacheKey);
        List<OrderItemModel> items = [];
        if (cachedData != null) {
          final List<dynamic> jsonList = jsonDecode(cachedData);
          items = jsonList
              .map((json) => OrderItemModel.fromJson(json))
              .where((item) => item.status != 'cancelled')
              .toList();
        }
        if (mounted) {
          setState(() {
            _selectedOrderItems = items;
            _isLoadingOrderDetails = false;
          });
        }
      }
    } catch (e) {
      debugPrint('General error in selectOrder: $e');
      if (mounted) {
        setState(() {
          _isLoadingOrderDetails = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load items: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _finalizeCheckout() async {
    if (_selectedOrder == null) return;

    final auth = context.read<AuthProvider>();
    final cafeId = auth.cafeId!;
    final cashierId = auth.currentProfile?.id ?? '';
    final role = auth.currentProfile?.role?.toLowerCase() ?? '';

    // Standard discount rule: cashier cannot apply more than 10% discount without warning/notify
    final posProvider = context.read<PosProvider>();
    final subtotal = posProvider.subtotal;
    
    if (_checkoutDiscount > (subtotal * 0.1) && role == 'cashier') {
      // Large discount applied by cashier: trigger notification to owner/admin
      try {
        await _client.from('notifications').insert({
          'cafe_id': cafeId,
          'recipient_role': 'owner',
          'title': 'Large Discount Applied',
          'message': 'Cashier applied Rs. ${_checkoutDiscount.toStringAsFixed(2)} discount (Subtotal: Rs. ${subtotal.toStringAsFixed(2)}) on Table ${_selectedOrder!.tableName ?? "Takeaway"}.',
          'type': 'large_discount_applied',
          'metadata': {'order_id': _selectedOrder!.id},
        });
      } catch (e) {
        debugPrint('Error inserting cashier discount alert offline: $e');
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    // Apply checkout variables to PosProvider
    posProvider.setPaymentMethod(_checkoutPaymentMethod);
    posProvider.setDiscount(_checkoutDiscount);

    final success = await posProvider.finalizePayment(
      cafeId,
      cashierId,
      customerDueId: _checkoutPaymentMethod.toLowerCase() == 'due' ? _selectedCustomerDueId : null,
    );

    if (mounted) {
      Navigator.pop(context); // Pop loading spinner
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment finalized successfully!'), backgroundColor: Colors.green),
        );
        
        // Refresh orders and tables
        _loadBillingOrders();
        context.read<TableProvider>().fetchTables();

        // Open Receipt Screen
        final orderCopy = _selectedOrder!;
        final itemsCopy = _selectedOrderItems;
        
        setState(() {
          _selectedOrder = null;
          _selectedOrderItems = [];
        });

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ReceiptScreen(
              order: orderCopy.copyWith(
                status: 'completed',
                paymentMethod: _checkoutPaymentMethod.toLowerCase(),
                discount: _checkoutDiscount,
                grandTotal: (subtotal - _checkoutDiscount) * 1.13, // re-estimate matching POS
              ),
              items: itemsCopy,
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Checkout failed: ${posProvider.errorMessage}'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Widget _buildOrderCard(OrderModel order) {
    final isSelected = _selectedOrder?.id == order.id;
    final formattedDate = order.createdAt != null
        ? order.createdAt!.toLocal().toString().substring(11, 16)
        : 'N/A';

    return InkWell(
      onTap: () => _selectOrder(order),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryColor.withOpacity(0.06) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : Colors.grey.shade200,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: order.type == 'dine_in' ? Colors.indigo.shade50 : Colors.teal.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                order.type == 'dine_in' ? Icons.table_restaurant : Icons.takeout_dining,
                color: order.type == 'dine_in' ? Colors.indigo.shade700 : Colors.teal.shade700,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    order.type == 'dine_in' ? 'Table ${order.tableName ?? "N/A"}' : 'Takeaway Order',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Bill No: #${order.billNumber ?? "N/A"}  |  Time: $formattedDate',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: order.status == 'ready' ? Colors.teal.shade50 : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                order.status.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: order.status == 'ready' ? Colors.teal.shade700 : Colors.orange.shade900,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_ios, size: 14, color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _buildOrdersListPanel() {
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _errorMessage != null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                    const SizedBox(height: 16),
                    Text('Error: $_errorMessage', style: const TextStyle(color: Colors.redAccent)),
                    const SizedBox(height: 16),
                    ElevatedButton(onPressed: _loadBillingOrders, child: const Text('Retry')),
                  ],
                ),
              )
            : _billingOrders.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.payments_outlined, color: AppTheme.textSecondary, size: 64),
                        SizedBox(height: 16),
                        Text(
                          'No orders ready for billing.',
                          style: TextStyle(fontSize: 18, color: AppTheme.textSecondary, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(24),
                    itemCount: _billingOrders.length,
                    itemBuilder: (context, index) {
                      return _buildOrderCard(_billingOrders[index]);
                    },
                  );
  }

  Widget _buildEmptyCheckoutPane() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shopping_cart_checkout, color: AppTheme.textSecondary, size: 48),
          SizedBox(height: 16),
          Text(
            'Select an active order to begin checkout.',
            style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isTablet = size.width > 950 && size.width > size.height;

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header section
          Container(
            padding: EdgeInsets.all(isTablet ? 24 : 16),
            color: Colors.white,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Billing & Checkout',
                        style: TextStyle(fontSize: isTablet ? 28 : 22, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Review served/ready orders and finalize payments.',
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: isTablet ? 14 : 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: isTablet ? 16 : 12, vertical: isTablet ? 12 : 8),
                  ),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text('Refresh', style: TextStyle(fontSize: isTablet ? 14 : 12)),
                  onPressed: _loadBillingOrders,
                ),
              ],
            ),
          ),

          // Main list panel / split panel
          Expanded(
            child: isTablet
                ? Row(
                    children: [
                      // Left Panel: Active billing orders list
                      Expanded(
                        flex: 5,
                        child: _buildOrdersListPanel(),
                      ),
                      const VerticalDivider(width: 1, thickness: 1),
                      // Right Panel: Checkout / Cart Summary panel
                      Expanded(
                        flex: 6,
                        child: Container(
                          color: Colors.white,
                          child: _selectedOrder == null
                              ? _buildEmptyCheckoutPane()
                              : _isLoadingOrderDetails
                                  ? const Center(child: CircularProgressIndicator())
                                  : _buildCheckoutPane(),
                        ),
                      ),
                    ],
                  )
                : _selectedOrder == null
                    ? _buildOrdersListPanel()
                    : _isLoadingOrderDetails
                        ? const Center(child: CircularProgressIndicator())
                        : Container(
                            color: Colors.white,
                            child: _buildCheckoutPane(),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckoutPane() {
    final posProvider = context.watch<PosProvider>();
    final auth = context.read<AuthProvider>();
    final role = auth.currentProfile?.role?.toLowerCase() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Title block
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _selectedOrder!.type == 'dine_in'
                        ? 'Table ${_selectedOrder!.tableName} Checkout'
                        : 'Takeaway Checkout',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Bill No: #${_selectedOrder!.billNumber}  |  Waiter: ${_selectedOrder!.waiterName ?? "N/A"}',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                  _selectedOrder = null;
                  _selectedOrderItems = [];
                }),
              ),
            ],
          ),
        ),

        // Items listing
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: _selectedOrderItems.length,
            itemBuilder: (context, index) {
              final item = _selectedOrderItems[index];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.productName,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          if (item.notes != null && item.notes!.isNotEmpty)
                            Text(
                              'Note: ${item.notes}',
                              style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      '${item.quantity}x',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 20),
                    Text(
                      'Rs. ${item.totalPrice.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              );
            },
          ),
        ),

        // Checkout Inputs (Discounts and Dues)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Segmented payment buttons
              const Text('Payment Method:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'Cash', label: Text('Cash')),
                  ButtonSegment(value: 'QR', label: Text('QR')),
                  ButtonSegment(value: 'Card', label: Text('Card')),
                  ButtonSegment(value: 'Due', label: Text('Due')),
                ],
                selected: {_checkoutPaymentMethod},
                onSelectionChanged: (set) {
                  setState(() {
                    _checkoutPaymentMethod = set.first;
                    if (_checkoutPaymentMethod != 'Due') {
                      _selectedCustomerDueId = null;
                    }
                  });
                },
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
              ),
              const SizedBox(height: 12),

              // Customer Dues Selector
              if (_checkoutPaymentMethod == 'Due') ...[
                const Text('Select Customer Due Account:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                Consumer<OperationsProvider>(
                  builder: (context, operationsProvider, child) {
                    final dues = operationsProvider.customerDues;
                    return DropdownButtonFormField<String>(
                      value: _selectedCustomerDueId,
                      decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.all(12)),
                      items: dues.map((d) => DropdownMenuItem(value: d.id, child: Text('${d.name} (Due: Rs. ${d.totalDue.toStringAsFixed(2)})'))).toList(),
                      onChanged: (val) {
                        setState(() {
                          _selectedCustomerDueId = val;
                        });
                      },
                    );
                  },
                ),
                const SizedBox(height: 12),
              ],

              // Discount field
              Row(
                children: [
                  const Text('Apply Discount (Rs):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: TextField(
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 10),
                          isDense: true,
                        ),
                        onChanged: (val) {
                          final double discount = double.tryParse(val) ?? 0.0;
                          setState(() {
                            _checkoutDiscount = discount;
                          });
                        },
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),

        // Financial calculations
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            border: Border(top: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Column(
            children: [
              _buildCheckoutRow('Subtotal', posProvider.subtotal),
              _buildCheckoutRow('Discount', _checkoutDiscount, isNegative: true),
              _buildCheckoutRow('VAT (13%)', (posProvider.subtotal - _checkoutDiscount > 0 ? posProvider.subtotal - _checkoutDiscount : 0.0) * 0.13),
              const Divider(),
              _buildCheckoutRow('Grand Total', (posProvider.subtotal - _checkoutDiscount > 0 ? posProvider.subtotal - _checkoutDiscount : 0.0) * 1.13, isBold: true, size: 20),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: AppTheme.primaryColor.withOpacity(0.5)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.receipt_long, size: 16),
                      label: const Text('Reprint Receipt', style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: () => _viewReceipt(_selectedOrder!),
                    ),
                  ),
                  if (role != 'waiter' || posProvider.waiterBillingEnabled) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppButton(
                        text: 'Finalize Checkout',
                        isLoading: posProvider.state == PosState.loading,
                        onPressed: (_checkoutPaymentMethod == 'Due' && _selectedCustomerDueId == null)
                            ? () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Please select a customer due account first.'), backgroundColor: Colors.orange),
                                );
                              }
                            : _finalizeCheckout,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCheckoutRow(String label, double amount, {bool isNegative = false, bool isBold = false, double size = 14}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, fontSize: size)),
          Text(
            '${isNegative ? "- " : ""}Rs. ${amount.toStringAsFixed(2)}',
            style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, fontSize: size),
          ),
        ],
      ),
    );
  }

  Future<void> _viewReceipt(OrderModel order) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReceiptScreen(
          order: order.copyWith(
            discount: _checkoutDiscount,
            grandTotal: (context.read<PosProvider>().subtotal - _checkoutDiscount > 0 ? context.read<PosProvider>().subtotal - _checkoutDiscount : 0.0) * 1.13,
          ),
          items: _selectedOrderItems,
        ),
      ),
    );
  }
}
