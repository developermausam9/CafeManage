import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/network/supabase_config.dart';
import '../../../../core/presentation/theme/app_theme.dart';
import '../../../../core/presentation/widgets/loading_view.dart';
import '../../../../core/presentation/widgets/error_view.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/product_provider.dart';
import '../widgets/product_card.dart';
import 'product_form_screen.dart';

class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  String _searchQuery = '';
  String _selectedCategory = 'All';
  final List<String> _categories = ['All', 'Food', 'Drinks', 'Cigarettes', 'Snacks', 'Retail'];
  Map<String, String> _categoryMap = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cafeId = context.read<AuthProvider>().cafeId;
      if (cafeId != null) {
        context.read<ProductProvider>().loadProducts(cafeId);
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

  void _confirmDelete(BuildContext context, String productId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Product'),
        content: const Text('Are you sure you want to delete this product?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              final cafeId = context.read<AuthProvider>().cafeId!;
              context.read<ProductProvider>().deleteProduct(productId, cafeId);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 950 && size.width > size.height;
    
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Consumer<ProductProvider>(
        builder: (context, provider, child) {
          if (provider.state == ProductState.loading && provider.products.isEmpty) {
            return const LoadingView(message: 'Loading Menu...');
          }
          if (provider.state == ProductState.error && provider.products.isEmpty) {
            return ErrorView(
              message: provider.errorMessage ?? 'Failed to load products',
              onRetry: () {
                final cafeId = context.read<AuthProvider>().cafeId!;
                provider.loadProducts(cafeId);
              },
            );
          }

          // Filter Logic
          final filteredProducts = provider.products.where((p) {
            final normCat = _getNormalizedCategory(p.categoryId);
            final matchesCategory = _selectedCategory == 'All' || normCat.toLowerCase() == _selectedCategory.toLowerCase();
            final matchesSearch = p.name.toLowerCase().contains(_searchQuery.toLowerCase());
            return matchesCategory && matchesSearch;
          }).toList();

          return Column(
            children: [
              // Header: Search and Categories
              Container(
                color: AppTheme.surfaceColor,
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    TextField(
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
                              labelStyle: TextStyle(
                                color: isSelected ? Colors.white : AppTheme.textPrimary,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),

              // Product Grid/List
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    final cafeId = context.read<AuthProvider>().cafeId;
                    if (cafeId != null) {
                      await provider.loadProducts(cafeId);
                      await _loadCategories();
                    }
                  },
                  child: filteredProducts.isEmpty
                      ? const SingleChildScrollView(
                          physics: AlwaysScrollableScrollPhysics(),
                          child: SizedBox(
                            height: 300,
                            child: Center(child: Text('No products found.')),
                          ),
                        )
                      : GridView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16.0),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: isDesktop ? 4 : 2,
                            childAspectRatio: 0.75,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                          ),
                          itemCount: filteredProducts.length,
                          itemBuilder: (context, index) {
                            final product = filteredProducts[index];
                            return ProductCard(
                              product: product,
                              onEdit: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ProductFormScreen(existingProduct: product),
                                  ),
                                );
                              },
                              onDelete: () => _confirmDelete(context, product.id),
                            );
                          },
                        ),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ProductFormScreen()),
          );
        },
        backgroundColor: AppTheme.primaryColor,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
