import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/usecases/create_cafe_usecase.dart';
import '../providers/super_admin_provider.dart';
import '../../../../core/utils/snackbar_helper.dart';

class CreateCafeScreen extends StatefulWidget {
  const CreateCafeScreen({super.key});

  @override
  State<CreateCafeScreen> createState() => _CreateCafeScreenState();
}

class _CreateCafeScreenState extends State<CreateCafeScreen> {
  final _formKey = GlobalKey<FormState>();

  final _cafeNameCtrl = TextEditingController();
  final _ownerNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _panVatCtrl = TextEditingController();
  final _monthlyFeeCtrl = TextEditingController();

  String _planType = 'Standard';
  String _status = 'active';
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 30));

  @override
  void dispose() {
    _cafeNameCtrl.dispose();
    _ownerNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    _addressCtrl.dispose();
    _panVatCtrl.dispose();
    _monthlyFeeCtrl.dispose();
    super.dispose();
  }

  void _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final provider = context.read<SuperAdminProvider>();

    final params = CreateCafeParams(
      cafeName: _cafeNameCtrl.text.trim(),
      ownerName: _ownerNameCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      password: _passwordCtrl.text,
      address: _addressCtrl.text.trim(),
      panVat: _panVatCtrl.text.trim(),
      planType: _planType,
      monthlyFee: double.tryParse(_monthlyFeeCtrl.text) ?? 0.0,
      subscriptionStart: _startDate,
      subscriptionEnd: _endDate,
      status: _status,
    );

    final success = await provider.createCafe(params);

    if (!mounted) return;

    if (success) {
      SnackbarHelper.showSuccess('Cafe created successfully!');
      
      // Show credentials dialog before popping
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Cafe Created'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Please share these credentials securely:'),
              const SizedBox(height: 16),
              Text('Login Email: ${params.email}', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('Password: ${params.password}', style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).pop(); // pop screen
              },
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } else {
      SnackbarHelper.showError(provider.errorMessage ?? 'Failed to create cafe');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = context.watch<SuperAdminProvider>().state == SuperAdminState.loading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Café'),
      ),
      body: isLoading 
        ? const Center(child: CircularProgressIndicator())
        : Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(24.0),
              children: [
                const Text('Café Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _cafeNameCtrl,
                  decoration: const InputDecoration(labelText: 'Café Name', border: OutlineInputBorder()),
                  validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _addressCtrl,
                  decoration: const InputDecoration(labelText: 'Address', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _panVatCtrl,
                  decoration: const InputDecoration(labelText: 'PAN/VAT Number', border: OutlineInputBorder()),
                ),
                
                const SizedBox(height: 32),
                const Text('Owner Details & Login', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _ownerNameCtrl,
                  decoration: const InputDecoration(labelText: 'Owner Full Name', border: OutlineInputBorder()),
                  validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailCtrl,
                  decoration: const InputDecoration(labelText: 'Owner Email (Login ID)', border: OutlineInputBorder()),
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneCtrl,
                  decoration: const InputDecoration(labelText: 'Owner Phone', border: OutlineInputBorder()),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordCtrl,
                  decoration: const InputDecoration(labelText: 'Temporary Password', border: OutlineInputBorder()),
                  obscureText: false,
                  validator: (v) => v == null || v.length < 6 ? 'Min 6 characters' : null,
                ),

                const SizedBox(height: 32),
                const Text('Subscription & Plan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _planType,
                  decoration: const InputDecoration(labelText: 'Plan Type', border: OutlineInputBorder()),
                  items: ['Basic', 'Standard', 'Premium']
                      .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                      .toList(),
                  onChanged: (v) => setState(() => _planType = v!),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _monthlyFeeCtrl,
                  decoration: const InputDecoration(labelText: 'Monthly Fee (Rs.)', border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                  validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _status,
                  decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
                  items: ['active', 'suspended']
                      .map((p) => DropdownMenuItem(value: p, child: Text(p.toUpperCase())))
                      .toList(),
                  onChanged: (v) => setState(() => _status = v!),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _submit,
                    child: const Text('Create Café', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
    );
  }
}
