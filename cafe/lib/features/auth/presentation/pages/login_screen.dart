import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/presentation/theme/app_theme.dart';
import '../../../../core/presentation/widgets/app_button.dart';
import '../../../../core/presentation/widgets/app_text_field.dart';
import '../providers/auth_provider.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _connectivity = Connectivity();
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    _emailController.text = 'developermausam9@gmail.com';
    _passwordController.text = '123456';
    _checkConnectivity();
  }

  Future<void> _checkConnectivity() async {
    // Web: dart:io is unavailable in browsers — always treat as online.
    // The ConnectivityService (provider) handles real-time status for the rest of the app.
    if (kIsWeb) {
      if (mounted) setState(() => _isOnline = true);
      return;
    }
    // Mobile/desktop: brief check using ConnectivityPlus
    try {
      final results = await _connectivity.checkConnectivity();
      final online = results.any((r) =>
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.ethernet ||
          r == ConnectivityResult.other);
      if (mounted) setState(() => _isOnline = online);
    } catch (_) {
      if (mounted) setState(() => _isOnline = true);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    final isOfflineCredential = (email == 'developermausam9@gmail.com' ||
        email == 'mausamban9@gmail.com' ||
        email == 'owner@cafe.com' ||
        email == 'waiter@cafe.com' ||
        email == 'cashier@cafe.com' ||
        email == 'kitchen@cafe.com') &&
        password == '123456';

    if (!_isOnline && !isOfflineCredential) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No internet connection. Turn on WiFi to sign in.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }
    if (_formKey.currentState!.validate()) {
      context.read<AuthProvider>().login(email, password);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 800;

    return Scaffold(
      body: Row(
        children: [
          // Left side branding (only on tablet/desktop)
          if (isDesktop)
            Expanded(
              child: Container(
                color: AppTheme.primaryColor,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.coffee_maker, size: 100, color: Colors.white),
                    const SizedBox(height: 24),
                    const Text(
                      'Café OS',
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'The Ultimate POS & Management System',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.white.withOpacity(0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Right side Login Form
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(40.0),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isDesktop) ...[
                          Center(
                            child: Icon(Icons.coffee, size: 64, color: AppTheme.primaryColor),
                          ),
                          const SizedBox(height: 32),
                        ],
                        const Text(
                          'Welcome back',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Please enter your details to sign in.',
                          style: TextStyle(
                            fontSize: 16,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 40),
                        
                        // Offline banner — shown when device has no internet
                        if (!_isOnline)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            margin: const EdgeInsets.only(bottom: 24),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.amber.shade300),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.wifi_off, color: Colors.amber.shade800, size: 20),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'You are offline',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.amber.shade900,
                                        ),
                                      ),
                                      Text(
                                        'Turn on WiFi to sign in for the first time.',
                                        style: TextStyle(fontSize: 12, color: Colors.amber.shade800),
                                      ),
                                    ],
                                  ),
                                ),
                                GestureDetector(
                                  onTap: _checkConnectivity,
                                  child: Icon(Icons.refresh, size: 20, color: Colors.amber.shade700),
                                ),
                              ],
                            ),
                          ),

                        // Auth error banner (wrong password, etc)
                        if (authProvider.errorMessage != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            margin: const EdgeInsets.only(bottom: 24),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.error_outline, color: Colors.red.shade700),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    authProvider.errorMessage!,
                                    style: TextStyle(color: Colors.red.shade700),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => context.read<AuthProvider>().clearError(),
                                  child: Icon(Icons.close, size: 18, color: Colors.red.shade400),
                                ),
                              ],
                            ),
                          ),

                        AppTextField(
                          label: 'Email',
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          prefixIcon: const Icon(Icons.email_outlined),
                          onChanged: (_) => context.read<AuthProvider>().clearError(),
                          validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                        ),
                        AppTextField(
                          label: 'Password',
                          controller: _passwordController,
                          obscureText: true,
                          prefixIcon: const Icon(Icons.lock_outline),
                          onChanged: (_) => context.read<AuthProvider>().clearError(),
                          validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
                              );
                            },
                            child: const Text('Forgot Password?'),
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        AppButton(
                          text: 'Sign In',
                          isLoading: authProvider.state == AuthState.loading,
                          onPressed: _submit,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
