import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/utils/snackbar_helper.dart';

class AddStaffScreen extends StatefulWidget {
  const AddStaffScreen({super.key});

  @override
  State<AddStaffScreen> createState() => _AddStaffScreenState();
}

class _AddStaffScreenState extends State<AddStaffScreen> {
  final _formKey = GlobalKey<FormState>();
  final _client = Supabase.instance.client;

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  String _role = 'cashier';
  bool _isLoading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final user = _client.auth.currentUser;
      if (user == null) throw Exception('Not logged in');

      // Get owner's cafe_id
      final currentProfile = await _client.from('profiles').select('cafe_id').eq('id', user.id).single();
      final cafeId = currentProfile['cafe_id'];

      // 1. Create a temporary client so we don't log out the Owner
      final tempClient = SupabaseClient(
        _client.auth.currentSession?.user.appMetadata['url'] ?? 'https://puffcvvmdvcidgniezvj.supabase.co',
        _client.auth.currentSession?.user.appMetadata['anonKey'] ?? 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InB1ZmZjdnZtZHZjaWRnbmllenZqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk1MjI1NTcsImV4cCI6MjA5NTA5ODU1N30.R7S_uvtmrqsonHAZ2Z5AIaP7gUZJVcOegCxoELI-N3I',
        authOptions: const AuthClientOptions(
          authFlowType: AuthFlowType.implicit,
        ),
      );

      final AuthResponse res = await tempClient.auth.signUp(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );

      final newStaffUser = res.user;
      if (newStaffUser == null) {
        throw Exception('Failed to create staff account');
      }

      // 2. Insert into profiles using main client (owner has RLS permission to insert for their cafe)
      await _client.from('profiles').insert({
        'id': newStaffUser.id,
        'cafe_id': cafeId,
        'full_name': _nameCtrl.text.trim(),
        'role': _role,
        'phone': _phoneCtrl.text.trim(),
        'is_active': true,
      });

      tempClient.dispose();

      if (!mounted) return;
      
      SnackbarHelper.showSuccess('Staff added successfully!');
      
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Staff Created'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Please share these credentials securely:'),
              const SizedBox(height: 16),
              Text('Login Email: ${_emailCtrl.text.trim()}', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('Password: ${_passwordCtrl.text}', style: const TextStyle(fontWeight: FontWeight.bold)),
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

    } catch (e) {
      SnackbarHelper.showError('Failed to add staff: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Staff')),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(24.0),
              children: [
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'Full Name', border: OutlineInputBorder()),
                  validator: (v) => v!.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailCtrl,
                  decoration: const InputDecoration(labelText: 'Email (Login ID)', border: OutlineInputBorder()),
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) => v!.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneCtrl,
                  decoration: const InputDecoration(labelText: 'Phone', border: OutlineInputBorder()),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordCtrl,
                  decoration: const InputDecoration(labelText: 'Temporary Password', border: OutlineInputBorder()),
                  obscureText: false,
                  validator: (v) => v!.length < 6 ? 'Min 6 chars' : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _role,
                  decoration: const InputDecoration(labelText: 'Role', border: OutlineInputBorder()),
                  items: ['admin', 'cashier', 'waiter', 'kitchen']
                      .map((p) => DropdownMenuItem(value: p, child: Text(p.toUpperCase())))
                      .toList(),
                  onChanged: (v) => setState(() => _role = v!),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _submit,
                    child: const Text('Add Staff', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
    );
  }
}
