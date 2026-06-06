import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/presentation/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/operations_provider.dart';
import '../../data/models/supplier_model.dart';
import 'package:uuid/uuid.dart';

class SuppliersScreen extends StatelessWidget {
  const SuppliersScreen({super.key});

  void _showAddSupplierDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        final _nameController = TextEditingController();
        final _phoneController = TextEditingController();
        final _companyController = TextEditingController();

        return AlertDialog(
          title: const Text('Add Supplier'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Supplier Name'),
              ),
              TextField(
                controller: _phoneController,
                decoration: const InputDecoration(labelText: 'Phone Number'),
                keyboardType: TextInputType.phone,
              ),
              TextField(
                controller: _companyController,
                decoration: const InputDecoration(labelText: 'Company/Brand'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final cafeId = context.read<AuthProvider>().cafeId;
                if (cafeId == null) return;

                final supplier = SupplierModel(
                  id: const Uuid().v4(),
                  cafeId: cafeId,
                  name: _nameController.text,
                  phone: _phoneController.text,
                  company: _companyController.text,
                  createdAt: DateTime.now(),
                );

                context.read<OperationsProvider>().addSupplier(supplier);
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddSupplierDialog(context),
        child: const Icon(Icons.add_business),
      ),
      body: Consumer<OperationsProvider>(
        builder: (context, provider, child) {
          final suppliers = provider.suppliers;

          if (provider.state == OperationsState.loading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.errorMessage != null) {
            return Center(child: Text(provider.errorMessage!));
          }

          if (suppliers.isEmpty) {
            return const Center(child: Text('No suppliers added yet.'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(24),
            itemCount: suppliers.length,
            itemBuilder: (context, index) {
              final s = suppliers[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.local_shipping),
                  ),
                  title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('${s.company} • ${s.phone}'),
                  trailing: Text('Payable: Rs. ${s.totalPayable.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 14)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
