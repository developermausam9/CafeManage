import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/utils/snackbar_helper.dart';
import '../../../../core/presentation/widgets/app_button.dart';
import '../../../../core/presentation/widgets/app_text_field.dart';
import '../../../../core/network/supabase_config.dart';

class CreateSuperAdminScreen extends StatefulWidget {
  const CreateSuperAdminScreen({super.key});

  @override
  State<CreateSuperAdminScreen> createState() => _CreateSuperAdminScreenState();
}

class _CreateSuperAdminScreenState extends State<CreateSuperAdminScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _createSuperAdmin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // 1. Create a secondary Supabase client to avoid hijacking current session
      final tempClient = SupabaseClient(
        SupabaseConfig.supabaseUrl,
        SupabaseConfig.supabaseAnonKey,
        authOptions: const AuthClientOptions(
          authFlowType: AuthFlowType.implicit,
        ),
      );

      final email = _emailCtrl.text.trim();
      final password = _passwordCtrl.text.trim();
      final name = _nameCtrl.text.trim();
      final phone = _phoneCtrl.text.trim();

      // 2. Sign up user
      final authResponse = await tempClient.auth.signUp(
        email: email,
        password: password,
      );

      final user = authResponse.user;
      if (user == null) {
        throw Exception("Failed to create super admin user.");
      }

      // 3. Create profile in main client as super_admin
      // Note: We use the main client here assuming RLS allows super_admins to insert profiles
      await Supabase.instance.client.from('profiles').insert({
        'id': user.id,
        'full_name': name,
        'phone': phone,
        'role': 'super_admin',
        // cafe_id is null for super admins
      });

      tempClient.dispose();

      if (!mounted) return;
      
      SnackbarHelper.showSuccess('Super Admin created successfully!');
      
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Super Admin Created'),
          content: Text('Email: $email\nPassword: $password'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
      
    } catch (e) {
      if (mounted) {
        SnackbarHelper.showError('Failed to create super admin: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Super Admin')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Enter new Super Admin details.', style: TextStyle(fontSize: 16)),
              const SizedBox(height: 24),
              AppTextField(
                label: 'Full Name',
                controller: _nameCtrl,
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              AppTextField(
                label: 'Email',
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              AppTextField(
                label: 'Phone',
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              AppTextField(
                label: 'Temporary Password',
                controller: _passwordCtrl,
                obscureText: true,
                validator: (v) => v!.length < 6 ? 'Min 6 chars' : null,
              ),
              const SizedBox(height: 32),
              AppButton(
                text: 'Create Super Admin',
                isLoading: _isLoading,
                onPressed: _createSuperAdmin,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
