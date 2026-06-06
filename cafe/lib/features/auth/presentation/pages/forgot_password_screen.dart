import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/presentation/widgets/app_button.dart';
import '../../../../core/presentation/widgets/app_text_field.dart';
import '../../../../core/utils/snackbar_helper.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _newPasswordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    final newPassword = _newPasswordController.text.trim();

    if (email.isEmpty) {
      SnackbarHelper.showError('Please enter your email');
      return;
    }
    if (phone.isEmpty) {
      SnackbarHelper.showError('Please enter your registered phone number');
      return;
    }
    if (newPassword.length < 6) {
      SnackbarHelper.showError('Password must be at least 6 characters');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final bool success = await Supabase.instance.client.rpc(
        'recover_user_password',
        params: {
          'p_email': email,
          'p_phone': phone,
          'p_new_password': newPassword,
        },
      );

      if (success) {
        if (mounted) {
          SnackbarHelper.showSuccess('Password reset successfully! Please sign in with your new password.');
          Navigator.pop(context);
        }
      } else {
        if (mounted) {
          SnackbarHelper.showError('Verification failed. Please check your email and registered phone number.');
        }
      }
    } catch (e) {
      if (mounted) {
        SnackbarHelper.showError('Error: ${e.toString()}');
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
      appBar: AppBar(title: const Text('Forgot Password')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(40.0),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Reset Password',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Verify your identity using your registered phone number to set a new password.',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
                const SizedBox(height: 32),
                AppTextField(
                  label: 'Email Address',
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  prefixIcon: const Icon(Icons.email_outlined),
                ),
                const SizedBox(height: 16),
                AppTextField(
                  label: 'Registered Phone Number',
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  prefixIcon: const Icon(Icons.phone_outlined),
                ),
                const SizedBox(height: 16),
                AppTextField(
                  label: 'New Password',
                  controller: _newPasswordController,
                  obscureText: true,
                  prefixIcon: const Icon(Icons.lock_outline),
                ),
                const SizedBox(height: 32),
                AppButton(
                  text: 'Reset Password',
                  isLoading: _isLoading,
                  onPressed: _resetPassword,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
