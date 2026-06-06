import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/presentation/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../menu/presentation/providers/product_provider.dart';
import '../providers/operations_provider.dart';
import '../../data/models/purchase_invoice_model.dart';
import 'package:uuid/uuid.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cafeId = context.read<AuthProvider>().cafeId;
      if (cafeId != null) {
        context.read<OperationsProvider>().init(cafeId);
      }
    });
  }

  void _showAddStockDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        final products = ctx.read<ProductProvider>().products;
        String? selectedProductId;
        final _qtyController = TextEditingController();
        final _priceController = TextEditingController();

        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            title: const Text('Add Stock (Purchase)'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Select Product'),
                  items: products.map((p) => DropdownMenuItem(value: p.id, child: Text(p.name))).toList(),
                  onChanged: (val) => setState(() => selectedProductId = val),
                ),
                TextField(
                  controller: _qtyController,
                  decoration: const InputDecoration(labelText: 'Quantity'),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: _priceController,
                  decoration: const InputDecoration(labelText: 'Total Cost (Rs.)'),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () {
                  if (selectedProductId == null) return;
                  final cafeId = context.read<AuthProvider>().cafeId;
                  if (cafeId == null) return;
                  final qty = int.tryParse(_qtyController.text) ?? 0;
                  final totalCost = double.tryParse(_priceController.text) ?? 0;
                  if (qty <= 0 || totalCost <= 0) return;

                  final invoice = PurchaseInvoiceModel(
                    id: const Uuid().v4(),
                    cafeId: cafeId,
                    supplierId: null,
                    productId: selectedProductId!,
                    quantity: qty,
                    purchasePrice: totalCost / qty,
                    totalCost: totalCost,
                    createdAt: DateTime.now(),
                  );

                  context.read<OperationsProvider>().addPurchaseInvoice(invoice, (productId, addQty) {
                    context.read<ProductProvider>().incrementStock(productId, addQty);
                  });
                  Navigator.pop(context);
                },
                child: const Text('Save'),
              ),
            ],
          );
        });
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Inventory Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_shopping_cart),
            tooltip: 'Stock In',
            onPressed: _showAddStockDialog,
          )
        ],
      ),
      body: Consumer<ProductProvider>(
        builder: (context, provider, child) {
          final products = provider.products;

          if (provider.state == ProductState.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          
          if (provider.errorMessage != null) {
            return Center(child: Text(provider.errorMessage!));
          }

          if (products.isEmpty) {
            return const Center(child: Text('No products found in inventory.'));
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Product', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Category', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Stock (Units)', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Unit Type', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
                rows: products.map((p) {
                  final isLow = p.stockQuantity <= 5; // Default low stock threshold
                  
                  // Cigarette advanced logic formatting
                  String stockText = '${p.stockQuantity}';
                  if (p.unitType == 'packet' && p.unitsPerPacket > 1) {
                     int packets = p.stockQuantity ~/ p.unitsPerPacket;
                     int looseSticks = p.stockQuantity % p.unitsPerPacket;
                     stockText = '$packets Pkt + $looseSticks sticks';
                  }

                  return DataRow(
                    cells: [
                      DataCell(Text(p.name)),
                      DataCell(Text(p.categoryId ?? 'N/A')),
                      DataCell(Text(stockText, style: TextStyle(color: isLow ? Colors.red : Colors.black, fontWeight: isLow ? FontWeight.bold : FontWeight.normal))),
                      DataCell(Text(p.unitType ?? 'pcs')),
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isLow ? Colors.red.withOpacity(0.1) : Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(isLow ? 'Low Stock' : 'In Stock', style: TextStyle(color: isLow ? Colors.red : Colors.green, fontSize: 12)),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          );
        },
      ),
    );
  }
}
