import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/presentation/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../orders/presentation/providers/table_provider.dart';
import '../../../orders/data/models/table_model.dart';

class TableManagementScreen extends StatefulWidget {
  const TableManagementScreen({super.key});

  @override
  State<TableManagementScreen> createState() => _TableManagementScreenState();
}

class _TableManagementScreenState extends State<TableManagementScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cafeId = context.read<AuthProvider>().cafeId;
      if (cafeId != null) {
        context.read<TableProvider>().init(cafeId);
      }
    });
  }

  void _showAddTableDialog(TableProvider tableProvider) {
    final nameController = TextEditingController();
    int capacity = 4;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add New Table'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Table Name / Number',
                  hintText: 'e.g. Table 5, T-12',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Capacity (Pax):', style: TextStyle(fontWeight: FontWeight.w600)),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: capacity > 1 ? () => setDialogState(() => capacity--) : null,
                      ),
                      Text('$capacity', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: capacity < 20 ? () => setDialogState(() => capacity++) : null,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) return;
                final success = await tableProvider.createTable(nameController.text.trim(), capacity);
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(success ? 'Table created successfully!' : 'Failed to create table.'),
                      backgroundColor: success ? Colors.green : Colors.red,
                    ),
                  );
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditTableDialog(TableModel table, TableProvider tableProvider) {
    final nameController = TextEditingController(text: table.name);
    int capacity = table.capacity;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Table Details'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Table Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Capacity (Pax):', style: TextStyle(fontWeight: FontWeight.w600)),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: capacity > 1 ? () => setDialogState(() => capacity--) : null,
                      ),
                      Text('$capacity', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: capacity < 20 ? () => setDialogState(() => capacity++) : null,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) return;
                final success = await tableProvider.updateTable(
                  table.id,
                  name: nameController.text.trim(),
                  capacity: capacity,
                );
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(success ? 'Table details updated!' : 'Failed to update table.'),
                      backgroundColor: success ? Colors.green : Colors.red,
                    ),
                  );
                }
              },
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteTable(TableModel table, TableProvider tableProvider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Table'),
        content: Text('Are you sure you want to delete "${table.name}"? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              final success = await tableProvider.deleteTable(table.id);
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success ? 'Table deleted successfully!' : 'Failed to delete table.'),
                    backgroundColor: success ? Colors.green : Colors.red,
                  ),
                );
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tableProvider = context.watch<TableProvider>();

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        onPressed: () => _showAddTableDialog(tableProvider),
        icon: const Icon(Icons.add),
        label: const Text('Create Table'),
      ),
      body: tableProvider.isLoading && tableProvider.allTables.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Configuration Panel',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: () => tableProvider.fetchTables(),
                        tooltip: 'Refresh Tables',
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Create, edit, toggle, or delete tables in your restaurant layout.',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: tableProvider.allTables.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.table_restaurant_outlined, size: 64, color: Colors.grey.shade400),
                                const SizedBox(height: 16),
                                const Text('No tables added yet.', style: TextStyle(fontSize: 18, color: AppTheme.textSecondary)),
                                const SizedBox(height: 8),
                                const Text('Tap "Create Table" to set up your dining room layout.', style: TextStyle(color: Colors.grey)),
                              ],
                            ),
                          )
                        : Builder(
                            builder: (context) {
                              final double screenWidth = MediaQuery.of(context).size.width;
                              int crossAxisCount = 3;
                              double aspectRatio = 1.45;
                              
                              if (screenWidth > 1200) {
                                crossAxisCount = 4;
                              } else if (screenWidth > 800) {
                                crossAxisCount = 3;
                              } else if (screenWidth > 500) {
                                crossAxisCount = 2;
                                aspectRatio = 1.35;
                              } else {
                                crossAxisCount = 1;
                                aspectRatio = 1.85;
                              }

                              return GridView.builder(
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossAxisCount,
                                  childAspectRatio: aspectRatio,
                                  crossAxisSpacing: 16,
                                  mainAxisSpacing: 16,
                                ),
                                itemCount: tableProvider.allTables.length,
                                itemBuilder: (context, index) {
                                  final table = tableProvider.allTables[index];
                                  return _buildConfigTableCard(table, tableProvider);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildConfigTableCard(TableModel table, TableProvider tableProvider) {
    Color statusColor;
    switch (table.status) {
      case 'preparing':
        statusColor = Colors.orange;
        break;
      case 'ready':
        statusColor = Colors.blue;
        break;
      case 'billing_pending':
        statusColor = Colors.purple;
        break;
      case 'occupied':
        statusColor = Colors.grey;
        break;
      default:
        statusColor = Colors.green;
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: table.isActive ? Colors.grey.shade200 : Colors.red.shade100, width: 1.5),
      ),
      color: table.isActive ? Colors.white : Colors.red.shade50.withOpacity(0.4),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      table.name,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: table.isActive ? AppTheme.textPrimary : Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.people_outline, size: 14, color: AppTheme.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          '${table.capacity} pax limit',
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
                Switch(
                  value: table.isActive,
                  activeColor: AppTheme.primaryColor,
                  onChanged: (val) {
                    tableProvider.updateTable(table.id, isActive: val);
                  },
                ),
              ],
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        table.status.toUpperCase(),
                        style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 10),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
                      onPressed: () => _showEditTableDialog(table, tableProvider),
                      tooltip: 'Edit details',
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                      onPressed: () => _deleteTable(table, tableProvider),
                      tooltip: 'Delete table',
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
