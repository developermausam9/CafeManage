import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/utils/snackbar_helper.dart';

class ReceiptFooterScreen extends StatefulWidget {
  const ReceiptFooterScreen({super.key});

  @override
  State<ReceiptFooterScreen> createState() => _ReceiptFooterScreenState();
}

class _ReceiptFooterScreenState extends State<ReceiptFooterScreen> {
  final _client = Supabase.instance.client;
  final _footerCtrl = TextEditingController();
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
          _footerCtrl.text = settingsRes['receipt_footer_message'] ?? '';
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
        'receipt_footer_message': _footerCtrl.text.trim(),
      };

      await _client.from('settings').upsert({'cafe_id': _cafeId, ...data});

      SnackbarHelper.showSuccess('Receipt footer message saved successfully');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      SnackbarHelper.showError('Failed to save settings: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _footerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Receipt Footer')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Footer Message',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'This message will be printed at the bottom of customer receipts/bills.',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _footerCtrl,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Footer Text',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                      hintText: 'Thank you for visiting! Please visit us again.',
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _saveSettings,
                      child: const Text('Save Settings', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
