import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/presentation/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import 'super_admin_settings_screen.dart';
import 'super_admin_dashboard_screen.dart';
import 'cafe_list_screen.dart';

class SuperAdminShell extends StatefulWidget {
  const SuperAdminShell({super.key});

  @override
  State<SuperAdminShell> createState() => _SuperAdminShellState();
}

class _SuperAdminShellState extends State<SuperAdminShell> {
  int _selectedIndex = 0;

  final _navItems = [
    _NavigationItem(icon: Icons.dashboard, label: 'Overview'),
    _NavigationItem(icon: Icons.store, label: 'Cafés'),
    _NavigationItem(icon: Icons.settings, label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 800;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Super Admin Panel'),
        elevation: 0,
        backgroundColor: Colors.indigo.shade900,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout), 
            onPressed: () => context.read<AuthProvider>().logout()
          ),
        ],
      ),
      body: Row(
        children: [
          if (isDesktop)
            Container(
              width: 250,
              color: AppTheme.surfaceColor,
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    color: Colors.indigo.shade900,
                    padding: const EdgeInsets.all(24.0),
                    child: const Text(
                      'SaaS Manager', 
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _navItems.length,
                      itemBuilder: (context, index) {
                        final item = _navItems[index];
                        final isSelected = _selectedIndex == index;
                        return ListTile(
                          leading: Icon(item.icon, color: isSelected ? Colors.indigo.shade700 : AppTheme.textSecondary),
                          title: Text(item.label, style: TextStyle(color: isSelected ? Colors.indigo.shade700 : AppTheme.textPrimary, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                          selected: isSelected,
                          selectedTileColor: Colors.indigo.shade50,
                          onTap: () => setState(() => _selectedIndex = index),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          
          Expanded(
            child: Column(
              children: [
                if (!isDesktop)
                  AppBar(
                    title: Text(_navItems[_selectedIndex].label),
                    backgroundColor: Colors.indigo.shade700,
                  ),
                Expanded(
                  child: Container(
                    color: AppTheme.backgroundColor,
                    child: _buildCurrentTab(_navItems[_selectedIndex].label),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: !isDesktop
          ? BottomNavigationBar(
              currentIndex: _selectedIndex,
              onTap: (index) => setState(() => _selectedIndex = index),
              selectedItemColor: Colors.indigo.shade700,
              items: _navItems.map((item) => BottomNavigationBarItem(icon: Icon(item.icon), label: item.label)).toList(),
            )
          : null,
    );
  }

  Widget _buildCurrentTab(String label) {
    if (label == 'Overview') return const SuperAdminDashboardScreen();
    if (label == 'Cafés') return const CafeListScreen();
    if (label == 'Settings') return const SuperAdminSettingsScreen();
    return const Center(child: Text('Coming soon...'));
  }
}

class _NavigationItem {
  final IconData icon;
  final String label;
  _NavigationItem({required this.icon, required this.label});
}
