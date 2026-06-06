import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/presentation/widgets/stat_card.dart';
import '../providers/super_admin_provider.dart';
import '../../data/models/cafe_with_subscription_model.dart';
import 'create_cafe_screen.dart';
import 'edit_cafe_screen.dart';
import 'create_super_admin_screen.dart';
import '../../../../core/presentation/theme/app_theme.dart';
import '../../../settings/presentation/pages/change_password_screen.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class SuperAdminDashboardScreen extends StatefulWidget {
  const SuperAdminDashboardScreen({super.key});

  @override
  State<SuperAdminDashboardScreen> createState() => _SuperAdminDashboardScreenState();
}

class _SuperAdminDashboardScreenState extends State<SuperAdminDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SuperAdminProvider>().fetchAllCafes();
      context.read<SuperAdminProvider>().fetchStats();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Super Admin Dashboard'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'add_super_admin') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CreateSuperAdminScreen()),
                );
              } else if (value == 'change_password') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
                );
              } else if (value == 'logout') {
                context.read<AuthProvider>().logout();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'add_super_admin',
                child: Row(children: [Icon(Icons.person_add, color: AppTheme.primaryColor), SizedBox(width: 8), Text('Add Super Admin')]),
              ),
              const PopupMenuItem(
                value: 'change_password',
                child: Row(children: [Icon(Icons.lock, color: AppTheme.primaryColor), SizedBox(width: 8), Text('Change Password')]),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: Row(children: [Icon(Icons.logout, color: Colors.red), SizedBox(width: 8), Text('Logout', style: TextStyle(color: Colors.red))]),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreateCafeScreen()),
          ).then((_) {
            if (mounted) {
              context.read<SuperAdminProvider>().fetchAllCafes();
              context.read<SuperAdminProvider>().fetchStats();
            }
          });
        },
        child: const Icon(Icons.add),
        tooltip: 'Create New Café',
      ),
      body: Consumer<SuperAdminProvider>(
        builder: (context, provider, child) {
          final stats = provider.stats;
          final cafes = provider.cafes;
          final isLoading = provider.state == SuperAdminState.loading;

          return RefreshIndicator(
            onRefresh: () async {
              await provider.fetchAllCafes();
              await provider.fetchStats();
            },
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('SaaS Overview', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 24),
                  if (stats.isNotEmpty)
                    LayoutBuilder(
                      builder: (context, constraints) {
                        int crossAxisCount = constraints.maxWidth > 800 ? 4 : (constraints.maxWidth > 600 ? 2 : 1);
                        return GridView.count(
                          crossAxisCount: crossAxisCount,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: 2,
                          children: [
                            StatCard(
                              title: 'Total Cafés',
                              value: stats['total_cafes'].toString(),
                              icon: Icons.store,
                              iconColor: Colors.blue,
                            ),
                            StatCard(
                              title: 'Active Subscriptions',
                              value: stats['active_cafes'].toString(),
                              icon: Icons.check_circle,
                              iconColor: Colors.green,
                            ),
                            StatCard(
                              title: 'Suspended Cafés',
                              value: stats['suspended_cafes'].toString(),
                              icon: Icons.warning,
                              iconColor: Colors.orange,
                            ),
                            StatCard(
                              title: 'MRR',
                              value: 'Rs. ${stats['mrr']?.toStringAsFixed(0)}',
                              icon: Icons.attach_money,
                              iconColor: Colors.indigo,
                            ),
                          ],
                        );
                      },
                    ),
                  const SizedBox(height: 32),
                  const Text('Cafés Directory', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  if (isLoading && cafes.isEmpty)
                    const Center(child: CircularProgressIndicator())
                  else if (cafes.isEmpty)
                    const Center(child: Text('No cafés found. Create one!'))
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: cafes.length,
                      itemBuilder: (context, index) {
                        final item = cafes[index];
                        final isActive = item.subscription?.isActive ?? false;
                        final statusText = item.cafe.status.toUpperCase();
                        final statusColor = item.cafe.status == 'active' ? Colors.green : Colors.red;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.blue.shade100,
                              child: const Icon(Icons.store, color: Colors.blue),
                            ),
                            title: Text(item.cafe.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('Owner: ${item.owner?.fullName ?? 'N/A'} | Plan: ${item.subscription?.planType ?? 'N/A'}\nStatus: $statusText'),
                            isThreeLine: true,
                            trailing: PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'edit') {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => EditCafeScreen(cafeData: item)),
                                  ).then((_) {
                                    if (mounted) {
                                      provider.fetchAllCafes();
                                      provider.fetchStats();
                                    }
                                  });
                                } else if (value == 'toggle_status') {
                                  provider.toggleCafeSuspension(item.cafe.id, item.cafe.status == 'suspended');
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Row(children: [Icon(Icons.edit, size: 20), SizedBox(width: 8), Text('Edit')]),
                                ),
                                PopupMenuItem(
                                  value: 'toggle_status',
                                  child: Row(children: [
                                    Icon(item.cafe.status == 'suspended' ? Icons.check_circle : Icons.block, size: 20, color: statusColor), 
                                    const SizedBox(width: 8), 
                                    Text(item.cafe.status == 'suspended' ? 'Reactivate' : 'Suspend')
                                  ]),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
