import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/presentation/theme/app_theme.dart';
import '../../../../core/presentation/widgets/app_button.dart';
import '../../../../core/presentation/widgets/app_text_field.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/models/product_model.dart';
import '../providers/product_provider.dart';

class ProductFormScreen extends StatefulWidget {
  final ProductModel? existingProduct;

  const ProductFormScreen({super.key, this.existingProduct});

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  
  late TextEditingController _nameController;
  late TextEditingController _sellingPriceController;
  late TextEditingController _costPriceController;
  late TextEditingController _stockController;
  late TextEditingController _lowStockController;
  late TextEditingController _unitsPerPacketController;
  
  String _category = 'Food';
  String _unitType = 'pcs';
  bool _isAvailable = true;

  final List<String> _categories = ['Food', 'Drinks', 'Cigarettes', 'Snacks', 'Retail'];
  final List<String> _unitTypes = ['pcs', 'kg', 'ltr', 'portion', 'cup', 'packet', 'stick'];

  @override
  void initState() {
    super.initState();
    final p = widget.existingProduct;
    _nameController = TextEditingController(text: p?.name ?? '');
    _sellingPriceController = TextEditingController(text: p?.sellingPrice.toString() ?? '');
    _costPriceController = TextEditingController(text: p?.costPrice.toString() ?? '');
    _stockController = TextEditingController(text: p?.stockQuantity.toString() ?? '0');
    _lowStockController = TextEditingController(text: '5'); // Removed from model
    _unitsPerPacketController = TextEditingController(text: p?.unitsPerPacket.toString() ?? '20');
    
    if (p != null) {
      _category = p.categoryId ?? 'Food'; 
      _unitType = p.unitType ?? 'pcs';
      _isAvailable = p.isAvailable;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _sellingPriceController.dispose();
    _costPriceController.dispose();
    _stockController.dispose();
    _lowStockController.dispose();
    _unitsPerPacketController.dispose();
    super.dispose();
  }

  void _submit() async {
    if (_formKey.currentState!.validate()) {
      final cafeId = context.read<AuthProvider>().cafeId;
      if (cafeId == null) return;

      final newProduct = ProductModel(
        id: widget.existingProduct?.id ?? const Uuid().v4(),
        cafeId: cafeId,
        categoryId: _category, // Treating categoryName as categoryId for UI simplicity
        name: _nameController.text.trim(),
        sellingPrice: double.parse(_sellingPriceController.text),
        costPrice: _costPriceController.text.isEmpty ? 0.0 : double.parse(_costPriceController.text),
        stockQuantity: int.parse(_stockController.text),
        unitType: _unitType,
        unitsPerPacket: _unitType == 'packet' ? int.parse(_unitsPerPacketController.text) : 1,
        isAvailable: _isAvailable,
        createdAt: widget.existingProduct?.createdAt ?? DateTime.now(),
      );

      final provider = context.read<ProductProvider>();
      if (widget.existingProduct == null) {
        await provider.addProduct(newProduct);
      } else {
        await provider.updateProduct(newProduct);
      }

      if (mounted) {
        if (provider.errorMessage == null) {
          Navigator.pop(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(provider.errorMessage!)),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingProduct != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Product' : 'Add Product'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppTextField(
                    label: 'Product Name',
                    controller: _nameController,
                    validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                  ),
                  
                  // Category Dropdown
                  const Text('Category', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _categories.contains(_category) ? _category : _categories.first,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                    onChanged: (val) => setState(() => _category = val!),
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        child: AppTextField(
                          label: 'Selling Price',
                          controller: _sellingPriceController,
                          keyboardType: TextInputType.number,
                          validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: AppTextField(
                          label: 'Cost Price (Optional)',
                          controller: _costPriceController,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),

                  Row(
                    children: [
                      Expanded(
                        child: AppTextField(
                          label: 'Initial Stock',
                          controller: _stockController,
                          keyboardType: TextInputType.number,
                          validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Unit', style: TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: _unitTypes.contains(_unitType) ? _unitType : _unitTypes.first,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                              ),
                              items: _unitTypes.map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
                              onChanged: (val) => setState(() => _unitType = val!),
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ],
                  ),
                  
                  if (_unitType == 'packet') ...[
                    AppTextField(
                      label: 'Units/Sticks per Packet',
                      controller: _unitsPerPacketController,
                      keyboardType: TextInputType.number,
                      validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                    ),
                  ],
                  
                  AppTextField(
                    label: 'Low Stock Limit Alert',
                    controller: _lowStockController,
                    keyboardType: TextInputType.number,
                  ),

                  SwitchListTile(
                    title: const Text('Is Available?', style: TextStyle(fontWeight: FontWeight.w600)),
                    value: _isAvailable,
                    onChanged: (val) => setState(() => _isAvailable = val),
                    contentPadding: EdgeInsets.zero,
                    activeColor: AppTheme.primaryColor,
                  ),
                  const SizedBox(height: 32),
                  
                  Consumer<ProductProvider>(
                    builder: (context, provider, child) {
                      return AppButton(
                        text: isEditing ? 'Update Product' : 'Add Product',
                        isLoading: provider.state == ProductState.loading,
                        onPressed: _submit,
                      );
                    }
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
