import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/presentation/theme/app_theme.dart';
import '../../../operations/data/models/customer_due_model.dart';
import '../../../operations/presentation/providers/operations_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/pos_provider.dart';

class CheckoutDialog extends StatefulWidget {
  final Function(String? customerDueId) onConfirm;

  const CheckoutDialog({super.key, required this.onConfirm});

  @override
  State<CheckoutDialog> createState() => _CheckoutDialogState();
}

class _CheckoutDialogState extends State<CheckoutDialog> {
  bool _isLoadingQr = true;
  String? _qrImageUrl;
  String? _merchantName;
  String? _qrProvider;

  // Due Selection State
  CustomerDueModel? _selectedCustomer;
  bool _isNewCustomer = false;
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _fetchQrDetails();
    // Fetch customer dues list to ensure it is fresh
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cafeId = context.read<AuthProvider>().cafeId;
      if (cafeId != null) {
        context.read<OperationsProvider>().fetchAll();
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _fetchQrDetails() async {
    final posProvider = context.read<PosProvider>();
    if (posProvider.paymentMethod != 'QR') {
      if (mounted) {
        setState(() => _isLoadingQr = false);
      }
      return;
    }

    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user != null) {
        final profile = await client.from('profiles').select('cafe_id').eq('id', user.id).single();
        final settings = await client.from('settings').select().eq('cafe_id', profile['cafe_id']).maybeSingle();
        if (settings != null) {
          _qrImageUrl = settings['qr_image_url'];
          _merchantName = settings['qr_merchant_name'];
          _qrProvider = settings['qr_provider'];
        }
      }
    } catch (e) {
      debugPrint('Error fetching QR settings: $e');
    } finally {
      if (mounted) setState(() => _isLoadingQr = false);
    }
  }

  Future<void> _handleConfirm() async {
    final posProvider = context.read<PosProvider>();
    if (posProvider.paymentMethod == 'Due') {
      final opsProvider = context.read<OperationsProvider>();
      final cafeId = context.read<AuthProvider>().cafeId;

      if (cafeId == null) return;

      if (_isNewCustomer) {
        if (!_formKey.currentState!.validate()) return;
        
        // Show local loading
        setState(() {});
        
        try {
          final newDue = CustomerDueModel(
            id: const Uuid().v4(),
            cafeId: cafeId,
            name: _nameController.text.trim(),
            phone: _phoneController.text.trim(),
            totalDue: 0.0, // PosProvider finalizePayment will increment it
            lastUpdatedAt: DateTime.now(),
          );
          
          await opsProvider.addCustomerDue(newDue);
          
          if (mounted) {
            Navigator.pop(context);
            widget.onConfirm(newDue.id);
          }
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to create customer: $e')),
          );
        }
      } else {
        if (_selectedCustomer == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please select an outstanding customer due account')),
          );
          return;
        }
        Navigator.pop(context);
        widget.onConfirm(_selectedCustomer!.id);
      }
    } else {
      Navigator.pop(context);
      widget.onConfirm(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final posProvider = context.watch<PosProvider>();
    final opsProvider = context.watch<OperationsProvider>();
    final customers = opsProvider.customerDues;

    return AlertDialog(
      title: const Text('Confirm Payment'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total Amount:', style: TextStyle(fontSize: 16)),
                  Text(
                    'Rs. ${posProvider.grandTotal.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Payment Method:', style: TextStyle(fontSize: 16)),
                  Text(
                    posProvider.paymentMethod,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const Divider(height: 32),
              
              if (posProvider.paymentMethod == 'Due') ...[
                const Text(
                  'Select Customer Account',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _isNewCustomer ? 'Create New Account' : 'Choose Existing Account',
                        style: const TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _isNewCustomer = !_isNewCustomer;
                        });
                      },
                      icon: Icon(_isNewCustomer ? Icons.people : Icons.person_add, size: 16),
                      label: Text(_isNewCustomer ? 'Existing' : 'New Customer'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (!_isNewCustomer) ...[
                  DropdownButtonFormField<CustomerDueModel>(
                    decoration: const InputDecoration(
                      labelText: 'Customer Dues Account',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    value: _selectedCustomer,
                    items: customers.map((c) {
                      return DropdownMenuItem(
                        value: c,
                        child: Text('${c.name} (${c.phone}) - Due: Rs.${c.totalDue.toStringAsFixed(0)}'),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setState(() {
                        _selectedCustomer = val;
                      });
                    },
                    validator: (val) => val == null ? 'Selection required' : null,
                  ),
                ] else ...[
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Customer Name',
                      border: OutlineInputBorder(),
                    ),
                    validator: (val) => val == null || val.trim().isEmpty ? 'Name required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phoneController,
                    decoration: const InputDecoration(
                      labelText: 'Phone Number',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.phone,
                    validator: (val) => val == null || val.trim().isEmpty ? 'Phone number required' : null,
                  ),
                ],
                const SizedBox(height: 24),
              ],

              if (posProvider.paymentMethod == 'QR') ...[
                if (_isLoadingQr)
                  const Center(child: CircularProgressIndicator())
                else if (_qrImageUrl != null && _qrImageUrl!.isNotEmpty) ...[
                  Text('Scan $_qrProvider to Pay', style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                  if (_merchantName != null && _merchantName!.isNotEmpty)
                    Text(_merchantName!, style: const TextStyle(fontSize: 12, color: Colors.grey), textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  Center(
                    child: Container(
                      height: 200,
                      width: 200,
                      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)),
                      child: Image.network(
                        _qrImageUrl!,
                        fit: BoxFit.contain,
                        errorBuilder: (ctx, err, stack) => const Center(child: Text('Invalid QR Image', textAlign: TextAlign.center)),
                      ),
                    ),
                  ),
                ] else ...[
                  const Center(child: Icon(Icons.warning, color: Colors.orange, size: 48)),
                  const SizedBox(height: 8),
                  const Text('QR settings not configured.', textAlign: TextAlign.center),
                  const Text('Please configure them in Settings.', style: TextStyle(fontSize: 12, color: Colors.grey), textAlign: TextAlign.center),
                ],
                const SizedBox(height: 24),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _handleConfirm,
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
          child: Text(posProvider.paymentMethod == 'QR' ? 'Confirm Payment Received' : 'Confirm Order'),
        ),
      ],
    );
  }
}
