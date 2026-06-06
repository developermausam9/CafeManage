import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/presentation/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/kitchen_provider.dart';

class KitchenScreen extends StatefulWidget {
  const KitchenScreen({super.key});

  @override
  State<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends State<KitchenScreen> {
  int _activeKitchenTabIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cafeId = context.read<AuthProvider>().cafeId;
      if (cafeId != null) {
        context.read<KitchenProvider>().init(cafeId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 950 && size.width > size.height;

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Consumer<KitchenProvider>(
        builder: (context, provider, child) {
          if (provider.state == KitchenState.loading && provider.kitchenOrders.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.state == KitchenState.error) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(provider.errorMessage ?? 'Error loading KOTs', style: const TextStyle(fontSize: 18, color: AppTheme.textSecondary)),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () => provider.fetchOrders(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          if (isDesktop) {
            return Column(
              children: [
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Kitchen Display (KOT)',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: () {
                          context.read<KitchenProvider>().fetchOrders();
                        },
                        tooltip: 'Refresh KOTs',
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildColumn('Pending', provider.pendingOrders, 'preparing', Colors.orange, provider)),
                      const VerticalDivider(width: 1, thickness: 1),
                      Expanded(child: _buildColumn('Preparing', provider.preparingOrders, 'ready', Colors.blue, provider)),
                      const VerticalDivider(width: 1, thickness: 1),
                      Expanded(child: _buildColumn('Ready to Serve', provider.readyOrders, 'served', Colors.green, provider)),
                    ],
                  ),
                ),
              ],
            );
          } else {
            return Column(
              children: [
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: SegmentedButton<int>(
                          segments: [
                            ButtonSegment(
                              value: 0,
                              label: Text('Pending (${provider.pendingOrders.length})'),
                            ),
                            ButtonSegment(
                              value: 1,
                              label: Text('Prep (${provider.preparingOrders.length})'),
                            ),
                            ButtonSegment(
                              value: 2,
                              label: Text('Ready (${provider.readyOrders.length})'),
                            ),
                          ],
                          selected: {_activeKitchenTabIndex},
                          onSelectionChanged: (set) {
                            setState(() {
                              _activeKitchenTabIndex = set.first;
                            });
                          },
                          showSelectedIcon: false,
                          style: const ButtonStyle(
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: () {
                          context.read<KitchenProvider>().fetchOrders();
                        },
                        tooltip: 'Refresh KOTs',
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Builder(
                    builder: (context) {
                      switch (_activeKitchenTabIndex) {
                        case 0:
                          return _buildColumn('Pending', provider.pendingOrders, 'preparing', Colors.orange, provider);
                        case 1:
                          return _buildColumn('Preparing', provider.preparingOrders, 'ready', Colors.blue, provider);
                        case 2:
                          return _buildColumn('Ready to Serve', provider.readyOrders, 'served', Colors.green, provider);
                        default:
                          return const SizedBox.shrink();
                      }
                    },
                  ),
                ),
              ],
            );
          }
        },
      ),
    );
  }

  Widget _buildColumn(String title, List<KitchenOrder> orders, String nextStatus, Color headerColor, KitchenProvider provider) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          decoration: BoxDecoration(
            color: headerColor.withOpacity(0.08),
            border: Border(bottom: BorderSide(color: headerColor.withOpacity(0.2), width: 2)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: headerColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                '$title (${orders.length})',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: headerColor),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              await provider.fetchOrders();
            },
            child: orders.isEmpty
                ? SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: SizedBox(
                      height: 400,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_outline, size: 40, color: Colors.grey.shade400),
                            const SizedBox(height: 8),
                            Text('No orders in $title', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(12),
                    itemCount: orders.length,
                    itemBuilder: (context, index) {
                      final order = orders[index];
                      return _buildKotCard(order, nextStatus, headerColor, provider);
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildKotCard(KitchenOrder order, String nextStatus, Color headerColor, KitchenProvider provider) {
    // Format timestamp
    String timestamp = '00:00';
    if (order.order.createdAt != null) {
      final localTime = order.order.createdAt!.toLocal();
      timestamp = '${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}';
    }

    String actionLabel = '';
    IconData actionIcon;
    switch (nextStatus) {
      case 'preparing':
        actionLabel = 'Start Preparing';
        actionIcon = Icons.cookie;
        break;
      case 'ready':
        actionLabel = 'Mark Ready';
        actionIcon = Icons.done_all;
        break;
      case 'served':
        actionLabel = 'Mark Served';
        actionIcon = Icons.room_service;
        break;
      default:
        actionLabel = 'Advance Order';
        actionIcon = Icons.arrow_forward;
    }

    final isRoomService = order.order.roomId != null;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isRoomService ? Colors.blue.shade300 : Colors.grey.shade200,
            width: isRoomService ? 2.0 : 1.0,
          ),
          color: isRoomService ? Colors.blue.shade50.withOpacity(0.15) : Colors.white,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Card Header: Table/Room & Time
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        isRoomService ? Icons.bed_outlined : Icons.table_restaurant,
                        size: 18,
                        color: isRoomService ? Colors.blue.shade700 : AppTheme.primaryColor,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isRoomService
                            ? 'Room ${order.order.roomName ?? 'Unknown'}'
                            : (order.order.tableName != null
                                ? '${order.order.tableName}'
                                : (order.order.tableId != null ? 'Table ${order.order.tableId!.substring(0, 4)}' : order.order.type)),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: isRoomService ? Colors.blue.shade900 : AppTheme.textPrimary,
                        ),
                      ),
                      if (isRoomService) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'ROOM SERVICE',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade900,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Row(
                    children: [
                      const Icon(Icons.access_time, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        timestamp,
                        style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              
              // Waiter name / QR info row
              Row(
                children: [
                  Icon(
                    isRoomService ? Icons.qr_code_scanner : Icons.person_outline,
                    size: 14,
                    color: AppTheme.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isRoomService ? 'QR Self-Ordered' : 'Waiter: ${order.order.waiterName ?? 'Unknown'}',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                ],
              ),

              const Divider(height: 20),
              
              // KOT Items
              ...order.items.map((item) {
                final isAdded = item.status == 'added';
                final isCancelled = item.status == 'cancelled';
                
                Color itemColor = isCancelled 
                    ? Colors.red 
                    : (isAdded ? Colors.green.shade700 : AppTheme.textPrimary);
                
                TextStyle nameStyle = TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: itemColor,
                  decoration: isCancelled ? TextDecoration.lineThrough : null,
                );

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isCancelled 
                              ? Colors.red.shade50 
                              : (isAdded ? Colors.green.shade50 : headerColor.withOpacity(0.1)),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isCancelled 
                                ? Colors.red.shade200 
                                : (isAdded ? Colors.green.shade200 : Colors.transparent),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          '${item.quantity.toInt()}x',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: isCancelled 
                                ? Colors.red.shade700 
                                : (isAdded ? Colors.green.shade700 : headerColor),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item.productName,
                                    style: nameStyle,
                                  ),
                                ),
                                if (isAdded) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(4)),
                                    child: const Text('ADDED', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.green)),
                                  ),
                                ],
                                if (isCancelled) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(4)),
                                    child: const Text('CANCELLED', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.red)),
                                  ),
                                ],
                              ],
                            ),
                            if (isCancelled && item.cancellationReason != null && item.cancellationReason!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Text(
                                  'Reason: ${item.cancellationReason}',
                                  style: TextStyle(color: Colors.red.shade700, fontSize: 12, fontWeight: FontWeight.w500, fontStyle: FontStyle.italic),
                                ),
                              ),
                            if (item.notes != null && item.notes!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 3.0),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.red.shade100),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.edit_note, size: 14, color: Colors.red.shade900),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          item.notes!,
                                          style: TextStyle(color: Colors.red.shade900, fontSize: 11, fontStyle: FontStyle.italic, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 16),
              
              // Action Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: headerColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => provider.updateOrderStatus(order.order.id, nextStatus),
                  icon: Icon(actionIcon, size: 16),
                  label: Text(actionLabel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
