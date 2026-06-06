import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/super_admin_provider.dart';
import 'create_cafe_screen.dart';
import 'edit_cafe_screen.dart';

class CafeListScreen extends StatefulWidget {
  const CafeListScreen({super.key});

  @override
  State<CafeListScreen> createState() => _CafeListScreenState();
}

class _CafeListScreenState extends State<CafeListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SuperAdminProvider>().fetchAllCafes();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SuperAdminProvider>(
      builder: (context, provider, child) {
        if (provider.state == SuperAdminState.loading) {
          return const Center(child: CircularProgressIndicator());
        }

        final cafes = provider.cafes;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('All Cafés', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const CreateCafeScreen()),
                      ).then((_) {
                        if (mounted) {
                          context.read<SuperAdminProvider>().fetchAllCafes();
                        }
                      });
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Add Cafe'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: cafes.length,
                itemBuilder: (context, index) {
                  final data = cafes[index];
                  final cafe = data.cafe;
                  final owner = data.owner;
                  final sub = data.subscription;
                  
                  final isSuspended = cafe.status == 'suspended';

                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      title: Text(cafe.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text('Owner: ${owner?.fullName ?? "No owner"} | Email: ${cafe.ownerEmail ?? "N/A"}'),
                          const SizedBox(height: 4),
                          Text('Plan: ${sub?.planType ?? "Basic"} | Fee: Rs. ${sub?.monthlyFee ?? 0}'),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Chip(
                            label: Text(
                              isSuspended ? 'Suspended' : 'Active',
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                            ),
                            backgroundColor: isSuspended ? Colors.red : Colors.green,
                          ),
                          const SizedBox(width: 8),
                          Switch(
                            value: !isSuspended,
                            activeColor: Colors.green,
                            onChanged: (val) {
                              provider.toggleCafeSuspension(cafe.id, isSuspended);
                            },
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.indigo),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => EditCafeScreen(cafeData: data)),
                              ).then((_) {
                                if (mounted) {
                                  provider.fetchAllCafes();
                                }
                              });
                            },
                            tooltip: 'Edit Café',
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
