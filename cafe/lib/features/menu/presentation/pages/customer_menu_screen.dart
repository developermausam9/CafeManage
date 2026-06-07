import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import '../../../../core/presentation/theme/app_theme.dart';
import '../../../../core/network/supabase_config.dart';

class CustomerMenuScreen extends StatefulWidget {
  const CustomerMenuScreen({super.key});

  @override
  State<CustomerMenuScreen> createState() => _CustomerMenuScreenState();
}

class _CustomerMenuScreenState extends State<CustomerMenuScreen>
    with SingleTickerProviderStateMixin {
  final SupabaseClient _client = SupabaseConfig.client;
  late TabController _tabController;

  // URL params
  String? _cafeId;
  String? _roomId;
  String? _bookingId;
  String? _cafeName;
  String? _roomNumber;
  Map<String, dynamic>? _booking;

  bool _isLoading = true;
  String? _errorMessage;

  // Menu
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _filteredProducts = [];
  String? _selectedCategoryId;
  final _searchCtrl = TextEditingController();

  // Cart
  final Map<String, _CartItem> _cart = {};
  bool _isPlacingOrder = false;

  // My Orders (real-time polling)
  List<Map<String, dynamic>> _myOrders = [];
  bool _loadingOrders = false;

  // My Bill
  double _roomCharge = 0;
  double _foodTotal = 0;
  bool _loadingBill = false;
  bool _checkoutRequested = false;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1) _loadMyOrders();
      if (_tabController.index == 2) _loadBill();
    });
    _initializeData();
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted) {
        _loadMyOrders(silent: true);
        _loadBill(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Map<String, String> _getQueryParams() {
    final params = Map<String, String>.from(Uri.base.queryParameters);
    final fragment = Uri.base.fragment;
    if (fragment.contains('?')) {
      final queryString = fragment.split('?').last;
      for (var part in queryString.split('&')) {
        final kv = part.split('=');
        if (kv.length == 2) params[kv[0]] = Uri.decodeComponent(kv[1]);
      }
    }
    return params;
  }

  bool _isValidUuid(String? s) {
    if (s == null || s.isEmpty) return false;
    final uuidRegex = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false,
    );
    return uuidRegex.hasMatch(s);
  }

  Future<void> _initializeData() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    final params = _getQueryParams();
    final rawCafeId = params['cafe_id'];
    final rawRoomId = params['room_id'];
    _bookingId = _isValidUuid(params['booking_id']) ? params['booking_id'] : null;
    _cafeId = _isValidUuid(rawCafeId) ? rawCafeId : null;
    _roomId = _isValidUuid(rawRoomId) ? rawRoomId : null;

    if (_cafeId == null || _roomId == null) {
      setState(() {
        _errorMessage = 'Invalid QR code. Please ask staff to re-print the room QR.';
        _isLoading = false;
      });
      return;
    }

    try {
      final cafe = await _client.from('cafes').select('name').eq('id', _cafeId!).single();
      _cafeName = cafe['name'];

      final room = await _client.from('rooms').select('room_number').eq('id', _roomId!).single();
      _roomNumber = room['room_number'];

      // Load booking info if available
      if (_bookingId != null && _bookingId!.isNotEmpty) {
        try {
          final b = await _client.from('room_bookings')
              .select('guest_name, check_in_date, check_out_date, total_amount, room_charge, status')
              .eq('id', _bookingId!).maybeSingle();
          _booking = b;
          _roomCharge = (b?['room_charge'] as num?)?.toDouble() ?? 0;
        } catch (_) {}
      }

      // Load menu
      final cats = await _client.from('categories').select().eq('cafe_id', _cafeId!).order('name');
      _categories = List<Map<String, dynamic>>.from(cats);
      final prods = await _client.from('products').select().eq('cafe_id', _cafeId!).eq('is_available', true).order('name');
      _products = List<Map<String, dynamic>>.from(prods);
      _filteredProducts = List.from(_products);
      _startPolling();
    } catch (e) {
      setState(() => _errorMessage = 'Failed to load: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _filterProducts() {
    final q = _searchCtrl.text.toLowerCase().trim();
    setState(() {
      _filteredProducts = _products.where((p) {
        final matchCat = _selectedCategoryId == null || p['category_id'] == _selectedCategoryId;
        final matchSearch = p['name'].toString().toLowerCase().contains(q) ||
            (p['description']?.toString().toLowerCase().contains(q) ?? false);
        return matchCat && matchSearch;
      }).toList();
    });
  }

  void _addToCart(Map<String, dynamic> product) {
    final pId = product['id'] as String;
    setState(() {
      if (_cart.containsKey(pId)) {
        _cart[pId]!.quantity++;
      } else {
        _cart[pId] = _CartItem(id: pId, name: product['name'], price: (product['price'] as num).toDouble(), quantity: 1);
      }
    });
  }

  void _removeFromCart(String pId) {
    setState(() {
      if (_cart.containsKey(pId)) {
        if (_cart[pId]!.quantity > 1) {
          _cart[pId]!.quantity--;
        } else {
          _cart.remove(pId);
        }
      }
    });
  }

  double get _cartTotal => _cart.values.fold(0.0, (s, i) => s + i.price * i.quantity);
  int get _cartCount => _cart.values.fold(0, (s, i) => s + i.quantity);

  Future<void> _placeOrder() async {
    if (_cart.isEmpty) return;
    setState(() => _isPlacingOrder = true);
    try {
      final orderId = const Uuid().v4();
      final subtotal = _cartTotal;

      double taxPct = 0, svcPct = 0;
      final settings = await _client.from('settings').select('tax_percentage, service_charge_percentage').eq('cafe_id', _cafeId!).maybeSingle();
      if (settings != null) {
        taxPct = (settings['tax_percentage'] as num?)?.toDouble() ?? 0;
        svcPct = (settings['service_charge_percentage'] as num?)?.toDouble() ?? 0;
      }
      final tax = subtotal * (taxPct / 100);
      final svc = subtotal * (svcPct / 100);
      final grandTotal = subtotal + tax + svc;

      // Check if there is an active (uncompleted, uncancelled) order for this room booking / room
      dynamic activeOrderRes;
      if (_bookingId != null && _bookingId!.isNotEmpty) {
        activeOrderRes = await _client
            .from('orders')
            .select()
            .eq('room_booking_id', _bookingId!)
            .neq('status', 'completed')
            .neq('status', 'cancelled')
            .maybeSingle();
      } else {
        activeOrderRes = await _client
            .from('orders')
            .select()
            .eq('room_id', _roomId!)
            .eq('cafe_id', _cafeId!)
            .neq('status', 'completed')
            .neq('status', 'cancelled')
            .maybeSingle();
      }

      String targetOrderId;
      if (activeOrderRes != null) {
        targetOrderId = activeOrderRes['id'];
        final double currentSubtotal = (activeOrderRes['subtotal'] as num).toDouble();
        final double currentDiscount = (activeOrderRes['discount'] as num).toDouble();
        final double newSubtotal = currentSubtotal + subtotal;
        final double newTax = (newSubtotal - currentDiscount > 0 ? newSubtotal - currentDiscount : 0.0) * (taxPct / 100);
        final double newSvc = (newSubtotal - currentDiscount > 0 ? newSubtotal - currentDiscount : 0.0) * (svcPct / 100);
        final double newGrandTotal = newSubtotal - currentDiscount + newTax + newSvc;

        await _client.from('orders').update({
          'subtotal': newSubtotal,
          'tax_amount': newTax,
          'service_charge': newSvc,
          'grand_total': newGrandTotal,
          'remaining_due': newGrandTotal,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', targetOrderId);
      } else {
        targetOrderId = orderId;
        await _client.from('orders').insert({
          'id': orderId,
          'cafe_id': _cafeId,
          'room_id': _roomId,
          'room_booking_id': _bookingId,
          'type': 'dine_in',
          'status': 'pending',
          'subtotal': subtotal,
          'discount': 0.0,
          'tax_amount': tax,
          'service_charge': svc,
          'grand_total': grandTotal,
          'payment_method': 'due',
          'payment_status': 'unpaid',
          'paid_amount': 0.0,
          'remaining_due': grandTotal,
        });
      }

      final items = _cart.values.map((item) => {
        'id': const Uuid().v4(),
        'order_id': targetOrderId,
        'product_id': item.id,
        'product_name': item.name,
        'quantity': item.quantity,
        'unit_price': item.price,
        'total_price': item.price * item.quantity,
        'status': 'sent',
      }).toList();
      await _client.from('order_items').insert(items);

      // Send notification to kitchen role
      await _client.from('notifications').insert({
        'cafe_id': _cafeId,
        'recipient_role': 'kitchen',
        'title': 'New Room Service Order',
        'message': 'Room $_roomNumber placed an order for Rs. ${grandTotal.toStringAsFixed(0)}',
        'type': 'kot_received',
        'metadata': {
          'order_id': targetOrderId,
          'table_no': 'Room $_roomNumber',
          'item_count': _cartCount,
        },
        'is_read': false,
      });

      // Send notification to waiter role
      await _client.from('notifications').insert({
        'cafe_id': _cafeId,
        'recipient_role': 'waiter',
        'title': 'New Room Service Order',
        'message': 'Room $_roomNumber placed an order for Rs. ${grandTotal.toStringAsFixed(0)}',
        'type': 'kot_received',
        'metadata': {
          'order_id': targetOrderId,
          'table_no': 'Room $_roomNumber',
          'item_count': _cartCount,
        },
        'is_read': false,
      });

      setState(() => _cart.clear());
      Navigator.pop(context); // close cart sheet
      _showOrderSuccess();
      _tabController.animateTo(1); // switch to My Orders tab
      _loadMyOrders();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Order failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isPlacingOrder = false);
    }
  }

  void _showOrderSuccess() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(children: [
          Icon(Icons.check_circle, color: Colors.white),
          SizedBox(width: 8),
          Text('Order sent to kitchen! 🍳', style: TextStyle(fontWeight: FontWeight.bold)),
        ]),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _loadMyOrders({bool silent = false}) async {
    if (_cafeId == null) return;
    if (!silent) setState(() => _loadingOrders = true);
    try {
      dynamic query = _client.from('orders').select('id, status, grand_total, created_at, order_items(quantity, unit_price, products(name))');
      if (_bookingId != null && _bookingId!.isNotEmpty) {
        query = query.eq('room_booking_id', _bookingId!);
      } else {
        query = query.eq('room_id', _roomId!).eq('cafe_id', _cafeId!);
      }
      final data = await query.order('created_at', ascending: false).limit(20);
      setState(() => _myOrders = List<Map<String, dynamic>>.from(data));
    } catch (_) {} finally {
      if (!silent) setState(() => _loadingOrders = false);
    }
  }

  Future<void> _loadBill({bool silent = false}) async {
    if (_cafeId == null || _roomId == null) return;
    if (!silent) setState(() => _loadingBill = true);
    try {
      dynamic query = _client.from('orders').select('grand_total, status').neq('status', 'cancelled');
      if (_bookingId != null && _bookingId!.isNotEmpty) {
        query = query.eq('room_booking_id', _bookingId!);
      } else {
        query = query.eq('room_id', _roomId!).eq('cafe_id', _cafeId!);
      }
      final orders = await query;
      final total = (orders as List).fold<double>(
          0, (s, o) => s + ((o['grand_total'] as num?)?.toDouble() ?? 0));
      setState(() => _foodTotal = total);
    } catch (_) {} finally {
      if (!silent) setState(() => _loadingBill = false);
    }
  }

  Future<void> _requestCheckout() async {
    try {
      await _client.from('notifications').insert({
        'cafe_id': _cafeId,
        'title': 'Checkout Requested',
        'message': 'Room $_roomNumber has requested checkout.',
        'type': 'checkout_request',
        'is_read': false,
      });
      setState(() => _checkoutRequested = true);
    } catch (_) {}
  }

  // ─────────────────────────────────────────────── BUILD
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const CircularProgressIndicator(color: AppTheme.primaryColor),
        const SizedBox(height: 16),
        Text('Loading menu...', style: TextStyle(color: Colors.grey.shade600)),
      ])));
    }
    if (_errorMessage != null) {
      return Scaffold(body: Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.qr_code_scanner, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: Colors.grey)),
        ]),
      )));
    }

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_cafeName ?? 'Room Service', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          Text('Room $_roomNumber${_booking != null ? ' · ${_booking!['guest_name']}' : ''}',
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _initializeData),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primaryColor,
          unselectedLabelColor: Colors.grey,
          indicatorColor: AppTheme.primaryColor,
          tabs: [
            const Tab(icon: Icon(Icons.restaurant_menu, size: 18), text: 'Menu'),
            Tab(
              child: Stack(clipBehavior: Clip.none, children: [
                const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.receipt_long, size: 18),
                  Text('My Orders', style: TextStyle(fontSize: 11)),
                ]),
                if (_myOrders.isNotEmpty)
                  Positioned(right: -8, top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                      child: Text('${_myOrders.length}', style: const TextStyle(color: Colors.white, fontSize: 9)),
                    ),
                  ),
              ]),
            ),
            const Tab(icon: Icon(Icons.attach_money, size: 18), text: 'My Bill'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildMenuTab(),
          _buildOrdersTab(),
          _buildBillTab(),
        ],
      ),
      bottomNavigationBar: _cart.isNotEmpty ? _buildCartBar() : null,
    );
  }

  // ── TAB 1: Menu ────────────────────────────────────────────────────────
  Widget _buildMenuTab() {
    return Column(children: [
      // Search + categories
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(children: [
          TextField(
            controller: _searchCtrl,
            onChanged: (_) => _filterProducts(),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search, color: Colors.grey),
              hintText: 'Search food, drinks...',
              filled: true,
              fillColor: AppTheme.backgroundColor,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          if (_categories.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 36,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _categories.length + 1,
                itemBuilder: (ctx, i) {
                  final isAll = i == 0;
                  final isSelected = isAll ? _selectedCategoryId == null : _selectedCategoryId == _categories[i - 1]['id'];
                  final label = isAll ? 'All' : _categories[i - 1]['name'];
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label, style: const TextStyle(fontSize: 13)),
                      selected: isSelected,
                      onSelected: (_) {
                        setState(() {
                          _selectedCategoryId = isAll ? null : _categories[i - 1]['id'];
                          _filterProducts();
                        });
                      },
                      selectedColor: AppTheme.primaryColor,
                      labelStyle: TextStyle(color: isSelected ? Colors.white : AppTheme.textPrimary, fontWeight: FontWeight.w600),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  );
                },
              ),
            ),
          ],
        ]),
      ),
      // Product grid
      Expanded(
        child: _filteredProducts.isEmpty
            ? const Center(child: Text('No items found.', style: TextStyle(color: Colors.grey)))
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _filteredProducts.length,
                itemBuilder: (ctx, i) => _buildProductCard(_filteredProducts[i]),
              ),
      ),
    ]);
  }

  Widget _buildProductCard(Map<String, dynamic> product) {
    final pId = product['id'] as String;
    final count = _cart[pId]?.quantity ?? 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 1,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          // Image
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 76, height: 76,
              color: AppTheme.backgroundColor,
              child: product['image_url'] != null && product['image_url'].toString().isNotEmpty
                  ? Image.network(product['image_url'], fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.fastfood, color: Colors.grey, size: 32))
                  : const Icon(Icons.fastfood, color: Colors.grey, size: 32),
            ),
          ),
          const SizedBox(width: 12),
          // Info
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(product['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            if (product['description'] != null)
              Text(product['description'], maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 6),
            Text('Rs. ${(product['price'] as num).toStringAsFixed(0)}',
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryColor, fontSize: 15)),
          ])),
          const SizedBox(width: 8),
          // Add/Remove
          if (count > 0)
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.primaryColor.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                InkWell(
                  onTap: () => _removeFromCart(pId),
                  borderRadius: BorderRadius.circular(10),
                  child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.remove, size: 18, color: Colors.red)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text('$count', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                InkWell(
                  onTap: () => _addToCart(product),
                  borderRadius: BorderRadius.circular(10),
                  child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.add, size: 18, color: Colors.green)),
                ),
              ]),
            )
          else
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => _addToCart(product),
              child: const Text('Add', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
        ]),
      ),
    );
  }

  // ── TAB 2: My Orders ───────────────────────────────────────────────────
  Widget _buildOrdersTab() {
    return RefreshIndicator(
      onRefresh: _loadMyOrders,
      child: _loadingOrders
          ? const Center(child: CircularProgressIndicator())
          : _myOrders.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.receipt_long, size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  const Text('No orders yet.', style: TextStyle(color: Colors.grey, fontSize: 16)),
                  const SizedBox(height: 8),
                  const Text('Order from the Menu tab!', style: TextStyle(color: Colors.grey, fontSize: 13)),
                ]))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _myOrders.length,
                  itemBuilder: (ctx, i) => _buildOrderCard(_myOrders[i]),
                ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final status = order['status'] as String? ?? 'pending';
    final items = order['order_items'] as List? ?? [];
    final total = (order['grand_total'] as num?)?.toDouble() ?? 0;
    final createdAt = order['created_at'] != null
        ? DateFormat('HH:mm').format(DateTime.parse(order['created_at']).toLocal())
        : '';

    final statusConfig = {
      'pending': (Colors.orange, Icons.hourglass_empty, 'Received'),
      'kitchen_sent': (Colors.orange, Icons.hourglass_empty, 'Received'),
      'preparing': (Colors.blue, Icons.restaurant, 'Preparing 🍳'),
      'ready': (Colors.green, Icons.check_circle, 'Ready! 🎉'),
      'served': (Colors.green, Icons.check_circle, 'Served'),
      'completed': (Colors.green, Icons.check_circle, 'Completed'),
      'cancelled': (Colors.red, Icons.cancel, 'Cancelled'),
    };
    final cfg = statusConfig[status] ?? (Colors.grey, Icons.info, status);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Order at $createdAt', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: cfg.$1.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(cfg.$2, size: 14, color: cfg.$1),
                const SizedBox(width: 4),
                Text(cfg.$3, style: TextStyle(color: cfg.$1, fontWeight: FontWeight.bold, fontSize: 12)),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          // Items
          ...items.take(3).map((item) {
            final prod = item['products'];
            final name = prod?['name'] ?? 'Item';
            final qty = item['quantity'] as int? ?? 1;
            final price = (item['unit_price'] as num?)?.toDouble() ?? 0;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Text('$qty×', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                const SizedBox(width: 6),
                Expanded(child: Text(name, style: const TextStyle(fontSize: 13))),
                Text('Rs. ${(qty * price).toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 13, color: Colors.grey)),
              ]),
            );
          }),
          if (items.length > 3) Text('+${items.length - 3} more items', style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const Divider(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Total', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('Rs. ${total.toStringAsFixed(0)}',
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
          ]),
          // Status progress bar
          if (status != 'cancelled') ...[
            const SizedBox(height: 12),
            _buildStatusProgress(status),
          ],
        ]),
      ),
    );
  }

  Widget _buildStatusProgress(String status) {
    final steps = ['pending', 'preparing', 'ready'];
    String mappedStatus = 'pending';
    if (status == 'preparing') {
      mappedStatus = 'preparing';
    } else if (status == 'ready' || status == 'served' || status == 'completed') {
      mappedStatus = 'ready';
    }
    final idx = steps.indexOf(mappedStatus);
    return Row(children: List.generate(steps.length * 2 - 1, (i) {
      if (i.isOdd) {
        final filled = i ~/ 2 < idx;
        return Expanded(child: Container(height: 3,
            color: filled ? Colors.green : Colors.grey.shade200));
      }
      final sIdx = i ~/ 2;
      final done = sIdx <= idx;
      final labels = ['Received', 'Preparing', 'Ready'];
      return Column(children: [
        Container(
          width: 24, height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? Colors.green : Colors.grey.shade200,
          ),
          child: Icon(done ? Icons.check : Icons.circle, color: done ? Colors.white : Colors.grey.shade400, size: 12),
        ),
        const SizedBox(height: 4),
        Text(labels[sIdx], style: TextStyle(fontSize: 9, color: done ? Colors.green : Colors.grey)),
      ]);
    }));
  }

  // ── TAB 3: My Bill ─────────────────────────────────────────────────────
  Widget _buildBillTab() {
    final grandTotal = _roomCharge + _foodTotal;
    return RefreshIndicator(
      onRefresh: _loadBill,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          // Room info banner
          if (_booking != null)
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              color: AppTheme.primaryColor,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  const Icon(Icons.hotel, color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_booking!['guest_name'] ?? 'Guest', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                    Text('Room $_roomNumber • ${_booking!['check_in_date']} → ${_booking!['check_out_date']}',
                        style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ]),
                ]),
              ),
            ),
          const SizedBox(height: 16),
          // Bill card
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            elevation: 4,
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: _loadingBill
                  ? const Center(child: CircularProgressIndicator())
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('BILL SUMMARY', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.5, color: Colors.grey)),
                      const SizedBox(height: 16),
                      _billLine('Room Charges', _roomCharge, Icons.hotel),
                      _billLine('Food & Room Service', _foodTotal, Icons.restaurant),
                      const Divider(height: 24),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        const Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                        Text('Rs. ${grandTotal.toStringAsFixed(0)}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24, color: AppTheme.primaryColor)),
                      ]),
                      const SizedBox(height: 6),
                      const Text('* This is an estimate. Final bill will be confirmed at checkout.',
                          style: TextStyle(fontSize: 11, color: Colors.grey)),
                    ]),
            ),
          ),
          const SizedBox(height: 20),
          // Refresh bill
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 46),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _loadBill,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh Bill'),
          ),
          const SizedBox(height: 12),
          // Request checkout
          if (!_checkoutRequested)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade600,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Request Checkout'),
                    content: const Text('This will notify hotel staff that you are ready to check out. They will come to settle your bill.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                        onPressed: () { Navigator.pop(context); _requestCheckout(); },
                        child: const Text('Yes, Request Checkout'),
                      ),
                    ],
                  ),
                );
              },
              icon: const Icon(Icons.logout),
              label: const Text('Request Checkout', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('Checkout requested! Staff is on the way.', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _billLine(String label, double amount, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Icon(icon, size: 18, color: Colors.grey),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 15))),
        Text('Rs. ${amount.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      ]),
    );
  }

  // ── Cart bar ────────────────────────────────────────────────────────────
  Widget _buildCartBar() {
    return SafeArea(
      child: Container(
        height: 65,
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.primaryColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: AppTheme.primaryColor.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: InkWell(
          onTap: _showCartSheet,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                child: Text('$_cartCount items', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              const Text('View Cart & Order', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              Text('Rs. ${_cartTotal.toStringAsFixed(0)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ]),
          ),
        ),
      ),
    );
  }

  void _showCartSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (ctx, scroll) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(4))),
              const SizedBox(height: 16),
              const Text('Your Order', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
              const SizedBox(height: 12),
              Expanded(
                child: _cart.isEmpty
                    ? const Center(child: Text('Cart is empty', style: TextStyle(color: Colors.grey)))
                    : ListView(controller: scroll, children: _cart.values.map((item) => ListTile(
                        title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Rs. ${item.price.toStringAsFixed(0)} each'),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                              onPressed: () { _removeFromCart(item.id); setS(() {}); }),
                          Text('${item.quantity}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                          IconButton(icon: const Icon(Icons.add_circle_outline, color: Colors.green),
                              onPressed: () { _addToCart(_products.firstWhere((p) => p['id'] == item.id)); setS(() {}); }),
                        ]),
                      )).toList()),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Total', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  Text('Rs. ${_cartTotal.toStringAsFixed(0)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryColor, fontSize: 20)),
                ]),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 4,
                ),
                onPressed: _isPlacingOrder ? null : _placeOrder,
                child: _isPlacingOrder
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Place Order → Kitchen 🍳', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _CartItem {
  final String id;
  final String name;
  final double price;
  int quantity;
  _CartItem({required this.id, required this.name, required this.price, required this.quantity});
}
