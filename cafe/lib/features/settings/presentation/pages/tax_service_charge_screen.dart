import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/utils/snackbar_helper.dart';

class TaxServiceChargeScreen extends StatefulWidget {
  const TaxServiceChargeScreen({super.key});

  @override
  State<TaxServiceChargeScreen> createState() => _TaxServiceChargeScreenState();
}

class _TaxServiceChargeScreenState extends State<TaxServiceChargeScreen> {
  final _client = Supabase.instance.client;
  final _taxCtrl = TextEditingController();
  final _serviceChargeCtrl = TextEditingController();
  bool _waiterBillingEnabled = false;
  bool _isLoading = true;
  String? _cafeId;

  @override
  void initState() {
    super.initState();
    _fetchSettings();
  }

  Future<void> _fetchSettings() async {
    setState(() => _isLoading = true);
    try {
      final user = _client.auth.currentUser;
      if (user == null) throw Exception('Not logged in');

      final currentProfile = await _client.from('profiles').select('cafe_id').eq('id', user.id).single();
      _cafeId = currentProfile['cafe_id'];

      final settingsRes = await _client.from('settings').select().eq('cafe_id', _cafeId as Object).maybeSingle();
      if (settingsRes != null) {
        setState(() {
          _taxCtrl.text = (settingsRes['tax_percentage'] ?? 13.0).toString();
          _serviceChargeCtrl.text = (settingsRes['service_charge_percentage'] ?? 10.0).toString();
          _waiterBillingEnabled = settingsRes['waiter_billing_enabled'] as bool? ?? false;
        });
      } else {
        setState(() {
          _taxCtrl.text = '13.0';
          _serviceChargeCtrl.text = '10.0';
          _waiterBillingEnabled = false;
        });
      }
    } catch (e) {
      SnackbarHelper.showError('Failed to load settings: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    final taxVal = double.tryParse(_taxCtrl.text.trim());
    final scVal = double.tryParse(_serviceChargeCtrl.text.trim());

    if (taxVal == null || taxVal < 0 || taxVal > 100) {
      SnackbarHelper.showError('Please enter a valid VAT percentage (0 - 100)');
      return;
    }
    if (scVal == null || scVal < 0 || scVal > 100) {
      SnackbarHelper.showError('Please enter a valid Service Charge percentage (0 - 100)');
      return;
    }

    setState(() => _isLoading = true);
    try {
      if (_cafeId == null) throw Exception('Cafe ID not found');

      final data = {
        'tax_percentage': taxVal,
        'service_charge_percentage': scVal,
        'waiter_billing_enabled': _waiterBillingEnabled,
      };

      await _client.from('settings').upsert({'cafe_id': _cafeId, ...data});

      SnackbarHelper.showSuccess('Settings saved successfully');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      SnackbarHelper.showError('Failed to save settings: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _taxCtrl.dispose();
    _serviceChargeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tax & Service Charge')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Configuration',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Configure the VAT, service charge, and workflow permissions for your café staff.',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _taxCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'VAT Percentage (%)',
                      border: OutlineInputBorder(),
                      suffixText: '%',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _serviceChargeCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Service Charge Percentage (%)',
                      border: OutlineInputBorder(),
                      suffixText: '%',
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 12),
                  const Text(
                    'Role & Permission Overrides',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    activeColor: Colors.deepOrange,
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Allow Waiters to Finalize Bills',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    subtitle: const Text(
                      'If enabled, waiters can complete billing and finalize payments in POS mode. Otherwise, only cashiers and admins can do so.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    value: _waiterBillingEnabled,
                    onChanged: (val) {
                      setState(() {
                        _waiterBillingEnabled = val;
                      });
                    },
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _saveSettings,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepOrange,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Save Settings', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
