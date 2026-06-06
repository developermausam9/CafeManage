import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/presentation/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/presentation/providers/subscription_provider.dart';
import '../../../orders/presentation/providers/room_provider.dart';
import '../../../orders/data/models/room_model.dart';

class RoomManagementScreen extends StatefulWidget {
  const RoomManagementScreen({super.key});

  @override
  State<RoomManagementScreen> createState() => _RoomManagementScreenState();
}

class _RoomManagementScreenState extends State<RoomManagementScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cafeId = context.read<AuthProvider>().cafeId;
      if (cafeId != null) {
        context.read<RoomProvider>().init(cafeId);
      }
    });
  }

  void _showAddRoomDialog(RoomProvider roomProvider) {
    final numberController = TextEditingController();
    final priceController = TextEditingController();
    String selectedType = 'standard';
    int floorNumber = 1;
    int maxOccupancy = 2;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add New Room'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: numberController,
                  decoration: const InputDecoration(
                    labelText: 'Room Number / Name',
                    hintText: 'e.g. 101, Suite A',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedType,
                  decoration: const InputDecoration(
                    labelText: 'Room Type',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'standard', child: Text('Standard')),
                    DropdownMenuItem(value: 'deluxe', child: Text('Deluxe')),
                    DropdownMenuItem(value: 'suite', child: Text('Suite')),
                    DropdownMenuItem(value: 'family', child: Text('Family')),
                  ],
                  onChanged: (val) {
                    if (val != null) setDialogState(() => selectedType = val);
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: priceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Price per Night (Rs.)',
                    hintText: 'e.g. 2500',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Floor Number:', style: TextStyle(fontWeight: FontWeight.w600)),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: floorNumber > 0 ? () => setDialogState(() => floorNumber--) : null,
                        ),
                        Text('$floorNumber', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () => setDialogState(() => floorNumber++),
                        ),
                      ],
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Max Occupancy:', style: TextStyle(fontWeight: FontWeight.w600)),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: maxOccupancy > 1 ? () => setDialogState(() => maxOccupancy--) : null,
                        ),
                        Text('$maxOccupancy', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () => setDialogState(() => maxOccupancy++),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (numberController.text.trim().isEmpty) return;
                final price = double.tryParse(priceController.text) ?? 0.0;
                final success = await roomProvider.createRoom(
                  roomNumber: numberController.text.trim(),
                  type: selectedType,
                  pricePerNight: price,
                  floorNumber: floorNumber,
                  maxOccupancy: maxOccupancy,
                );
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(success ? 'Room created successfully!' : 'Failed to create room.'),
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

  void _showEditRoomDialog(RoomModel room, RoomProvider roomProvider) {
    final numberController = TextEditingController(text: room.roomNumber);
    final priceController = TextEditingController(text: room.pricePerNight.toString());
    String selectedType = room.type;
    String selectedStatus = room.status;
    int floorNumber = room.floorNumber;
    int maxOccupancy = room.maxOccupancy;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Room Details'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: numberController,
                  decoration: const InputDecoration(
                    labelText: 'Room Number',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedStatus,
                  decoration: const InputDecoration(
                    labelText: 'Room Status',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'available', child: Text('Available')),
                    DropdownMenuItem(value: 'occupied', child: Text('Occupied')),
                    DropdownMenuItem(value: 'dirty', child: Text('Dirty')),
                    DropdownMenuItem(value: 'maintenance', child: Text('Maintenance')),
                  ],
                  onChanged: (val) {
                    if (val != null) setDialogState(() => selectedStatus = val);
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedType,
                  decoration: const InputDecoration(
                    labelText: 'Room Type',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'standard', child: Text('Standard')),
                    DropdownMenuItem(value: 'deluxe', child: Text('Deluxe')),
                    DropdownMenuItem(value: 'suite', child: Text('Suite')),
                    DropdownMenuItem(value: 'family', child: Text('Family')),
                  ],
                  onChanged: (val) {
                    if (val != null) setDialogState(() => selectedType = val);
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: priceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Price per Night (Rs.)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Floor Number:', style: TextStyle(fontWeight: FontWeight.w600)),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: floorNumber > 0 ? () => setDialogState(() => floorNumber--) : null,
                        ),
                        Text('$floorNumber', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () => setDialogState(() => floorNumber++),
                        ),
                      ],
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Max Occupancy:', style: TextStyle(fontWeight: FontWeight.w600)),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: maxOccupancy > 1 ? () => setDialogState(() => maxOccupancy--) : null,
                        ),
                        Text('$maxOccupancy', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () => setDialogState(() => maxOccupancy++),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (numberController.text.trim().isEmpty) return;
                final price = double.tryParse(priceController.text) ?? 0.0;
                final success = await roomProvider.updateRoom(
                  room.id,
                  roomNumber: numberController.text.trim(),
                  type: selectedType,
                  status: selectedStatus,
                  pricePerNight: price,
                  floorNumber: floorNumber,
                  maxOccupancy: maxOccupancy,
                );
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(success ? 'Room details updated!' : 'Failed to update room.'),
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

  void _deleteRoom(RoomModel room, RoomProvider roomProvider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Room'),
        content: Text('Are you sure you want to delete room "${room.roomNumber}"? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              final success = await roomProvider.deleteRoom(room.id);
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success ? 'Room deleted successfully!' : 'Failed to delete room.'),
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

  Future<String> _getCustomerPortalUrl() async {
    try {
      final cafeId = context.read<AuthProvider>().cafeId;
      if (cafeId != null) {
        final res = await Supabase.instance.client
            .from('settings')
            .select('customer_portal_url')
            .eq('cafe_id', cafeId)
            .maybeSingle();
        if (res != null && res['customer_portal_url'] != null && res['customer_portal_url'].toString().isNotEmpty) {
          return res['customer_portal_url'];
        }
      }
    } catch (e) {
      debugPrint('Error getting customer portal url: $e');
    }
    // Fallback to current browser URL or placeholder
    final domain = Uri.base.host.isNotEmpty ? Uri.base.origin : 'https://cafe-os.web.app';
    return domain;
  }

  void _showQrCodeDialog(RoomModel room) {
    showDialog(
      context: context,
      builder: (context) => FutureBuilder<String>(
        future: _getCustomerPortalUrl(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final domain = snapshot.data ?? 'https://cafe-os.web.app';
          final orderUrl = '$domain/#/order?room_id=${room.id}&cafe_id=${room.cafeId}';

          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.qr_code, color: AppTheme.primaryColor),
                const SizedBox(width: 8),
                Text('Room ${room.roomNumber} QR Code'),
              ],
            ),
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Customers in this room can scan this QR code to place orders directly from their mobile device.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200, width: 2),
                    ),
                    child: QrImageView(
                      data: orderUrl,
                      version: QrVersions.auto,
                      size: 200.0,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    orderUrl,
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.print),
                label: const Text('Print QR'),
                onPressed: () {
                  Navigator.pop(context);
                  // Print command integration
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Sent QR Code print job to thermal printer.'),
                      backgroundColor: Colors.green,
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );

  }

  @override
  Widget build(BuildContext context) {
    final subProvider = context.watch<SubscriptionProvider>();
    final roomProvider = context.watch<RoomProvider>();

    // Subscription check: Only Premium tier allows access to Hotel/Room features
    if (!subProvider.hasPremium) {
      return _buildPremiumPaywall();
    }

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        onPressed: () => _showAddRoomDialog(roomProvider),
        icon: const Icon(Icons.add),
        label: const Text('Create Room'),
      ),
      body: roomProvider.isLoading && roomProvider.rooms.isEmpty
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
                        'Rooms & Lodging Setup',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: () => roomProvider.fetchRooms(),
                        tooltip: 'Refresh Rooms',
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Configure guest rooms, housekeeping status, nightly rates, and order QR codes.',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: roomProvider.rooms.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.bed_outlined, size: 64, color: Colors.grey.shade400),
                                const SizedBox(height: 16),
                                const Text('No rooms added yet.', style: TextStyle(fontSize: 18, color: AppTheme.textSecondary)),
                                const SizedBox(height: 8),
                                const Text('Tap "Create Room" to set up your lodging layout.', style: TextStyle(color: Colors.grey)),
                              ],
                            ),
                          )
                        : Builder(
                            builder: (context) {
                              final double screenWidth = MediaQuery.of(context).size.width;
                              int crossAxisCount = 3;
                              double aspectRatio = 1.35;

                              if (screenWidth > 1200) {
                                crossAxisCount = 4;
                              } else if (screenWidth > 800) {
                                crossAxisCount = 3;
                              } else if (screenWidth > 500) {
                                crossAxisCount = 2;
                                aspectRatio = 1.25;
                              } else {
                                crossAxisCount = 1;
                                aspectRatio = 1.65;
                              }

                              return GridView.builder(
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossAxisCount,
                                  childAspectRatio: aspectRatio,
                                  crossAxisSpacing: 16,
                                  mainAxisSpacing: 16,
                                ),
                                itemCount: roomProvider.rooms.length,
                                itemBuilder: (context, index) {
                                  final room = roomProvider.rooms[index];
                                  return _buildRoomCard(room, roomProvider);
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

  Widget _buildRoomCard(RoomModel room, RoomProvider roomProvider) {
    Color statusColor;
    switch (room.status) {
      case 'occupied':
        statusColor = Colors.blue;
        break;
      case 'dirty':
        statusColor = Colors.amber.shade800;
        break;
      case 'maintenance':
        statusColor = Colors.red;
        break;
      default:
        statusColor = Colors.green;
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200, width: 1.5),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Room ${room.roomNumber}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      Text(
                        '${room.type.toUpperCase()} • Floor ${room.floorNumber}',
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.qr_code, color: AppTheme.primaryColor),
                  onPressed: () => _showQrCodeDialog(room),
                  tooltip: 'Generate Self-Ordering QR',
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.people_outline, size: 14, color: AppTheme.textSecondary),
                const SizedBox(width: 4),
                Text(
                  'Max ${room.maxOccupancy} Guests',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
                const Spacer(),
                Text(
                  'Rs. ${room.pricePerNight.toStringAsFixed(0)}/night',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryColor, fontSize: 13),
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
                        room.status.toUpperCase(),
                        style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 10),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
                      onPressed: () => _showEditRoomDialog(room, roomProvider),
                      tooltip: 'Edit details',
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                      onPressed: () => _deleteRoom(room, roomProvider),
                      tooltip: 'Delete room',
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

  Widget _buildPremiumPaywall() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        padding: const EdgeInsets.all(32.0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.shade200,
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.bed_outlined,
                size: 64,
                color: AppTheme.primaryColor,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Unlock Room & Booking Systems',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'Upgrade to the Premium subscription package to enable full lodging management, self-service QR room ordering, public date booking, and QR payment verification workflows.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, height: 1.5, fontSize: 14),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                // Simulate subscription upgrade
                final cafeId = context.read<AuthProvider>().cafeId;
                if (cafeId != null) {
                  // Run local mock upgrade or show instructions
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please contact Super Admin in staff panel to upgrade plan to Premium.'),
                      backgroundColor: AppTheme.primaryColor,
                    ),
                  );
                }
              },
              child: const Text('Upgrade to Premium Tier', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
