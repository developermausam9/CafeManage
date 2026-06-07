import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../core/presentation/theme/app_theme.dart';
import '../../../../core/services/export_service.dart';
import '../../../../core/services/notification_service.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../cafes/presentation/providers/business_setup_provider.dart';
import '../../../operations/presentation/providers/operations_provider.dart';
import '../../../menu/presentation/providers/product_provider.dart';
import '../../../analytics/presentation/providers/analytics_provider.dart';
import '../../../orders/presentation/providers/pos_provider.dart';
import 'printer_settings_screen.dart';
import 'staff_management_screen.dart';
import 'payment_settings_screen.dart';
import 'change_password_screen.dart';
import 'tax_service_charge_screen.dart';
import 'receipt_footer_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;
  bool _darkMode = false;
  bool _permissionGranted = false;
  bool _checkingPermission = false;

  @override
  void initState() {
    super.initState();
    _checkPermissionStatus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cafeId = context.read<AuthProvider>().cafeId;
      if (cafeId != null) {
        context.read<PosProvider>().fetchSettings(cafeId);
      }
    });
  }

  Future<void> _checkPermissionStatus() async {
    final granted = await NotificationService().areNotificationsEnabled();
    if (mounted) setState(() => _permissionGranted = granted);
  }

  @override
  Widget build(BuildContext context) {
    final businessProvider = context.watch<BusinessSetupProvider>();
    final cafe = businessProvider.cafeDetails;
    final authProvider = context.watch<AuthProvider>();
    final role = authProvider.currentProfile?.role?.toLowerCase() ?? 'admin';

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Settings & Export', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Cafe Profile Section
          _buildSectionHeader('Café Profile'),
          Card(
            color: AppTheme.surfaceColor,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppTheme.primaryColor,
                child: Icon(Icons.store, color: Colors.white),
              ),
              title: Text(cafe?.name ?? 'My Café', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(cafe?.address ?? 'Setup your business profile'),
              trailing: const Icon(Icons.edit, size: 20, color: AppTheme.primaryColor),
              onTap: () {
                // Navigate to edit profile
              },
            ),
          ),
          const SizedBox(height: 24),

          // Configuration
          _buildSectionHeader('Configuration'),
          _buildListTile(Icons.receipt_long, 'Tax & Service Charge', 'Manage VAT (13%) and Service Charge', onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const TaxServiceChargeScreen()));
          }),
          _buildListTile(Icons.print, 'Printer Settings', 'Configure thermal printer', onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const PrinterSettingsScreen()));
          }),
          _buildListTile(Icons.qr_code, 'Payment Settings', 'Configure QR code', onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const PaymentSettingsScreen()));
          }),
          _buildListTile(Icons.group, 'Staff Management', 'Manage roles & access', onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const StaffManagementScreen()));
          }),
          _buildListTile(Icons.text_snippet, 'Receipt Footer', 'Change thank you message', onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const ReceiptFooterScreen()));
          }),

          // ── Web Links ──────────────────────────────────────────────────────
          const SizedBox(height: 24),
          _buildSectionHeader('🌐 Web Links (Share with Customers)'),
          _buildWebLinksCard(authProvider.cafeId),

          // Admin override settings
          if (role == 'owner' || role == 'admin') ...[
            const SizedBox(height: 24),
            _buildSectionHeader('Staff Controls'),
            SwitchListTile(
              activeColor: AppTheme.primaryColor,
              title: const Text('Waiter Billing Override', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Allow waiters to access billing & finalize payments'),
              value: context.watch<PosProvider>().waiterBillingEnabled,
              onChanged: (val) async {
                final cafeId = context.read<AuthProvider>().cafeId;
                if (cafeId != null) {
                  final success = await context.read<PosProvider>().updateWaiterBillingOverride(cafeId, val);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(success 
                            ? 'Waiter billing override ${val ? "enabled" : "disabled"}' 
                            : 'Failed to update waiter billing override'),
                        backgroundColor: success ? Colors.green : Colors.red,
                      ),
                    );
                  }
                }
              },
            ),
          ],
          
          const SizedBox(height: 24),

          // ── Notifications & Diagnostics ──────────────────────────────────────
          _buildSectionHeader('Notifications & Diagnostics'),
          _buildNotificationDiagnosticsCard(context),
          const SizedBox(height: 24),

          // App Preferences
          _buildSectionHeader('Preferences'),
          SwitchListTile(
            activeColor: AppTheme.primaryColor,
            title: const Text('Push Notifications', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Stock alerts, sync status'),
            value: _notificationsEnabled,
            onChanged: (val) => setState(() => _notificationsEnabled = val),
          ),
          SwitchListTile(
            activeColor: AppTheme.primaryColor,
            title: const Text('Dark Mode', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Enable dark theme'),
            value: _darkMode,
            onChanged: (val) => setState(() => _darkMode = val),
          ),
          _buildListTile(Icons.lock, 'Change Password', 'Update your login password', onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const ChangePasswordScreen()));
          }),
          _buildListTile(Icons.access_time_filled_outlined, 'Timezone Debug Checker', 'Verify local device and UTC clock alignment', onTap: () {
            _showTimezoneDebugDialog(context);
          }),

          const SizedBox(height: 24),

          // Data & Export
          _buildSectionHeader('Data Export'),
          _buildExportTile(context, 'Export Sales', Icons.trending_up, () async {
            // Pick date range, then fetch orders from analytics provider
            final now = DateTime.now();
            final picked = await showDateRangePicker(
              context: context,
              firstDate: DateTime(now.year - 1),
              lastDate: now,
              initialDateRange: DateTimeRange(
                start: DateTime(now.year, now.month, 1),
                end: now,
              ),
              builder: (ctx, child) => Theme(
                data: ThemeData.light().copyWith(
                  colorScheme: const ColorScheme.light(primary: AppTheme.primaryColor),
                ),
                child: child!,
              ),
            );
            if (picked == null) return;
            final analyticsProvider = context.read<AnalyticsProvider>();
            final cafeId = context.read<AuthProvider>().cafeId;
            if (cafeId == null) return;
            // Re-fetch with selected range
            await analyticsProvider.fetchDataForRange(cafeId, picked.start, picked.end);
            await ExportService().exportSales(analyticsProvider.orders);
          }),
          _buildExportTile(context, 'Export Inventory', Icons.inventory_2, () async {
             final products = context.read<ProductProvider>().products;
             await ExportService().exportInventory(products);
          }),
          _buildExportTile(context, 'Export Expenses', Icons.money_off, () async {
             final expenses = context.read<OperationsProvider>().expenses;
             await ExportService().exportExpenses(expenses);
          }),
          _buildExportTile(context, 'Export Customer Dues', Icons.warning_amber, () async {
             final dues = context.read<OperationsProvider>().customerDues;
             await ExportService().exportDues(dues);
          }),

          const SizedBox(height: 32),


          // Logout
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: const BorderSide(color: Colors.red),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.logout, color: Colors.red),
              label: const Text('Logout', style: TextStyle(color: Colors.red, fontSize: 16, fontWeight: FontWeight.bold)),
              onPressed: () async {
                await context.read<AuthProvider>().logout();
              },
            ),
          ),
          const SizedBox(height: 24),
          const Center(
            child: Text('Version 1.0.0 (Production Build)', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildWebLinksCard(String? cafeId) {
    const baseUrl = 'https://cafemanage-gamma.vercel.app';
    final bookingUrl = cafeId != null
        ? '$baseUrl/#/book?cafe_id=$cafeId'
        : '$baseUrl/#/book';

    void copyUrl(String url, String label) {
      Clipboard.setData(ClipboardData(text: url));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$label URL copied!'),
          backgroundColor: AppTheme.primaryColor,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    return Card(
      color: AppTheme.surfaceColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppTheme.primaryColor.withOpacity(0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Booking Portal
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.book_online, color: Colors.blue, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Room Booking Portal',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      Text('Share this link with guests to book rooms online',
                          style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      bookingUrl,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: Colors.blue.shade800,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => copyUrl(bookingUrl, 'Booking Portal'),
                    icon: const Icon(Icons.copy, size: 18),
                    color: Colors.blue,
                    tooltip: 'Copy URL',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),

            // In-Room Ordering Info
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.qr_code_scanner, color: Colors.orange, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('In-Room QR (Auto-Generated)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      Text('Generated automatically when you Check In a guest',
                          style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.orange, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Go to Bookings → Checked In → Room QR to print and give to guests.',
                      style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                    ),
                  ),
                ],
              ),
            ),
            if (cafeId == null) ...[ 
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber, color: Colors.red, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Could not determine your Café ID. Please log out and log back in.',
                        style: TextStyle(fontSize: 12, color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: AppTheme.textSecondary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildListTile(IconData icon, String title, String subtitle, {VoidCallback? onTap}) {
    return Card(
      color: AppTheme.surfaceColor,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(icon, color: AppTheme.textSecondary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
        onTap: onTap,
      ),
    );
  }

  Widget _buildExportTile(BuildContext context, String title, IconData icon, Future<void> Function() onExport) {
    return Card(
      color: AppTheme.surfaceColor,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(icon, color: Colors.green),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.download, color: Colors.green),
        onTap: () async {
          try {
            await onExport();
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Export successful')));
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red));
          }
        },
      ),
    );
  }

  Widget _buildNotificationDiagnosticsCard(BuildContext context) {
    return Card(
      color: AppTheme.surfaceColor,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Permission Status Row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _permissionGranted
                        ? Colors.green.withOpacity(0.1)
                        : Colors.red.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _permissionGranted
                        ? Icons.notifications_active_rounded
                        : Icons.notifications_off_rounded,
                    color: _permissionGranted ? Colors.green.shade700 : Colors.red.shade700,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Android Notification Permission',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      Text(
                        _permissionGranted
                            ? 'Granted — Notifications will appear in system tray'
                            : 'Not granted — Notifications will be silenced',
                        style: TextStyle(
                          fontSize: 12,
                          color: _permissionGranted
                              ? Colors.green.shade700
                              : Colors.red.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Action Buttons
            Row(
              children: [
                // Request Permission
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(
                        color: _permissionGranted
                            ? Colors.grey.shade300
                            : AppTheme.primaryColor,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: _checkingPermission
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            Icons.shield_rounded,
                            size: 18,
                            color: _permissionGranted
                                ? Colors.grey
                                : AppTheme.primaryColor,
                          ),
                    label: Text(
                      _permissionGranted ? 'Granted ✓' : 'Request Permission',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _permissionGranted
                            ? Colors.grey
                            : AppTheme.primaryColor,
                        fontSize: 13,
                      ),
                    ),
                    onPressed: _permissionGranted
                        ? null
                        : () async {
                            setState(() => _checkingPermission = true);
                            final granted =
                                await NotificationService().requestPermission();
                            if (mounted) {
                              setState(() {
                                _permissionGranted = granted;
                                _checkingPermission = false;
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    granted
                                        ? '✅ Permission granted! Notifications enabled.'
                                        : '❌ Permission denied. Enable in Android Settings.',
                                  ),
                                  backgroundColor:
                                      granted ? Colors.green : Colors.red,
                                ),
                              );
                            }
                          },
                  ),
                ),
                const SizedBox(width: 12),

                // Send Test Notification
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.notifications_rounded, size: 18),
                    label: const Text(
                      'Send Test',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    onPressed: () async {
                      await NotificationService().showTestNotification();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              '🔔 Test notification sent! Pull down the Android notification shade to see it.',
                            ),
                            backgroundColor: Colors.indigo,
                            duration: Duration(seconds: 4),
                          ),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Pull down the Android notification shade after tapping "Send Test" to confirm delivery.',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade500,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTimezoneDebugDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        final now = DateTime.now();
        final utc = now.toUtc();
        final local = utc.toLocal();

        return AlertDialog(
          title: const Text('Timezone Alignment Audit', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDebugRow('Device Local Time:', now.toString()),
              const Divider(height: 20),
              _buildDebugRow('Database UTC Time:', utc.toString()),
              const Divider(height: 20),
              _buildDebugRow('Converted Local Time:', local.toString()),
              const Divider(height: 24),
              Text(
                'Status: ${now.difference(local).inSeconds.abs() < 5 ? "Synced & Correct!" : "Offset Mismatch!"}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: now.difference(local).inSeconds.abs() < 5 ? Colors.green.shade700 : Colors.red,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDebugRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textSecondary)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: AppTheme.textPrimary)),
      ],
    );
  }
}
