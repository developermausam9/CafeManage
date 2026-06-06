import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/utils/snackbar_helper.dart';

class PaymentSettingsScreen extends StatefulWidget {
  const PaymentSettingsScreen({super.key});

  @override
  State<PaymentSettingsScreen> createState() => _PaymentSettingsScreenState();
}

class _PaymentSettingsScreenState extends State<PaymentSettingsScreen> {
  final _client = Supabase.instance.client;
  final _merchantNameCtrl = TextEditingController();
  final _imageUrlCtrl = TextEditingController();
  final _paymentQrUrlCtrl = TextEditingController();
  final _customerPortalUrlCtrl = TextEditingController();



  String _qrProvider = 'eSewa';
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
          _merchantNameCtrl.text = settingsRes['qr_merchant_name'] ?? '';
          _imageUrlCtrl.text = settingsRes['qr_image_url'] ?? '';
          _qrProvider = settingsRes['qr_provider'] ?? 'eSewa';
          _paymentQrUrlCtrl.text = settingsRes['payment_qr_url'] ?? '';
          _customerPortalUrlCtrl.text = settingsRes['customer_portal_url'] ?? '';
        });
      }


    } catch (e) {
      SnackbarHelper.showError('Failed to load settings: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isLoading = true);
    try {
      if (_cafeId == null) throw Exception('Cafe ID not found');

      final data = {
        'qr_provider': _qrProvider,
        'qr_merchant_name': _merchantNameCtrl.text.trim(),
        'qr_image_url': _imageUrlCtrl.text.trim(),
        'payment_qr_url': _paymentQrUrlCtrl.text.trim(),
        'customer_portal_url': _customerPortalUrlCtrl.text.trim(),
      };



      await _client.from('settings').upsert({'cafe_id': _cafeId, ...data});

      SnackbarHelper.showSuccess('Payment settings saved');
    } catch (e) {
      SnackbarHelper.showError('Failed to save settings: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _merchantNameCtrl.dispose();
    _imageUrlCtrl.dispose();
    _paymentQrUrlCtrl.dispose();
    _customerPortalUrlCtrl.dispose();
    super.dispose();
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payment Settings')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24.0),
              children: [
                const Text('QR Configuration', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _qrProvider,
                  decoration: const InputDecoration(labelText: 'QR Provider', border: OutlineInputBorder()),
                  items: ['eSewa', 'Khalti', 'Fonepay', 'Bank QR', 'Other']
                      .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                      .toList(),
                  onChanged: (v) => setState(() => _qrProvider = v!),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _merchantNameCtrl,
                  decoration: const InputDecoration(labelText: 'Merchant Name / Account Number', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _imageUrlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'QR Image URL',
                    border: OutlineInputBorder(),
                    hintText: 'https://example.com/my-qr.png',
                  ),
                ),
                const SizedBox(height: 8),
                const Text('Note: Due to Android Emulator limitations, please upload the image somewhere (like imgur) and paste the direct URL here.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 32),
                if (_imageUrlCtrl.text.isNotEmpty)
                  Center(
                    child: Container(
                      height: 200,
                      width: 200,
                      decoration: BoxDecoration(border: Border.all(color: Colors.grey)),
                      child: Image.network(
                        _imageUrlCtrl.text,
                        errorBuilder: (ctx, err, stack) => const Center(child: Text('Invalid Image URL')),
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),
                const Text('Room Booking Payment QR', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _paymentQrUrlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Room Booking Payment QR Image URL',
                    border: OutlineInputBorder(),
                    hintText: 'https://example.com/my-room-payment-qr.png',
                  ),
                ),
                const SizedBox(height: 8),
                const Text('Note: This QR is specifically shown during room bookings (/book page) for customers to upload payment validation references.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 16),
                if (_paymentQrUrlCtrl.text.isNotEmpty)
                  Center(
                    child: Container(
                      height: 200,
                      width: 200,
                      decoration: BoxDecoration(border: Border.all(color: Colors.grey)),
                      child: Image.network(
                        _paymentQrUrlCtrl.text,
                        errorBuilder: (ctx, err, stack) => const Center(child: Text('Invalid Image URL')),
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),
                const Text('Customer Web Portal Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _customerPortalUrlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Customer Web Portal URL',
                    border: OutlineInputBorder(),
                    hintText: 'e.g. https://myhotel.vercel.app or http://192.168.1.10:8080',
                  ),
                ),
                const SizedBox(height: 8),
                const Text('Note: Configure the base domain/URL where the guest self-service portals are hosted. QR codes will link to this address.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 32),


                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _saveSettings,
                    child: const Text('Save Settings', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
    );
  }
}
