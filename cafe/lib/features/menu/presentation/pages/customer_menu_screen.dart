import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/presentation/theme/app_theme.dart';
import '../../../../core/network/supabase_config.dart';

class CustomerMenuScreen extends StatefulWidget {
  const CustomerMenuScreen({super.key});

  @override
  State<CustomerMenuScreen> createState() => _CustomerMenuScreenState();
}

class _CustomerMenuScreenState extends State<CustomerMenuScreen> {
  final SupabaseClient _client = SupabaseConfig.client;

  String? _cafeId;
  String? _roomId;
  String? _cafeName;
  String? _roomNumber;
  bool _isLoading = true;
  String? _errorMessage;

  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _filteredProducts = [];
  String? _selectedCategoryId;
  final _searchCtrl = TextEditingController();

  // Cart: Map of product_id -> CartItem
  final Map<String, _CartItem> _cart = {};

  bool _isPlacingOrder = false;
  bool _orderPlaced = false;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Map<String, String> _getQueryParams() {
    final params = Map<String, String>.from(Uri.base.queryParameters);
    final fragment = Uri.base.fragment;
    if (fragment.contains('?')) {
      final queryString = fragment.split('?').last;
      final parts = queryString.split('&');
      for (var part in parts) {
        final kv = part.split('=');
        if (kv.length == 2) {
          params[kv[0]] = Uri.decodeComponent(kv[1]);
        }
      }
    }
    return params;
  }

  Future<void> _initializeData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final params = _getQueryParams();
    _cafeId = params['cafe_id'];
    _roomId = params['room_id'];

    if (_cafeId == null || _cafeId!.isEmpty || _roomId == null || _roomId!.isEmpty) {
      setState(() {
        _errorMessage = 'Invalid QR code URL. Missing room configuration parameters.';
        _isLoading = false;
      });
      return;
    }

    try {
      // 1. Fetch Cafe Details
      final cafeRes = await _client.from('cafes').select('name').eq('id', _cafeId!).single();
      _cafeName = cafeRes['name'];

      // 2. Fetch Room Details
      final roomRes = await _client.from('rooms').select('room_number').eq('id', _roomId!).single();
      _roomNumber = roomRes['room_number'];

      // 3. Fetch Categories & Products
      final categoriesRes = await _client.from('categories').select().eq('cafe_id', _cafeId!).order('name');
      _categories = List<Map<String, dynamic>>.from(categoriesRes);

      final productsRes = await _client.from('products').select().eq('cafe_id', _cafeId!).eq('is_available', true).order('name');
      _products = List<Map<String, dynamic>>.from(productsRes);
      _filteredProducts = List<Map<String, dynamic>>.from(_products);

      if (_categories.isNotEmpty) {
        _selectedCategoryId = null; // 'All' selected by default
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load menu: $e';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _filterProducts() {
    final query = _searchCtrl.text.toLowerCase().trim();
    setState(() {
      _filteredProducts = _products.where((p) {
        final matchesCategory = _selectedCategoryId == null || p['category_id'] == _selectedCategoryId;
        final matchesSearch = p['name'].toString().toLowerCase().contains(query) ||
            (p['description'] != null && p['description'].toString().toLowerCase().contains(query));
        return matchesCategory && matchesSearch;
      }).toList();
    });
  }

  void _addToCart(Map<String, dynamic> product) {
    final pId = product['id'] as String;
    setState(() {
      if (_cart.containsKey(pId)) {
        _cart[pId]!.quantity++;
      } else {
        _cart[pId] = _CartItem(
          id: pId,
          name: product['name'] as String,
          price: (product['price'] as num).toDouble(),
          quantity: 1,
        );
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

  double get _cartTotal {
    return _cart.values.fold(0.0, (sum, item) => sum + (item.price * item.quantity));
  }

  int get _cartCount {
    return _cart.values.fold(0, (sum, item) => sum + item.quantity);
  }

  Future<void> _placeOrder() async {
    if (_cart.isEmpty) return;

    setState(() => _isPlacingOrder = true);

    try {
      final orderId = const Uuid().v4();
      final subtotal = _cartTotal;
      // Fetch default settings for tax / service charge if any
      double taxPercentage = 0.0;
      double servicePercentage = 0.0;

      final settingsRes = await _client.from('settings').select('tax_percentage, service_charge_percentage').eq('cafe_id', _cafeId!).maybeSingle();
      if (settingsRes != null) {
        taxPercentage = (settingsRes['tax_percentage'] as num?)?.toDouble() ?? 0.0;
        servicePercentage = (settingsRes['service_charge_percentage'] as num?)?.toDouble() ?? 0.0;
      }

      final taxAmount = subtotal * (taxPercentage / 100);
      final serviceCharge = subtotal * (servicePercentage / 100);
      final grandTotal = subtotal + taxAmount + serviceCharge;

      // 1. Insert Order
      await _client.from('orders').insert({
        'id': orderId,
        'cafe_id': _cafeId,
        'room_id': _roomId,
        'type': 'dine_in', // Dine-in is used for room service orders
        'status': 'pending', // Pending routes to POS kitchen displays
        'subtotal': subtotal,
        'discount': 0.0,
        'tax_amount': taxAmount,
        'service_charge': serviceCharge,
        'grand_total': grandTotal,
        'payment_method': 'due', // Unpaid/Due to pay at room checkout
        'payment_status': 'unpaid',
        'paid_amount': 0.0,
        'remaining_due': grandTotal,
      });

      // 2. Insert Order Items
      final orderItemsData = _cart.values.map((item) => {
        'id': const Uuid().v4(),
        'order_id': orderId,
        'product_id': item.id,
        'quantity': item.quantity,
        'price': item.price,
        'status': 'added',
      }).toList();

      await _client.from('order_items').insert(orderItemsData);

      // Create a notification for POS
      await _client.from('notifications').insert({
        'cafe_id': _cafeId,
        'title': 'New Room Service Order',
        'message': 'Room $_roomNumber placed an order for Rs. ${grandTotal.toStringAsFixed(0)}',
        'type': 'new_order',
        'is_read': false,
      });

      setState(() {
        _orderPlaced = true;
        _cart.clear();
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to place order: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isPlacingOrder = false);
    }
  }

  void _showCartSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Your Order Cart', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                  const Divider(),
                  if (_cart.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40.0),
                      child: Center(child: Text('Your cart is empty', style: TextStyle(color: Colors.grey))),
                    )
                  else ...[
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: _cart.values.map((item) {
                          return ListTile(
                            title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('Rs. ${item.price.toStringAsFixed(0)}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                                  onPressed: () {
                                    _removeFromCart(item.id);
                                    setSheetState(() {});
                                    setState(() {}); // Sync main screen
                                    if (_cart.isEmpty) Navigator.pop(context);
                                  },
                                ),
                                Text('${item.quantity}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline, color: Colors.green),
                                  onPressed: () {
                                    final prod = _products.firstWhere((p) => p['id'] == item.id);
                                    _addToCart(prod);
                                    setSheetState(() {});
                                    setState(() {}); // Sync main screen
                                  },
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                        Text('Rs. ${_cartTotal.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryColor, fontSize: 20)),
                      ],
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _isPlacingOrder
                          ? null
                          : () {
                              Navigator.pop(context);
                              _placeOrder();
                            },
                      child: _isPlacingOrder
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('Place Order (Send to Kitchen)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_errorMessage != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.qr_code_scanner, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text(_errorMessage!, style: const TextStyle(fontSize: 18, color: AppTheme.textSecondary), textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );
    }

    if (_orderPlaced) {
      return _buildSuccessScreen();
    }

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_cafeName ?? 'Hotel Room Service', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text('Room $_roomNumber Service', style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
          ],
        ),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
      ),
      bottomNavigationBar: _cart.isNotEmpty ? _buildCartBar() : null,
      body: Column(
        children: [
          // Search & Filter Panel
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Search delicious food, snacks, drinks...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: AppTheme.backgroundColor,
                  ),
                  onChanged: (_) => _filterProducts(),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 40,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _categories.length + 1,
                    itemBuilder: (context, index) {
                      final isAll = index == 0;
                      final isSelected = isAll ? _selectedCategoryId == null : _selectedCategoryId == _categories[index - 1]['id'];
                      final label = isAll ? 'All Items' : _categories[index - 1]['name'] as String;

                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ChoiceChip(
                          label: Text(label),
                          selected: isSelected,
                          onSelected: (_) {
                            setState(() {
                              _selectedCategoryId = isAll ? null : _categories[index - 1]['id'];
                              _filterProducts();
                            });
                          },
                          selectedColor: AppTheme.primaryColor,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : AppTheme.textPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // Menu Grid/List
          Expanded(
            child: _filteredProducts.isEmpty
                ? const Center(child: Text('No food items found matching your filters.', style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _filteredProducts.length,
                    itemBuilder: (context, index) {
                      final product = _filteredProducts[index];
                      final pId = product['id'] as String;
                      final count = _cart[pId]?.quantity ?? 0;

                      return Card(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        color: Colors.white,
                        elevation: 1,
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Row(
                            children: [
                              // Food Image or Placeholder
                              Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  color: AppTheme.backgroundColor,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: product['image_url'] != null && product['image_url'].toString().isNotEmpty
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(product['image_url'], fit: BoxFit.cover),
                                      )
                                    : const Icon(Icons.fastfood, color: Colors.grey),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(product['name'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                    if (product['description'] != null)
                                      Text(product['description'] as String, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                    const SizedBox(height: 6),
                                    Text('Rs. ${(product['price'] as num).toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),

                              // Quantity Selector
                              if (count > 0)
                                Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.remove_circle, color: Colors.red),
                                      onPressed: () => _removeFromCart(pId),
                                    ),
                                    Text('$count', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                    IconButton(
                                      icon: const Icon(Icons.add_circle, color: Colors.green),
                                      onPressed: () => _addToCart(product),
                                    ),
                                  ],
                                )
                              else
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
                                  onPressed: () => _addToCart(product),
                                  child: const Text('Add'),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartBar() {
    return SafeArea(
      child: Container(
        height: 65,
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.primaryColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryColor.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: InkWell(
          onTap: _showCartSheet,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.shopping_bag, color: Colors.white),
                    const SizedBox(width: 8),
                    Text('$_cartCount Items selected', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
                Row(
                  children: [
                    Text('Rs. ${_cartTotal.toStringAsFixed(0)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessScreen() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.restaurant, color: Colors.green, size: 80),
              const SizedBox(height: 24),
              const Text('Order Sent to Kitchen!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text(
                'Your room service order has been received and is being prepared by our chefs. It will be brought to your room shortly.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary, height: 1.5),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(200, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  setState(() {
                    _orderPlaced = false;
                  });
                  _initializeData();
                },
                child: const Text('Order More Items'),
              ),
            ],
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
