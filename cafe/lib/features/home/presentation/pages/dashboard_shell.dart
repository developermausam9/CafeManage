import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../../core/presentation/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../menu/presentation/pages/product_list_screen.dart';
import '../../../orders/presentation/pages/pos_screen.dart';
import '../../../orders/presentation/pages/billing_screen.dart';
import '../../../kitchen/presentation/pages/kitchen_screen.dart';
import '../../../analytics/presentation/pages/analytics_dashboard_screen.dart';
import '../../../operations/presentation/pages/inventory_screen.dart';
import '../../../operations/presentation/pages/suppliers_screen.dart';
import '../../../operations/presentation/pages/expenses_screen.dart';
import '../../../operations/presentation/pages/dues_screen.dart';
import '../../../operations/presentation/pages/table_management_screen.dart';
import '../../../operations/presentation/pages/room_management_screen.dart';
import '../../../operations/presentation/pages/bookings_management_screen.dart';
import '../../../operations/presentation/pages/delivery_management_screen.dart';

import '../../../orders/presentation/pages/order_history_screen.dart';
import '../../../settings/presentation/pages/settings_screen.dart';
import '../../../../core/services/connectivity_service.dart';
import '../../../../core/services/sync_service.dart';
import '../../../auth/presentation/providers/subscription_provider.dart';
import '../../../orders/presentation/providers/table_provider.dart';
import '../../../orders/presentation/providers/pos_provider.dart';
import '../../../kitchen/presentation/providers/kitchen_provider.dart';
import '../../../notifications/presentation/providers/notification_provider.dart';
import '../../../notifications/presentation/pages/notifications_screen.dart';

class DashboardShell extends StatefulWidget {
  const DashboardShell({super.key});

  @override
  State<DashboardShell> createState() => DashboardShellState();
}

class DashboardShellState extends State<DashboardShell> {
  int _selectedIndex = 0;
  bool _isSidebarOpen = true;

  void switchToTab(String label) {
    final authProvider = context.read<AuthProvider>();
    final subProvider = context.read<SubscriptionProvider>();
    final posProvider = context.read<PosProvider>();
    final role = authProvider.currentProfile?.role ?? 'admin';
    final navItems = _getNavigationItems(role, subProvider, posProvider.waiterBillingEnabled);
    final index = navItems.indexWhere((item) => item.label == label);
    if (index != -1) {
      setState(() {
        _selectedIndex = index;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = context.read<AuthProvider>();
      final cafeId = authProvider.currentProfile?.cafeId;
      if (cafeId != null) {
        context.read<SubscriptionProvider>().fetchSubscription(cafeId);
        context.read<TableProvider>().init(cafeId);
        context.read<KitchenProvider>().init(cafeId);
        context.read<PosProvider>().fetchSettings(cafeId);
        
        final userId = authProvider.currentProfile?.id ?? '';
        final role = authProvider.currentProfile?.role ?? 'admin';
        context.read<NotificationProvider>().init(cafeId, userId, role);
      }
    });
  }

  List<_NavigationItem> _getNavigationItems(String role, SubscriptionProvider subProvider, bool waiterBillingEnabled) {
    final hasStandard = subProvider.hasStandardOrPremium;

    switch (role) {
      case 'owner':
      case 'admin':
        final items = [
          if (hasStandard) _NavigationItem(icon: Icons.dashboard, label: 'Dashboard'),
          _NavigationItem(icon: Icons.point_of_sale, label: 'POS'),
          _NavigationItem(icon: Icons.receipt_long, label: 'Billing'),
          _NavigationItem(icon: Icons.history, label: 'Order History'),
          _NavigationItem(icon: Icons.restaurant_menu, label: 'Kitchen'),
          _NavigationItem(icon: Icons.table_restaurant, label: 'Tables'),
          _NavigationItem(icon: Icons.bed_outlined, label: 'Rooms'),
          _NavigationItem(icon: Icons.book_online, label: 'Bookings'),
          if (hasStandard) _NavigationItem(icon: Icons.delivery_dining, label: 'Deliveries'),
          _NavigationItem(icon: Icons.menu_book, label: 'Menu'),

          if (hasStandard) _NavigationItem(icon: Icons.inventory_2, label: 'Inventory'),
          if (hasStandard) _NavigationItem(icon: Icons.local_shipping, label: 'Suppliers'),
          if (hasStandard) _NavigationItem(icon: Icons.money_off, label: 'Expenses'),
          if (hasStandard) _NavigationItem(icon: Icons.warning_amber, label: 'Dues'),
          _NavigationItem(icon: Icons.settings, label: 'Settings'),
        ];
        return items;
      case 'cashier':
        return [
          _NavigationItem(icon: Icons.point_of_sale, label: 'POS'),
          _NavigationItem(icon: Icons.receipt_long, label: 'Billing'),
          _NavigationItem(icon: Icons.history, label: 'Order History'),
          _NavigationItem(icon: Icons.restaurant_menu, label: 'Kitchen'),
          if (hasStandard) _NavigationItem(icon: Icons.delivery_dining, label: 'Deliveries'),
          _NavigationItem(icon: Icons.book_online, label: 'Bookings'),
        ];
      case 'waiter':
        return [
          _NavigationItem(icon: Icons.point_of_sale, label: 'POS'),
          if (waiterBillingEnabled) _NavigationItem(icon: Icons.receipt_long, label: 'Billing'),
          _NavigationItem(icon: Icons.restaurant_menu, label: 'Kitchen'),
        ];
      case 'kitchen':
        return [
          _NavigationItem(icon: Icons.restaurant_menu, label: 'Kitchen'),
        ];
      default:
        return [
          _NavigationItem(icon: Icons.error, label: 'No Access'),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final subProvider = context.watch<SubscriptionProvider>();
    final posProvider = context.watch<PosProvider>();
    
    final role = authProvider.currentProfile?.role ?? 'admin';
    final navItems = _getNavigationItems(role, subProvider, posProvider.waiterBillingEnabled);
    
    if (_selectedIndex >= navItems.length) {
      _selectedIndex = 0;
    }

    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 950 && size.width > size.height;

    return Scaffold(
      appBar: AppBar(
        leading: isDesktop
            ? IconButton(
                icon: Icon(_isSidebarOpen ? Icons.menu_open : Icons.menu),
                onPressed: () {
                  setState(() {
                    _isSidebarOpen = !_isSidebarOpen;
                  });
                },
                tooltip: _isSidebarOpen ? 'Close Sidebar' : 'Open Sidebar',
              )
            : null,
        title: Text(
          isDesktop ? 'Café OS' : navItems[_selectedIndex].label,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
        actions: [
          // Notification Bell with Badge
          Consumer<NotificationProvider>(
            builder: (context, notifProvider, child) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined, size: 26),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const NotificationsScreen(),
                        ),
                      );
                    },
                  ),
                  if (notifProvider.unreadCount > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          '${notifProvider.unreadCount}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          Consumer<ConnectivityService>(
            builder: (context, connectivity, child) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Chip(
                  backgroundColor: connectivity.isOnline ? Colors.green.shade100 : Colors.red.shade100,
                  label: Row(
                    children: [
                      Icon(
                        connectivity.isOnline ? Icons.wifi : Icons.wifi_off,
                        color: connectivity.isOnline ? Colors.green : Colors.red,
                        size: 16,
                      ),
                      if (isDesktop) ...[
                        const SizedBox(width: 8),
                        Text(
                          connectivity.isOnline ? 'Online' : 'Offline',
                          style: TextStyle(
                            color: connectivity.isOnline ? Colors.green.shade900 : Colors.red.shade900,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
          if (isDesktop || navItems.length <= 4)
            IconButton(icon: const Icon(Icons.logout), onPressed: () => authProvider.logout()),
        ],
      ),
      drawer: !isDesktop && navItems.length > 4
          ? Drawer(
              child: Column(
                children: [
                  DrawerHeader(
                    decoration: const BoxDecoration(color: AppTheme.surfaceColor),
                    child: Stack(
                      children: [
                        Align(
                          alignment: Alignment.topRight,
                          child: IconButton(
                            icon: const Icon(Icons.close, color: AppTheme.textSecondary),
                            onPressed: () {
                              Navigator.pop(context); // Close the drawer
                            },
                          ),
                        ),
                        Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text(
                                'Café OS',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primaryColor,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                role.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: navItems.length,
                      itemBuilder: (context, index) {
                        final item = navItems[index];
                        final isSelected = _selectedIndex == index;
                        return ListTile(
                          leading: Icon(item.icon, color: isSelected ? AppTheme.primaryColor : AppTheme.textSecondary),
                          title: Text(
                            item.label,
                            style: TextStyle(
                              color: isSelected ? AppTheme.primaryColor : AppTheme.textPrimary,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          selected: isSelected,
                          selectedTileColor: AppTheme.primaryColor.withOpacity(0.1),
                          onTap: () {
                            setState(() => _selectedIndex = index);
                            Navigator.pop(context); // Close the drawer
                          },
                        );
                      },
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.logout, color: Colors.red),
                    title: const Text('Logout', style: TextStyle(color: Colors.red)),
                    onTap: () {
                      Navigator.pop(context);
                      authProvider.logout();
                    },
                  ),
                ],
              ),
            )
          : null,
      body: Row(
        children: [
          if (isDesktop)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: _isSidebarOpen ? 250 : 0,
              color: AppTheme.surfaceColor,
              curve: Curves.easeInOut,
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                child: SizedBox(
                  width: 250,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 16.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const SizedBox(width: 8),
                            const Text(
                              'Café OS',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.menu_open, color: AppTheme.primaryColor),
                              tooltip: 'Close Sidebar',
                              onPressed: () {
                                setState(() {
                                  _isSidebarOpen = false;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          itemCount: navItems.length,
                          itemBuilder: (context, index) {
                            final item = navItems[index];
                            final isSelected = _selectedIndex == index;
                            return ListTile(
                              leading: Icon(item.icon, color: isSelected ? AppTheme.primaryColor : AppTheme.textSecondary),
                              title: Text(item.label, style: TextStyle(color: isSelected ? AppTheme.primaryColor : AppTheme.textPrimary, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                              selected: isSelected,
                              selectedTileColor: AppTheme.primaryColor.withOpacity(0.1),
                              onTap: () => setState(() => _selectedIndex = index),
                            );
                          },
                        ),
                      ),
                      const Divider(),
                      ListTile(
                        leading: const Icon(Icons.logout, color: Colors.red),
                        title: const Text('Logout', style: TextStyle(color: Colors.red)),
                        onTap: () => authProvider.logout(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          
          Expanded(
            child: Column(
              children: [
                
                Consumer<ConnectivityService>(
                  builder: (context, connectivity, child) {
                    if (connectivity.isOnline) return const SizedBox.shrink();
                    
                    return ValueListenableBuilder<Box>(
                      valueListenable: Hive.box('offline_orders').listenable(),
                      builder: (context, offlineBox, child) {
                        return ValueListenableBuilder<Box>(
                          valueListenable: Hive.box('cache').listenable(),
                          builder: (context, cacheBox, child) {
                            final pendingCount = offlineBox.length;
                            final lastSynced = cacheBox.get('last_synced_time') as String?;
                            final lastSyncError = cacheBox.get('last_sync_error') as String?;
                            
                            String formattedSynced = 'Never';
                            if (lastSynced != null) {
                              try {
                                final dt = DateTime.parse(lastSynced).toLocal();
                                final pad = (int n) => n.toString().padLeft(2, '0');
                                formattedSynced = '${pad(dt.hour)}:${pad(dt.minute)}:${pad(dt.second)}';
                              } catch (_) {}
                            }

                            return Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                border: Border(
                                  bottom: BorderSide(color: Colors.red.shade100, width: 1.5),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.signal_wifi_off_rounded,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          '🔴 Offline Session Active',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.red,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Last Synced: $formattedSynced  |  Pending Sync: $pendingCount order(s)',
                                          style: TextStyle(
                                            color: Colors.red.shade900,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        if (lastSyncError != null) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            'Sync failed: $lastSyncError',
                                            style: TextStyle(
                                              color: Colors.red.shade800,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500,
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red.shade700,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    icon: const Icon(Icons.sync, size: 16),
                                    label: const Text('Retry Sync', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                    onPressed: () {
                                      try {
                                        final syncService = context.read<SyncService>();
                                        syncService.syncOfflineOrders();
                                      } catch (e) {
                                        debugPrint('Error triggering sync: $e');
                                      }
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
                Expanded(
                  child: Container(
                    color: AppTheme.backgroundColor,
                    child: _buildCurrentTab(navItems[_selectedIndex].label),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: !isDesktop && navItems.length > 1 && navItems.length <= 4
          ? BottomNavigationBar(
              currentIndex: _selectedIndex,
              onTap: (index) => setState(() => _selectedIndex = index),
              type: BottomNavigationBarType.fixed,
              selectedItemColor: AppTheme.primaryColor,
              unselectedItemColor: AppTheme.textSecondary,
              items: navItems.map((item) => BottomNavigationBarItem(icon: Icon(item.icon), label: item.label)).toList(),
            )
          : null,
    );
  }

  Widget _buildCurrentTab(String label) {
    if (label == 'Dashboard') return const AnalyticsDashboardScreen();
    if (label == 'Menu') return const ProductListScreen();
    if (label == 'POS') return const PosScreen();
    if (label == 'Billing') return const BillingScreen();
    if (label == 'Order History') return const OrderHistoryScreen();
    if (label == 'Kitchen') return const KitchenScreen();
    if (label == 'Tables') return const TableManagementScreen();
    if (label == 'Rooms') return const RoomManagementScreen();
    if (label == 'Bookings') return const BookingsManagementScreen();
    if (label == 'Deliveries') return const DeliveryManagementScreen();

    if (label == 'Inventory') return const InventoryScreen();
    if (label == 'Suppliers') return const SuppliersScreen();
    if (label == 'Expenses') return const ExpensesScreen();
    if (label == 'Dues') return const DuesScreen();
    if (label == 'Settings') return const SettingsScreen();
    
    return Center(
      child: Text('$label Screen\n(Coming soon...)', textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, color: AppTheme.textSecondary)),
    );
  }
}

class _NavigationItem {
  final IconData icon;
  final String label;
  _NavigationItem({required this.icon, required this.label});
}
