import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/presentation/theme/app_theme.dart';
import '../../../../core/utils/snackbar_helper.dart';
import '../providers/notification_provider.dart';
import '../../data/models/notification_model.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text(
          'Notifications',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
        ),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.textPrimary,
        actions: [
          Consumer<NotificationProvider>(
            builder: (context, provider, child) {
              if (provider.notifications.isEmpty) return const SizedBox.shrink();
              return TextButton.icon(
                icon: const Icon(Icons.done_all, size: 18),
                label: const Text(
                  'Mark all as read',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primaryColor,
                ),
                onPressed: () async {
                  await provider.markAllAsRead();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('All notifications marked as read'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                },
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Consumer<NotificationProvider>(
        builder: (context, provider, child) {
          final notifications = provider.notifications;

          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (notifications.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withOpacity(0.05),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.notifications_off_outlined,
                      size: 64,
                      color: AppTheme.primaryColor.withOpacity(0.4),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'All Caught Up!',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No new alerts or notifications at this time.',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: notifications.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final n = notifications[index];
              return _NotificationCard(notification: n, provider: provider);
            },
          );
        },
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final NotificationModel notification;
  final NotificationProvider provider;

  const _NotificationCard({
    required this.notification,
    required this.provider,
  });

  Color _getBadgeColor() {
    switch (notification.type.toLowerCase()) {
      case 'low_stock':
      case 'stock_alert':
        return Colors.red.shade100;
      case 'order_cancelled':
      case 'order_voided':
      case 'refund':
      case 'payment_failed':
      case 'sync_failed':
      case 'subscription_expired':
      case 'payment_overdue':
        return Colors.red.shade100;
      case 'payment_completed':
      case 'due_payment_received':
        return Colors.green.shade100;
      case 'kot_received':
      case 'item_added_after_kot':
      case 'item_cancelled_after_kot':
        return Colors.amber.shade100;
      case 'kitchen_ready':
      case 'table_ready_for_serving':
      case 'table_ready_for_billing':
        return Colors.teal.shade100;
      default:
        return Colors.blue.shade100;
    }
  }

  Color _getIconColor() {
    switch (notification.type.toLowerCase()) {
      case 'low_stock':
      case 'stock_alert':
      case 'order_cancelled':
      case 'order_voided':
      case 'refund':
      case 'payment_failed':
      case 'sync_failed':
      case 'subscription_expired':
      case 'payment_overdue':
        return Colors.red.shade800;
      case 'payment_completed':
      case 'due_payment_received':
        return Colors.green.shade800;
      case 'kot_received':
      case 'item_added_after_kot':
      case 'item_cancelled_after_kot':
        return Colors.amber.shade900;
      case 'kitchen_ready':
      case 'table_ready_for_serving':
      case 'table_ready_for_billing':
        return Colors.teal.shade800;
      default:
        return Colors.blue.shade800;
    }
  }

  IconData _getIcon() {
    switch (notification.type.toLowerCase()) {
      case 'low_stock':
      case 'stock_alert':
        return Icons.warning_amber_rounded;
      case 'order_cancelled':
      case 'order_voided':
      case 'refund':
        return Icons.cancel_outlined;
      case 'payment_completed':
      case 'due_payment_received':
        return Icons.attach_money_rounded;
      case 'kot_received':
      case 'item_added_after_kot':
        return Icons.restaurant_menu_rounded;
      case 'item_cancelled_after_kot':
        return Icons.remove_circle_outline_rounded;
      case 'kitchen_ready':
      case 'table_ready_for_serving':
        return Icons.room_service_rounded;
      case 'table_ready_for_billing':
        return Icons.receipt_long_rounded;
      case 'payment_failed':
      case 'sync_failed':
        return Icons.sync_problem_rounded;
      case 'subscription_expired':
      case 'payment_overdue':
        return Icons.credit_card_off_rounded;
      default:
        return Icons.notifications_none_rounded;
    }
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inDays < 1) {
      return '${diff.inHours}h ago';
    } else {
      return '${diff.inDays}d ago';
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeStr = _formatTime(notification.createdAt);

    return InkWell(
      onTap: () {
        if (!notification.isRead) {
          provider.markAsRead(notification.id);
        }
        _showDetailsDialog(context);
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: notification.isRead 
                ? Colors.grey.shade100 
                : AppTheme.primaryColor.withOpacity(0.15),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.shade200.withOpacity(0.4),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Circle Icon
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _getBadgeColor(),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _getIcon(),
                color: _getIconColor(),
                size: 22,
              ),
            ),
            const SizedBox(width: 16),
            
            // Text Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          style: TextStyle(
                            fontWeight: notification.isRead ? FontWeight.w600 : FontWeight.bold,
                            fontSize: 16,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        timeStr,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    notification.message,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  
                  if (!notification.isRead) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'NEW',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDetailsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _getBadgeColor(),
                shape: BoxShape.circle,
              ),
              child: Icon(_getIcon(), color: _getIconColor(), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                notification.title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              notification.message,
              style: const TextStyle(fontSize: 15, height: 1.4, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 16),
            Divider(color: Colors.grey.shade200),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Received:',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                ),
                Text(
                  notification.createdAt.toString().substring(0, 19),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ],
            ),
            if (notification.recipientRole != null) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Target Role:',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                  ),
                  Text(
                    notification.recipientRole!.toUpperCase(),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
            if (notification.metadata.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Metadata:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Text(
                  notification.metadata.entries.map((e) => "${e.key}: ${e.value}").join("\n"),
                  style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: Colors.grey.shade700),
                ),
              )
            ]
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
          ),
        ],
      ),
    );
  }
}
