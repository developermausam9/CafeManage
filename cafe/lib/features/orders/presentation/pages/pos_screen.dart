import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/network/supabase_config.dart';
import '../../../../core/presentation/theme/app_theme.dart';
import '../../../../core/presentation/widgets/app_button.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../menu/presentation/providers/product_provider.dart';
import '../../../menu/data/models/product_model.dart';
import '../providers/pos_provider.dart';
import '../providers/table_provider.dart';
import '../../data/models/table_model.dart';
import '../../data/models/order_status_history_model.dart';
import '../models/cart_item.dart';
import '../widgets/checkout_dialog.dart';
import 'receipt_screen.dart';
import '../../../../core/presentation/providers/printer_provider.dart';
import '../../../../core/services/models/printer_config_model.dart';


class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  String _searchQuery = '';
  String _selectedCategory = 'All';
  final List<String> _categories = ['All', 'Food', 'Drinks', 'Cigarettes', 'Snacks', 'Retail'];
  String _currentView = 'Tables';
  Map<String, String> _categoryMap = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cafeId = context.read<AuthProvider>().cafeId;
      if (cafeId != null) {
        context.read<ProductProvider>().loadProducts(cafeId);
        context.read<TableProvider>().init(cafeId);
        context.read<PosProvider>().fetchSettings(cafeId);
        _loadCategories();
      }
    });
  }

  Future<void> _loadCategories() async {
    try {
      final client = SupabaseConfig.client;
      final res = await client.from('categories').select('id, name');
      final Map<String, String> newMap = {};
      for (var item in res) {
        newMap[item['id'] as String] = item['name'] as String;
      }
      if (mounted) {
        setState(() {
          _categoryMap = newMap;
        });
      }
    } catch (e) {
      debugPrint("Error loading categories: $e");
    }
  }

  String _getNormalizedCategory(String? categoryIdOrName) {
    if (categoryIdOrName == null) return 'All';
    String name = _categoryMap[categoryIdOrName] ?? categoryIdOrName;
    final lower = name.toLowerCase();
    if (lower == 'food' || lower.contains('food') || lower.contains('meal') || lower.contains('momo') || lower.contains('combo')) {
      return 'Food';
    }
    if (lower == 'drinks' || lower.contains('drink') || lower.contains('beverage') || lower.contains('coffee') || lower.contains('tea')) {
      return 'Drinks';
    }
    if (lower == 'cigarettes' || lower.contains('cigarette') || lower.contains('smoke') || lower.contains('surya')) {
      return 'Cigarettes';
    }
    if (lower == 'snacks' || lower.contains('snack') || lower.contains('chips')) {
      return 'Snacks';
    }
    if (lower == 'retail' || lower.contains('retail')) {
      return 'Retail';
    }
    return name;
  }

  void _checkout() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => CheckoutDialog(
        onConfirm: (customerDueId) async {
          final posProvider = context.read<PosProvider>();
          final cafeId = context.read<AuthProvider>().cafeId;
          final staffId = context.read<AuthProvider>().currentProfile?.id;
          
          if (cafeId == null || staffId == null) return;

          final success = await posProvider.finalizePayment(cafeId, staffId, customerDueId: customerDueId);
          
          if (success && mounted) {
            setState(() {
              _currentView = 'Tables';
            });
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ReceiptScreen()),
            );
          } else if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(posProvider.errorMessage ?? 'Checkout failed')),
            );
          }
        },
      ),
    );
  }

  void _sendToKitchen() async {
    final posProvider = context.read<PosProvider>();
    final cafeId = context.read<AuthProvider>().cafeId;
    final staffId = context.read<AuthProvider>().currentProfile?.id;

    if (cafeId == null || staffId == null) return;

    final List<CartItem> itemsToPrint = List<CartItem>.from(posProvider.cart);
    final String tableNumber = posProvider.orderType == 'Dine-in' ? posProvider.selectedTable : '';
    final String orderType = posProvider.orderType;

    final success = await posProvider.sendToKitchen(cafeId, staffId);

    if (success) {
      try {
        final printerProvider = context.read<PrinterProvider>();
        if (printerProvider.kitchenConfig != null && printerProvider.kitchenConfig!.isEnabled) {
          await printerProvider.printKOTRouted(
            tableNumber: tableNumber,
            orderType: orderType,
            items: itemsToPrint,
          );
        }
      } catch (e) {
        debugPrint('KOT Print failed: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('KOT sent to kitchen, but printer failed: $e'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'KOT sent to kitchen successfully!' : (posProvider.errorMessage ?? 'Failed to send KOT')),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  void _editItemNote(CartItem item, PosProvider posProvider) {
    final controller = TextEditingController(text: item.note);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Item Note: ${item.product.name}'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'e.g. No onions, extra spicy, warm',
            border: OutlineInputBorder(),
          ),
          maxLines: 2,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              posProvider.updateNote(item.product, controller.text);
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _buildPOSViewToggle(PosProvider posProvider, bool isDesktop) {
    final showTables = posProvider.orderType == 'Dine-in';
    
    return Container(
      color: AppTheme.surfaceColor,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (showTables)
                    _buildToggleButton(
                      label: 'Tables',
                      icon: Icons.table_bar,
                      isSelected: _currentView == 'Tables',
                      onPressed: () {
                        setState(() => _currentView = 'Tables');
                      },
                    ),
                  if (showTables) const SizedBox(width: 8),
                  _buildToggleButton(
                    label: 'Products',
                    icon: Icons.fastfood,
                    isSelected: _currentView == 'Products',
                    onPressed: () {
                      setState(() => _currentView = 'Products');
                    },
                  ),
                  const SizedBox(width: 8),
                  _buildToggleButton(
                    label: 'Current Order',
                    icon: Icons.shopping_cart,
                    isSelected: _currentView == 'Current Order',
                    onPressed: () {
                      setState(() => _currentView = 'Current Order');
                    },
                  ),
                ],
              ),
            ),
          ),
          
          if (posProvider.orderType == 'Dine-in') ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: posProvider.activeTableId != null ? AppTheme.primaryColor.withOpacity(0.1) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: posProvider.activeTableId != null ? AppTheme.primaryColor.withOpacity(0.3) : Colors.grey.shade300,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.table_restaurant_outlined,
                    size: 16,
                    color: posProvider.activeTableId != null ? AppTheme.primaryColor : AppTheme.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    posProvider.activeTableId != null
                        ? 'Table ${posProvider.selectedTable}'
                        : 'No Table Selected',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: posProvider.activeTableId != null ? AppTheme.primaryColor : AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildToggleButton({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onPressed,
  }) {
    return Container(
      height: 40,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16, color: isSelected ? Colors.white : AppTheme.primaryColor),
        label: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.white : AppTheme.primaryColor,
          ),
        ),
        style: ElevatedButton.styleFrom(
          elevation: isSelected ? 2 : 0,
          backgroundColor: isSelected ? AppTheme.primaryColor : Colors.white,
          side: BorderSide(color: AppTheme.primaryColor.withOpacity(0.3)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 950 && size.width > size.height;
    final posProvider = context.watch<PosProvider>();

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Row(
        children: [
          // Left Side: View Toggle + Sub-views
          Expanded(
            flex: 2,
            child: Column(
              children: [
                _buildPOSViewToggle(posProvider, isDesktop),
                const Divider(height: 1, color: Colors.black12),
                Expanded(
                  child: Builder(
                    builder: (context) {
                      if (_currentView == 'Tables' && posProvider.orderType == 'Dine-in') {
                        return Column(
                          children: [
                            _buildTableGridHeader(),
                            Expanded(child: _buildTableGrid()),
                          ],
                        );
                      } else if (_currentView == 'Current Order') {
                        return Container(
                          color: AppTheme.surfaceColor,
                          child: _buildCart(posProvider),
                        );
                      } else {
                        return Column(
                          children: [
                            _buildProductHeader(posProvider),
                            Expanded(child: _buildProductGrid(isDesktop)),
                          ],
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          
          // Right Side: Cart (Visible side-by-side on desktop)
          if (isDesktop)
            Expanded(
              flex: 1,
              child: Container(
                color: AppTheme.surfaceColor,
                child: _buildCart(posProvider),
              ),
            ),
        ],
      ),
      // Mobile Cart Bottom Sheet trigger
      bottomSheet: !isDesktop ? _buildMobileCartSummary(posProvider) : null,
    );
  }

  Widget _buildTableGridHeader() {
    return Container(
      color: AppTheme.surfaceColor,
      width: double.infinity,
      padding: const EdgeInsets.all(20.0),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select a Table to Order',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
          ),
          SizedBox(height: 4),
          Text(
            'Manage customer dine-in sessions, preparing orders, and billing.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildTableGrid() {
    return Consumer<TableProvider>(
      builder: (context, tableProvider, child) {
        if (tableProvider.isLoading && tableProvider.tables.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        final activeTables = tableProvider.tables;

        if (activeTables.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.table_bar, size: 64, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                const Text('No tables configured.', style: TextStyle(fontSize: 18, color: AppTheme.textSecondary)),
                const SizedBox(height: 8),
                const Text('Admins can configure tables in the Tables tab.', style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }

        final double screenWidth = MediaQuery.of(context).size.width;
        int crossAxisCount = 2;
        double aspectRatio = 1.25;
        
        if (screenWidth > 1200) {
          crossAxisCount = 5;
        } else if (screenWidth > 800) {
          crossAxisCount = 4;
        } else if (screenWidth > 500) {
          crossAxisCount = 3;
        }

        return GridView.builder(
          padding: const EdgeInsets.all(20),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: aspectRatio,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: activeTables.length,
          itemBuilder: (context, index) {
            final table = activeTables[index];
            return _buildTableCard(table);
          },
        );
      },
    );
  }

  Widget _buildTableCard(TableModel table) {
    Color cardColor;
    Color textColor;
    IconData icon;

    switch (table.status) {
      case 'preparing':
        cardColor = Colors.orange.shade50;
        textColor = Colors.orange.shade800;
        icon = Icons.restaurant;
        break;
      case 'ready':
        cardColor = Colors.blue.shade50;
        textColor = Colors.blue.shade800;
        icon = Icons.dining_outlined;
        break;
      case 'billing_pending':
        cardColor = Colors.purple.shade50;
        textColor = Colors.purple.shade800;
        icon = Icons.receipt_long;
        break;
      case 'occupied':
        cardColor = Colors.grey.shade100;
        textColor = Colors.grey.shade800;
        icon = Icons.people;
        break;
      default:
        cardColor = Colors.green.shade50;
        textColor = Colors.green.shade800;
        icon = Icons.table_restaurant;
    }

    return InkWell(
      onTap: () {
        final cafeId = context.read<AuthProvider>().cafeId;
        final role = context.read<AuthProvider>().currentProfile?.role;
        if (cafeId != null) {
          context.read<PosProvider>().selectTable(table, cafeId, userRole: role);
          setState(() {
            _currentView = 'Products';
          });
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: textColor.withOpacity(0.2), width: 1.5),
          boxShadow: [
            BoxShadow(color: textColor.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2)),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(icon, color: textColor, size: 28),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: textColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      table.status.toUpperCase(),
                      style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 10),
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    table.name,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: textColor.withOpacity(0.9)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${table.capacity} Pax',
                    style: TextStyle(color: textColor.withOpacity(0.7), fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProductHeader(PosProvider posProvider) {
    return Container(
      color: AppTheme.surfaceColor,
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Row(
            children: [
              if (posProvider.orderType == 'Dine-in' && posProvider.activeTableId != null) ...[
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                  onPressed: () {
                    // Deselect table
                    posProvider.activeTableId = null;
                    posProvider.activeOrder = null;
                    posProvider.clearCart();
                    setState(() {
                      _currentView = 'Tables';
                    });
                  },
                  tooltip: 'Back to Table Grid',
                ),
                Text(
                  '${posProvider.selectedTable}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: AppTheme.primaryColor),
                ),
                if (posProvider.activeOrder != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'ACTIVE ORDER: #${posProvider.activeOrder!.billNumber}',
                      style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.bold, fontSize: 10),
                    ),
                  ),
                ],
                const Spacer(),
              ],
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search products...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: AppTheme.backgroundColor,
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final cat = _categories[index];
                final isSelected = _selectedCategory == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ChoiceChip(
                    label: Text(cat),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) setState(() => _selectedCategory = cat);
                    },
                    selectedColor: AppTheme.primaryColor,
                    labelStyle: TextStyle(color: isSelected ? Colors.white : AppTheme.textPrimary),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductGrid(bool isDesktop) {
    final posProvider = context.read<PosProvider>();
    return Consumer<ProductProvider>(
      builder: (context, provider, child) {
        if (provider.state == ProductState.loading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (provider.products.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.restaurant_menu, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                const Text(
                  'No products found in menu.',
                  style: TextStyle(fontSize: 18, color: AppTheme.textSecondary, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text('Add products from Menu to start selling.', style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }

        final filteredProducts = provider.products.where((p) {
          final isAvailable = p.isAvailable && (!p.isStockTracked || p.stockQuantity >= 0);
          final normCat = _getNormalizedCategory(p.categoryId);
          final matchesCategory = _selectedCategory == 'All' || normCat.toLowerCase() == _selectedCategory.toLowerCase();
          final matchesSearch = p.name.toLowerCase().contains(_searchQuery.toLowerCase());
          return isAvailable && matchesCategory && matchesSearch;
        }).toList();

        if (filteredProducts.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.search_off, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                const Text(
                  'No matching products found.',
                  style: TextStyle(fontSize: 18, color: AppTheme.textSecondary, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _searchQuery = '';
                      _selectedCategory = 'All';
                    });
                  },
                  child: const Text('Clear Filters'),
                ),
              ],
            ),
          );
        }

        return GridView.builder(
          padding: EdgeInsets.all(isDesktop ? 24.0 : 16.0),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: isDesktop ? 3 : 2,
            childAspectRatio: 0.85,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: filteredProducts.length,
          itemBuilder: (context, index) {
            final product = filteredProducts[index];
            return InkWell(
              onTap: () {
                final role = context.read<AuthProvider>().currentProfile?.role?.toLowerCase() ?? 'admin';
                final isPostKOT = posProvider.activeOrder != null && 
                    posProvider.activeOrder!.status != 'active' && 
                    posProvider.activeOrder!.status != 'pending';
                
                if (role == 'cashier' && isPostKOT) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Cashiers cannot add items after KOT without admin permission.'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                  return;
                }

                if (posProvider.orderType == 'Dine-in' && posProvider.activeTableId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please select a table first for Dine-in orders.'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  setState(() {
                    _currentView = 'Tables';
                  });
                  return;
                }
                context.read<PosProvider>().addToCart(product);
              },
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                        ),
                        child: const Icon(Icons.fastfood, size: 40, color: Colors.grey),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(product.name, style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 1),
                          const SizedBox(height: 4),
                          Text('Rs. ${product.sellingPrice.toStringAsFixed(2)}', style: const TextStyle(color: AppTheme.primaryColor)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStatusTimeline(PosProvider provider) {
    if (provider.activeOrder == null || provider.orderStatusHistory.isEmpty) {
      return const SizedBox.shrink();
    }

    final history = provider.orderStatusHistory;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.track_changes, size: 18, color: Colors.deepOrange),
              const SizedBox(width: 8),
              const Text(
                'Live Order Journey',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: AppTheme.textPrimary,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.deepOrange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${history.length} updates',
                  style: const TextStyle(
                    color: Colors.deepOrange,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Vertical timeline list
          ...history.map((event) {
            final idx = history.indexOf(event);
            final isLast = idx == history.length - 1;
            
            // Format time
            final localTime = event.changedAt.toLocal();
            final timeStr = '${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}';
            
            Color themeColor;
            IconData icon;
            
            switch (event.status.toLowerCase()) {
              case 'pending':
                themeColor = Colors.orange;
                icon = Icons.hourglass_top_rounded;
                break;
              case 'preparing':
                themeColor = Colors.blue;
                icon = Icons.cookie_rounded;
                break;
              case 'ready':
                themeColor = Colors.cyan;
                icon = Icons.check_circle_outline_rounded;
                break;
              case 'served':
                themeColor = Colors.teal;
                icon = Icons.room_service_rounded;
                break;
              case 'billed':
                themeColor = Colors.purple;
                icon = Icons.receipt_long_rounded;
                break;
              case 'completed':
                themeColor = Colors.green;
                icon = Icons.payment_rounded;
                break;
              case 'cancelled':
                themeColor = Colors.red;
                icon = Icons.cancel_rounded;
                break;
              default:
                themeColor = Colors.grey;
                icon = Icons.circle;
            }

            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: themeColor.withOpacity(0.08),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, size: 14, color: themeColor),
                      ),
                      if (!isLast)
                        Expanded(
                          child: Container(
                            width: 1.5,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            color: Colors.grey.shade200,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                event.status.toUpperCase(),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: themeColor,
                                ),
                              ),
                              Text(
                                timeStr,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            event.changedByName != null
                                ? 'by ${event.changedByName}'
                                : 'System auto-update',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildCart(PosProvider posProvider) {
    final role = context.watch<AuthProvider>().currentProfile?.role?.toLowerCase() ?? 'admin';
    final isWaiter = role == 'waiter';
    final hideBillingForWaiter = isWaiter;
    
    final isPostKOT = posProvider.activeOrder != null && 
        posProvider.activeOrder!.status != 'active' && 
        posProvider.activeOrder!.status != 'pending';
    
    final bool disableClearCart = role == 'cashier' && isPostKOT;

    return Column(
      children: [
        // Cart Header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                posProvider.activeTableId != null ? 'Table ${posProvider.selectedTable} Order' : 'Current Order',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.delete_sweep, color: Colors.red),
                onPressed: disableClearCart ? null : () => posProvider.clearCart(),
                tooltip: 'Clear Cart',
              ),
            ],
          ),
        ),
        
        // Order Type & Table Selection
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: posProvider.orderType,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Type', isDense: true),
                  items: ['Dine-in', 'Takeaway', 'Delivery'].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (val) {
                    posProvider.setOrderType(val!);
                    setState(() {
                      _currentView = val == 'Dine-in' ? 'Tables' : 'Products';
                    });
                  },
                ),
              ),
              if (posProvider.orderType == 'Dine-in') ...[
                if (posProvider.activeTableId == null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Consumer<TableProvider>(
                      builder: (context, tableProvider, child) {
                        final tables = tableProvider.tables;
                        return DropdownButtonFormField<String>(
                          value: tables.any((t) => t.id == posProvider.activeTableId) ? posProvider.activeTableId : (tables.isNotEmpty ? tables.first.id : null),
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Table', isDense: true),
                          items: tables.map((t) => DropdownMenuItem(value: t.id, child: Text(t.name))).toList(),
                          onChanged: (val) {
                            final selected = tables.firstWhere((t) => t.id == val);
                            final cafeId = context.read<AuthProvider>().cafeId;
                            final role = context.read<AuthProvider>().currentProfile?.role;
                            if (cafeId != null) {
                              posProvider.selectTable(selected, cafeId, userRole: role);
                              setState(() {
                                _currentView = 'Products';
                              });
                            }
                          },
                        );
                      },
                    ),
                  ),
                ] else ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.primaryColor.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.table_restaurant, color: AppTheme.primaryColor, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Table ${posProvider.selectedTable}',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryColor, fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            constraints: const BoxConstraints(),
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.close, size: 16, color: AppTheme.primaryColor),
                            onPressed: () {
                              posProvider.activeTableId = null;
                              posProvider.activeOrder = null;
                              posProvider.clearCart();
                              setState(() {
                                _currentView = 'Tables';
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),

        // Cart Items
        Expanded(
          child: posProvider.cart.isEmpty
              ? const Center(child: Text('Cart is empty', style: TextStyle(color: AppTheme.textSecondary)))
              : ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    ...posProvider.cart.map((item) => _buildCartItemTile(item, posProvider)),
                    if (posProvider.activeOrder != null) _buildStatusTimeline(posProvider),
                  ],
                ),
        ),
        
        // Billing Summary
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            border: Border(top: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Column(
            children: [
              _buildSummaryRow('Subtotal', posProvider.subtotal),
              _buildSummaryRow('VAT (13%)', posProvider.taxAmount),
              const Divider(),
              _buildSummaryRow('Grand Total', posProvider.grandTotal, isBold: true, size: 20),
              const SizedBox(height: 16),
              
              // Status Badge if order exists
              if (posProvider.activeOrder != null) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Order Status:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: posProvider.activeOrder!.status == 'ready' 
                            ? Colors.teal.shade50 
                            : (posProvider.activeOrder!.status == 'served' ? Colors.indigo.shade50 : Colors.amber.shade50),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        posProvider.activeOrder!.status.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: posProvider.activeOrder!.status == 'ready' 
                              ? Colors.teal.shade700 
                              : (posProvider.activeOrder!.status == 'served' ? Colors.indigo.shade700 : Colors.amber.shade900),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              
              Row(
                children: [
                  // Action buttons
                  if (posProvider.orderType == 'Dine-in') ...[
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: posProvider.cart.isEmpty ? null : _sendToKitchen,
                        child: posProvider.state == PosState.loading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Send KOT', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    
                    // Mark Served Button if Order is Ready in the Kitchen!
                    if (posProvider.activeOrder != null && posProvider.activeOrder!.status == 'ready') ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: const Icon(Icons.room_service, size: 16),
                          label: const Text('Mark Served', style: TextStyle(fontWeight: FontWeight.bold)),
                          onPressed: () async {
                            final auth = context.read<AuthProvider>();
                            final profileId = auth.currentProfile?.id ?? '';
                            final cafeId = auth.currentProfile?.cafeId ?? '';
                            
                            showDialog(
                              context: context,
                              barrierDismissible: false,
                              builder: (ctx) => const Center(child: CircularProgressIndicator()),
                            );
                            
                            final success = await posProvider.markAsServed(posProvider.activeOrder!.id, profileId, cafeId);
                            
                            if (mounted) {
                              Navigator.pop(context); // Pop loading spinner
                              if (success) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Order marked as served!'), backgroundColor: Colors.green),
                                );
                                // Go back to table view
                                setState(() {
                                  _currentView = 'Tables';
                                });
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Error: ${posProvider.errorMessage}'), backgroundColor: Colors.redAccent),
                                );
                              }
                            }
                          },
                        ),
                      ),
                    ],
                  ] else ...[
                    // Takeaway / Delivery Flow: Save Order so it can be billed on the Billing Screen
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: posProvider.cart.isEmpty ? null : _sendToKitchen,
                        child: posProvider.state == PosState.loading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Save Takeaway', style: TextStyle(fontWeight: FontWeight.bold)),
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

  Widget _buildCartItemTile(CartItem item, PosProvider provider) {
    final role = context.read<AuthProvider>().currentProfile?.role?.toLowerCase() ?? 'admin';
    final isPostKOT = provider.activeOrder != null && 
        provider.activeOrder!.status != 'active' && 
        provider.activeOrder!.status != 'pending';
    
    final bool disableEdit = role == 'cashier' && isPostKOT;

    return Column(
      children: [
        ListTile(
          title: Text(item.product.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Rs. ${item.product.sellingPrice.toStringAsFixed(2)}'),
              if (item.note != null && item.note!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(4)),
                    child: Text(
                      'Note: ${item.note}',
                      style: TextStyle(color: Colors.red.shade900, fontSize: 11, fontStyle: FontStyle.italic),
                    ),
                  ),
                ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 20),
                onPressed: disableEdit ? null : () => provider.updateQuantity(item.product, item.quantity - 1),
              ),
              Text('${item.quantity.toInt()}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 20),
                onPressed: disableEdit ? null : () => provider.updateQuantity(item.product, item.quantity + 1),
              ),
              IconButton(
                icon: const Icon(Icons.note_add_outlined, color: Colors.blue),
                onPressed: disableEdit ? null : () => _editItemNote(item, provider),
                tooltip: 'Add note',
              ),
            ],
          ),
        ),
        const Divider(height: 1, indent: 16, endIndent: 16),
      ],
    );
  }

  Widget _buildSummaryRow(String label, double amount, {bool isNegative = false, bool isBold = false, double size = 14}) {
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

  Widget _buildMobileCartSummary(PosProvider posProvider) {
    if (posProvider.cart.isEmpty) return const SizedBox.shrink();
    
    return Container(
      color: AppTheme.surfaceColor,
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${posProvider.cart.length} Items', style: const TextStyle(color: AppTheme.textSecondary)),
              Text('Total: Rs. ${posProvider.grandTotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          ElevatedButton(
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (context) => SizedBox(
                  height: MediaQuery.of(context).size.height * 0.85,
                  child: _buildCart(posProvider),
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
            child: const Text('View Cart'),
          ),
        ],
      ),
    );
  }
}
