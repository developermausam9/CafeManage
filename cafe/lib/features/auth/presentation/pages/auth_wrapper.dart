import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'login_screen.dart';
import '../../../cafes/presentation/pages/business_setup_screen.dart';
import '../../../home/presentation/pages/dashboard_shell.dart';
import '../../../super_admin/presentation/pages/super_admin_shell.dart';
import '../../../super_admin/presentation/pages/subscription_expired_screen.dart';
import '../../../operations/presentation/pages/customer_booking_screen.dart';
import '../../../menu/presentation/pages/customer_menu_screen.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  @override
  void initState() {
    super.initState();
    // Check session on start
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthProvider>().checkAuthStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final path = Uri.base.path;
    final fragment = Uri.base.fragment;
    final isBookingRoute = path.contains('/book') || fragment.contains('/book') || path == 'book';
    final isOrderingRoute = path.contains('/order') || fragment.contains('/order') || path == 'order';

    if (isBookingRoute) {
      return const CustomerBookingScreen();
    }
    if (isOrderingRoute) {
      return const CustomerMenuScreen();
    }

    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        if (authProvider.state == AuthState.loading || 
            authProvider.state == AuthState.initial) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }


        if (authProvider.state == AuthState.authenticated) {
          // Super Admin Routing
          if (authProvider.currentProfile?.isSuperAdmin == true) {
            return const SuperAdminShell();
          }
          
          // Suspended Check
          if (authProvider.isSuspended) {
            return const SubscriptionExpiredScreen();
          }

          final cafeId = authProvider.currentProfile?.cafeId;
          final role = authProvider.currentProfile?.role;
          
          // If Owner and no cafe_id, show Business Setup
          if (role == 'owner' && (cafeId == null || cafeId.isEmpty)) {
            return BusinessSetupScreen();
          }

          // Otherwise, go to dashboard
          return const DashboardShell();
        }

        // Unauthenticated or Error
        return const LoginScreen();
      },
    );
  }
}
