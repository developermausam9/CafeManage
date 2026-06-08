import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import '../../../../core/presentation/theme/app_theme.dart';
import '../../../../core/network/supabase_config.dart';

class CustomerDeliveryScreen extends StatefulWidget {
  const CustomerDeliveryScreen({super.key});

  @override
  State<CustomerDeliveryScreen> createState() => _CustomerDeliveryScreenState();
}

class _CustomerDeliveryScreenState extends State<CustomerDeliveryScreen>
    with SingleTickerProviderStateMixin {
  final SupabaseClient _client = SupabaseConfig.client;
  late TabController _tabController;

  // Cafe info & state
  String? _cafeId;
  String? _cafeName;
  String? _cafePhone;
  String? _cafeAddress;
  String? _paymentQrUrl;
  bool _isLoading = true;
  String? _errorMessage;

  // Step state
  int _step = 0; // 0=Menu/Cart, 1=Details Checkout, 2=QR Payment (if QR selected), 3=Success/Track

  // Menu data
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _filteredProducts = [];
  String? _selectedCategoryId;
  final _searchCtrl = TextEditingController();

  // Cart
  final Map<String, _CartItem> _cart = {};

  // Form Fields
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _selectedPaymentMethod = 'cash'; // cash, qr, card

  // Submitted delivery info
  Map<String, dynamic>? _submittedDelivery;
  Timer? _trackingTimer;
  bool _isSubmitting = false;

  // Track Existing Delivery Order
  final _trackDeliveryIdCtrl = TextEditingController();
  bool _isTrackingLookup = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _initializeData();
  }

  @override
  void dispose() {
    _trackingTimer?.cancel();
    _tabController.dispose();
    _searchCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _notesCtrl.dispose();
    _trackDeliveryIdCtrl.dispose();
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
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final params = _getQueryParams();
      final rawCafeId = params['cafe_id'];

      // If no valid cafe_id provided, default to the first cafe in database
      if (!_isValidUuid(rawCafeId)) {
        final cafes = await _client.from('cafes').select().limit(1);
        if (cafes.isNotEmpty) {
          _cafeId = cafes.first['id'];
          _cafeName = cafes.first['name'];
          _cafePhone = cafes.first['phone'];
          _cafeAddress = cafes.first['address'];
        } else {
          throw Exception('No cafes found in the database.');
        }
      } else {
        _cafeId = rawCafeId;
        final cafe = await _client.from('cafes').select().eq('id', _cafeId!).maybeSingle();
        if (cafe != null) {
          _cafeName = cafe['name'];
          _cafePhone = cafe['phone'];
          _cafeAddress = cafe['address'];
        } else {
          // fallback to first cafe
          final cafes = await _client.from('cafes').select().limit(1);
          if (cafes.isNotEmpty) {
            _cafeId = cafes.first['id'];
            _cafeName = cafes.first['name'];
            _cafePhone = cafes.first['phone'];
            _cafeAddress = cafes.first['address'];
          } else {
            throw Exception('Selected café does not exist.');
          }
        }
      }

      // Check Cafe subscription plan (Must be Standard or Premium)
      final subRes = await _client
          .from('subscriptions')
          .select('plan_type, is_active')
          .eq('cafe_id', _cafeId!)
          .maybeSingle();
      final planType = subRes != null ? subRes['plan_type'] as String : 'Basic';
      final isActive = subRes != null ? subRes['is_active'] as bool : true;
      if (!isActive || (planType != 'Standard' && planType != 'Premium')) {
        throw Exception('Online food delivery tracking is not enabled for this café. Please contact the administrator.');
      }

      // Load Settings (for payment QR)
      final settings = await _client
          .from('settings')
          .select('payment_qr_url')
          .eq('cafe_id', _cafeId!)
          .maybeSingle();
      if (settings != null) {
        _paymentQrUrl = settings['payment_qr_url'];
      }

      // Load Categories and Products
      final catsRes = await _client.from('categories').select().eq('cafe_id', _cafeId!).order('name');
      final prodsRes = await _client.from('products').select().eq('cafe_id', _cafeId!).eq('is_available', true).order('name');

      _categories = List<Map<String, dynamic>>.from(catsRes);
      _products = List<Map<String, dynamic>>.from(prodsRes);
      _filteredProducts = List<Map<String, dynamic>>.from(_products);

      if (_categories.isNotEmpty) {
        _selectedCategoryId = _categories.first['id'];
        _filterProducts();
      }

      // Check if direct delivery tracking is requested via URL
      final deliveryIdStr = params['delivery_id'];
      if (_isValidUuid(deliveryIdStr)) {
        final delRes = await _client.from('deliveries')
            .select('*')
            .eq('id', deliveryIdStr!)
            .maybeSingle();
        if (delRes != null) {
          _submittedDelivery = Map<String, dynamic>.from(delRes);
          _step = 3; // Live tracking step
          _startTracking();
        }
      }

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load menu: $e';
        _isLoading = false;
      });
    }
  }

  void _filterProducts() {
    setState(() {
      final query = _searchCtrl.text.toLowerCase().trim();
      _filteredProducts = _products.where((p) {
        final matchesCategory = _selectedCategoryId == null || p['category_id'] == _selectedCategoryId;
        final matchesSearch = query.isEmpty || p['name'].toString().toLowerCase().contains(query);
        return matchesCategory && matchesSearch;
      }).toList();
    });
  }

  // ── CART ACTIONS ──────────────────────────────────────────────────────────

  void _addToCart(Map<String, dynamic> product) {
    final id = product['id'] as String;
    final name = product['name'] as String;
    final price = (product['price'] as num).toDouble();

    setState(() {
      if (_cart.containsKey(id)) {
        _cart[id]!.quantity++;
      } else {
        _cart[id] = _CartItem(id: id, name: name, price: price, quantity: 1);
      }
    });
  }

  void _removeFromCart(String productId) {
    setState(() {
      if (_cart.containsKey(productId)) {
        if (_cart[productId]!.quantity > 1) {
          _cart[productId]!.quantity--;
        } else {
          _cart.remove(productId);
        }
      }
    });
  }

  double get _cartTotal => _cart.values.fold(0.0, (sum, item) => sum + (item.price * item.quantity));
  int get _cartCount => _cart.values.fold(0, (sum, item) => sum + item.quantity);

  // ── SUBMIT FLOW ───────────────────────────────────────────────────────────

  Future<void> _submitOrder() async {
    if (_cart.isEmpty) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final orderId = const Uuid().v4();
      final deliveryId = const Uuid().v4();
      final subtotal = _cartTotal;
      const deliveryCharge = 50.00;
      final grandTotal = subtotal + deliveryCharge;

      // 1. Insert POS order of type 'delivery'
      await _client.from('orders').insert({
        'id': orderId,
        'cafe_id': _cafeId,
        'type': 'delivery',
        'status': 'pending',
        'subtotal': subtotal,
        'discount': 0.0,
        'tax_amount': 0.0,
        'service_charge': 0.0,
        'grand_total': grandTotal,
        'payment_method': _selectedPaymentMethod,
        'payment_status': 'unpaid',
      });

      // 2. Insert order items
      final orderItemsList = _cart.values.map((item) => {
        'id': const Uuid().v4(),
        'order_id': orderId,
        'product_id': item.id,
        'product_name': item.name,
        'quantity': item.quantity,
        'unit_price': item.price,
        'total_price': item.price * item.quantity,
        'status': 'added',
      }).toList();

      await _client.from('order_items').insert(orderItemsList);

      // 3. Insert Delivery track record
      final deliveryData = {
        'id': deliveryId,
        'cafe_id': _cafeId,
        'order_id': orderId,
        'customer_name': _nameCtrl.text.trim(),
        'customer_phone': _phoneCtrl.text.trim(),
        'delivery_address': _addressCtrl.text.trim(),
        'status': 'pending',
        'delivery_charge': deliveryCharge,
        'grand_total': grandTotal,
        'payment_method': _selectedPaymentMethod,
        'payment_status': 'pending',
        'notes': _notesCtrl.text.trim(),
      };

      await _client.from('deliveries').insert(deliveryData);

      // 4. Send notification to admin panel
      await _client.from('notifications').insert({
        'cafe_id': _cafeId,
        'title': '📞 New Delivery Order',
        'message': 'Delivery placed by ${_nameCtrl.text.trim()} for Rs. ${grandTotal.toStringAsFixed(0)}',
        'type': 'new_order',
        'is_read': false,
      });

      // Reset cart and load success screen
      _submittedDelivery = deliveryData;
      _cart.clear();
      _startTracking();

      setState(() {
        _step = 3; // Jump to tracking step
        _isSubmitting = false;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit order: $e'), backgroundColor: Colors.red),
      );
      setState(() => _isSubmitting = false);
    }
  }

  void _startTracking() {
    _trackingTimer?.cancel();
    _trackingTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (_submittedDelivery == null) return;
      try {
        final data = await _client
            .from('deliveries')
            .select('*')
            .eq('id', _submittedDelivery!['id'])
            .maybeSingle();
        if (data != null && mounted) {
          setState(() {
            _submittedDelivery = data;
          });
          if (data['status'] == 'delivered' || data['status'] == 'cancelled') {
            _trackingTimer?.cancel();
          }
        }
      } catch (e) {
        debugPrint('Error polling tracking status: $e');
      }
    });
  }

  void _showTrackOrderDialog() {
    _trackDeliveryIdCtrl.clear();
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.track_changes, color: AppTheme.primaryColor),
                  SizedBox(width: 8),
                  Text('Track Existing Order'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Enter your Delivery ID (UUID) to track your order progress in real-time.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _trackDeliveryIdCtrl,
                    decoration: InputDecoration(
                      hintText: 'e.g. 123e4567-e89b-12d3-a456-426614174000',
                      hintStyle: const TextStyle(fontSize: 12, color: Colors.grey),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _isTrackingLookup ? null : () async {
                    final rawId = _trackDeliveryIdCtrl.text.trim();
                    if (!_isValidUuid(rawId)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter a valid Delivery ID (UUID).'), backgroundColor: Colors.red),
                      );
                      return;
                    }
                    setDialogState(() => _isTrackingLookup = true);
                    try {
                      final res = await _client.from('deliveries')
                          .select('*')
                          .eq('id', rawId)
                          .maybeSingle();
                      if (res == null) {
                        throw Exception('Order/Delivery not found. Please check your Delivery ID.');
                      }
                      Navigator.pop(context); // Close dialog
                      setState(() {
                        _submittedDelivery = Map<String, dynamic>.from(res);
                        _step = 3; // Live Tracking
                      });
                      _startTracking();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Order found! Loading status...'), backgroundColor: Colors.green),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: ${e.toString().replaceAll('Exception: ', '')}'), backgroundColor: Colors.red),
                      );
                    } finally {
                      setDialogState(() => _isTrackingLookup = false);
                    }
                  },
                  child: _isTrackingLookup
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Track'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ── UI WIDGETS ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      final isSubError = _errorMessage!.contains('not enabled');
      return Scaffold(
        backgroundColor: Colors.grey.shade50,
        body: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 500),
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isSubError ? AppTheme.primaryColor.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isSubError ? Icons.delivery_dining : Icons.error_outline,
                    size: 64,
                    color: isSubError ? AppTheme.primaryColor : Colors.red,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  isSubError ? 'Delivery Service Unavailable' : 'Error Occurred',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.textSecondary, height: 1.5, fontSize: 14),
                ),
                const SizedBox(height: 32),
                if (!isSubError)
                  ElevatedButton(
                    onPressed: _initializeData,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Retry'),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_cafeName ?? 'Café Delivery', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            if (_step < 3)
              Text('Step ${_step + 1} of 3', style: const TextStyle(fontSize: 12, color: Colors.grey))
            else
              const Text('Live Delivery Tracking 🛵', style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.bold)),
          ],
        ),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.textPrimary,
        elevation: 1,
        centerTitle: false,
        leading: _step > 0 && _step < 3
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    if (_step == 2 && _selectedPaymentMethod != 'qr') {
                      _step = 1;
                    } else {
                      _step--;
                    }
                  });
                },
              )
            : null,
        actions: [
          if (_step == 0)
            IconButton(
              icon: const Icon(Icons.track_changes, color: AppTheme.primaryColor),
              tooltip: 'Track Existing Order',
              onPressed: _showTrackOrderDialog,
            ),
        ],
      ),
      body: _buildCurrentStepView(),
      bottomNavigationBar: _step < 3 ? _buildBottomActionBar() : null,
    );
  }

  Widget _buildCurrentStepView() {
    switch (_step) {
      case 0:
        return _buildMenuSelector();
      case 1:
        return _buildDetailsForm();
      case 2:
        return _buildQrPaymentVerification();
      case 3:
        return _buildLiveTracking();
      default:
        return _buildMenuSelector();
    }
  }

  Widget _buildBottomActionBar() {
    if (_step == 0) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -4))],
        ),
        child: SafeArea(
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _cart.isEmpty
                ? null
                : () {
                    setState(() => _step = 1);
                  },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('$_cartCount items', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const Text('Proceed to Checkout →', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text('Rs. ${_cartTotal.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
          ),
        ),
      );
    }

    if (_step == 1) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -4))],
        ),
        child: SafeArea(
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => setState(() => _step = 0),
                  child: const Text('Back to Menu'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    if (!_formKey.currentState!.validate()) return;
                    if (_selectedPaymentMethod == 'qr') {
                      setState(() => _step = 2);
                    } else {
                      _submitOrder();
                    }
                  },
                  child: _isSubmitting
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Place Order 🚀', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_step == 2) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -4))],
        ),
        child: SafeArea(
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => setState(() => _step = 1),
                  child: const Text('Back'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _submitOrder,
                  child: _isSubmitting
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('I Have Paid ✅', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  // ── STEP 1: MENU ──────────────────────────────────────────────────────────

  Widget _buildMenuSelector() {
    return Column(
      children: [
        // Search & Filter header
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (val) => _filterProducts(),
            decoration: InputDecoration(
              hintText: 'Search delicious dishes...',
              prefixIcon: const Icon(Icons.search, color: Colors.grey),
              filled: true,
              fillColor: Colors.grey.shade100,
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
        ),

        // Categories list
        if (_categories.isNotEmpty)
          Container(
            height: 50,
            color: Colors.white,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final cat = _categories[index];
                final isSelected = _selectedCategoryId == cat['id'];
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0, bottom: 8),
                  child: FilterChip(
                    label: Text(cat['name']),
                    selected: isSelected,
                    selectedColor: AppTheme.primaryColor.withOpacity(0.12),
                    checkmarkColor: AppTheme.primaryColor,
                    labelStyle: TextStyle(
                      color: isSelected ? AppTheme.primaryColor : Colors.grey.shade700,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    onSelected: (selected) {
                      setState(() {
                        _selectedCategoryId = selected ? cat['id'] : null;
                        _filterProducts();
                      });
                    },
                  ),
                );
              },
            ),
          ),

        // Product Catalog grid
        Expanded(
          child: _filteredProducts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.restaurant, size: 54, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      const Text('No products match your filters', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _filteredProducts.length,
                  itemBuilder: (context, index) {
                    final p = _filteredProducts[index];
                    final id = p['id'] as String;
                    final price = (p['price'] as num).toDouble();
                    final inCart = _cart[id]?.quantity ?? 0;

                    return Card(
                      color: Colors.white,
                      elevation: 0.5,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          children: [
                            if (p['image_url'] != null && p['image_url'].toString().isNotEmpty)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  p['image_url'],
                                  width: 80,
                                  height: 80,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(width: 80, height: 80, color: Colors.grey.shade100, child: const Icon(Icons.fastfood, color: Colors.grey)),
                                ),
                              )
                            else
                              Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
                                child: const Icon(Icons.fastfood, color: Colors.grey),
                              ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(p['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Rs. ${price.toStringAsFixed(0)}',
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryColor, fontSize: 15),
                                  ),
                                ],
                              ),
                            ),
                            if (inCart == 0)
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.primaryColor,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                ),
                                onPressed: () => _addToCart(p),
                                child: const Text('ADD'),
                              )
                            else
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.remove_circle_outline, color: AppTheme.primaryColor),
                                    onPressed: () => _removeFromCart(id),
                                  ),
                                  Text('$inCart', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                  IconButton(
                                    icon: const Icon(Icons.add_circle, color: AppTheme.primaryColor),
                                    onPressed: () => _addToCart(p),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ── STEP 2: CHECKOUT DETAILS ──────────────────────────────────────────────

  Widget _buildDetailsForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Checkout Details', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Full Name', prefixIcon: Icon(Icons.person)),
              validator: (val) => val == null || val.trim().isEmpty ? 'Enter your name' : null,
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone Number', prefixIcon: Icon(Icons.phone)),
              validator: (val) => val == null || val.trim().length < 8 ? 'Enter valid phone number' : null,
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _addressCtrl,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Delivery Address', prefixIcon: Icon(Icons.location_on)),
              validator: (val) => val == null || val.trim().isEmpty ? 'Enter your delivery address' : null,
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _notesCtrl,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Special Delivery Instructions (Optional)', prefixIcon: Icon(Icons.notes)),
            ),
            const SizedBox(height: 24),

            const Text('Payment Method', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),

            Card(
              color: Colors.white,
              elevation: 0.5,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Column(
                children: [
                  RadioListTile<String>(
                    title: const Text('Cash on Delivery'),
                    subtitle: const Text('Pay with cash when food arrives'),
                    value: 'cash',
                    groupValue: _selectedPaymentMethod,
                    activeColor: AppTheme.primaryColor,
                    onChanged: (val) => setState(() => _selectedPaymentMethod = val!),
                  ),
                  const Divider(height: 1),
                  RadioListTile<String>(
                    title: const Text('QR Online Payment'),
                    subtitle: const Text('Scan QR code to transfer before delivery'),
                    value: 'qr',
                    groupValue: _selectedPaymentMethod,
                    activeColor: AppTheme.primaryColor,
                    onChanged: (val) => setState(() => _selectedPaymentMethod = val!),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── STEP 3: QR PAYMENT ───────────────────────────────────────────────────

  Widget _buildQrPaymentVerification() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.qr_code_scanner, size: 64, color: AppTheme.primaryColor),
            const SizedBox(height: 16),
            const Text('Scan to Pay', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Please transfer Rs. ${(_cartTotal + 50.00).toStringAsFixed(0)} to complete your booking order.', style: const TextStyle(color: Colors.grey), textAlign: TextAlign.center),
            const SizedBox(height: 24),

            if (_paymentQrUrl != null && _paymentQrUrl!.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  _paymentQrUrl!,
                  width: 250,
                  height: 250,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(Icons.qr_code, size: 200, color: Colors.grey),
                ),
              )
            else
              Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(16)),
                child: const Center(child: Text('QR Code loading or not set up.', style: TextStyle(color: Colors.grey))),
              ),
            
            const SizedBox(height: 24),
            const Text('Click the "I Have Paid" button below to dispatch your delivery order immediately.', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  // ── STEP 4: REAL-TIME TRACKING ────────────────────────────────────────────

  Widget _detailRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color ?? AppTheme.textPrimary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveTracking() {
    if (_submittedDelivery == null) {
      return const Center(child: Text('Loading tracking...'));
    }

    final status = _submittedDelivery!['status'] as String? ?? 'pending';
    final riderName = _submittedDelivery!['driver_name'] as String?;
    final riderPhone = _submittedDelivery!['driver_phone'] as String?;

    // Status mapping for visual tracker
    int activeIndex = 0;
    if (status == 'preparing') activeIndex = 1;
    if (status == 'out_for_delivery') activeIndex = 2;
    if (status == 'delivered') activeIndex = 3;
    if (status == 'cancelled') activeIndex = -1;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Order Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppTheme.primaryColor, Colors.orangeAccent]),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('YOUR DELIVERY ORDER', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 4),
                Text('Order ID: ${_submittedDelivery!['id'].toString().substring(0, 8).toUpperCase()}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
                const SizedBox(height: 12),
                Text('Grand Total: Rs. ${(_submittedDelivery!['grand_total'] as num).toStringAsFixed(0)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 16)),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Real-time Status Progress Bar
          const Text('Delivery Status', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),

          if (activeIndex == -1) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  const Icon(Icons.cancel_outlined, color: Colors.red, size: 28),
                  const SizedBox(width: 12),
                  Text('This order has been cancelled.', style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.bold, fontSize: 15)),
                ],
              ),
            ),
          ] else ...[
            _buildStatusStep('Order Placed', 'Your request has been received by the kitchen.', activeIndex >= 0, isLast: false),
            _buildStatusStep('Kitchen Preparing', 'Chef is preparing your hot meals.', activeIndex >= 1, isLast: false),
            _buildStatusStep('Out for Delivery', 'Driver has picked up and is on the way.', activeIndex >= 2, isLast: false),
            _buildStatusStep('Delivered', 'Enjoy your fresh food!', activeIndex >= 3, isLast: true),
          ],
          const SizedBox(height: 24),

          // Courier Detail Card
          if (status == 'out_for_delivery' && riderName != null) ...[
            Card(
              color: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppTheme.primaryColor,
                  child: Icon(Icons.motorcycle, color: Colors.white),
                ),
                title: Text(riderName, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(riderPhone ?? 'No Contact Number'),
                trailing: IconButton(
                  icon: const Icon(Icons.phone_in_talk, color: Colors.green),
                  onPressed: () {
                    // Trigger dialer if possible
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Payment Details Card
          const Text('Payment Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
            child: Column(
              children: [
                _detailRow('Method', (_submittedDelivery!['payment_method'] as String? ?? 'cash').toUpperCase()),
                const Divider(),
                _detailRow(
                  'Payment Status',
                  _submittedDelivery!['payment_status'] == 'paid'
                      ? 'PAID & VERIFIED'
                      : (_submittedDelivery!['payment_method'] == 'qr' ? 'PENDING VERIFICATION' : 'PENDING ON ARRIVAL'),
                  color: _submittedDelivery!['payment_status'] == 'paid'
                      ? Colors.green
                      : (_submittedDelivery!['payment_method'] == 'qr' ? Colors.orange : Colors.blue),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Address Summary card
          const Text('Delivery Address', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.location_on, color: Colors.grey, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_submittedDelivery!['customer_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(_submittedDelivery!['delivery_address'] ?? ''),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),

          // Copy tracking link button
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              final trackingUrl = "${Uri.base.origin}${Uri.base.path}?delivery_id=${_submittedDelivery!['id']}&cafe_id=$_cafeId";
              Clipboard.setData(ClipboardData(text: trackingUrl));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Tracking Link copied! Bookmark it to check status later.')),
              );
            },
            icon: const Icon(Icons.link),
            label: const Text('Copy Direct Tracking Link'),
          ),
          const SizedBox(height: 12),

          // Return home button
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              setState(() {
                _step = 0;
                _submittedDelivery = null;
                _trackingTimer?.cancel();
                _trackDeliveryIdCtrl.clear();
              });
            },
            child: const Text('Order Something Else'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusStep(String title, String description, bool isCompleted, {required bool isLast}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isCompleted ? AppTheme.primaryColor : Colors.grey.shade300,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: isCompleted ? [BoxShadow(color: AppTheme.primaryColor.withOpacity(0.4), blurRadius: 6)] : null,
              ),
              child: isCompleted ? const Icon(Icons.check, color: Colors.white, size: 14) : null,
            ),
            if (!isLast)
              Container(
                width: 2.5,
                height: 45,
                color: isCompleted ? AppTheme.primaryColor : Colors.grey.shade300,
              ),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: isCompleted ? AppTheme.textPrimary : Colors.grey.shade500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(
                  fontSize: 12.5,
                  color: isCompleted ? AppTheme.textSecondary : Colors.grey.shade400,
                ),
              ),
            ],
          ),
        ),
      ],
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
