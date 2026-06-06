import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/presentation/theme/app_theme.dart';
import '../../../../core/presentation/widgets/app_button.dart';
import '../../../../core/presentation/providers/printer_provider.dart';
import '../../../../core/services/models/printer_config_model.dart';
import '../../../../features/settings/presentation/pages/printer_settings_screen.dart';
import '../../data/models/order_model.dart';
import '../../data/models/order_item_model.dart';
import '../providers/pos_provider.dart';

class ReceiptScreen extends StatefulWidget {
  final OrderModel? order;
  final List<OrderItemModel>? items;

  const ReceiptScreen({
    super.key,
    this.order,
    this.items,
  });

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  Map<String, dynamic>? _cafeDetails;
  bool _isLoadingCafe = false;
  bool _printedOnce = false;

  @override
  void initState() {
    super.initState();
    _loadCafeDetails();
  }

  Future<void> _loadCafeDetails() async {
    final posProvider = context.read<PosProvider>();
    final resolvedOrder = widget.order ?? posProvider.lastCompletedOrder;
    if (resolvedOrder == null) return;

    setState(() => _isLoadingCafe = true);
    try {
      final res = await Supabase.instance.client
          .from('cafes')
          .select()
          .eq('id', resolvedOrder.cafeId)
          .maybeSingle();
      if (res != null && mounted) {
        setState(() {
          _cafeDetails = res;
        });
      }
    } catch (e) {
      debugPrint('Error loading cafe details for receipt: $e');
    } finally {
      if (mounted) setState(() => _isLoadingCafe = false);
    }
  }

  void _printReceipt(OrderModel order, List<OrderItemModel> items) async {
    final printerProvider = context.read<PrinterProvider>();
    final counterConfig = printerProvider.counterConfig;
    
    if (counterConfig == null || !counterConfig.isEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Counter Printer is not configured or disabled in Settings.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final cafeName = _cafeDetails?['name'] ?? 'Café OS';
    final panVat = _cafeDetails?['pan_vat_number'] ?? '123456789';

    try {
      await printerProvider.printReceiptRouted(
        order: order,
        items: items,
        cafeName: cafeName,
        panVat: panVat,
        cashierName: order.waiterName ?? order.cashierId ?? 'Cashier',
      );

      setState(() {
        _printedOnce = true;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Receipt sent to Counter Printer successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Receipt printing failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Receipt printing failed: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _shareReceipt(OrderModel order, List<OrderItemModel> items) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Share Receipt'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Share options simulated successfully:'),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.copy, color: AppTheme.primaryColor),
              title: const Text('Copy to Clipboard'),
              onTap: () {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Receipt plain-text copied to clipboard!')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.share, color: Colors.green),
              title: const Text('System Share Sheet'),
              onTap: () {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Sent Bill #${order.billNumber} to System Share Sheet!')),
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final posProvider = context.read<PosProvider>();
    final printerProvider = context.watch<PrinterProvider>();

    final resolvedOrder = widget.order ?? posProvider.lastCompletedOrder;
    final resolvedItems = widget.items ?? posProvider.lastCompletedOrderItems;

    if (resolvedOrder == null || resolvedItems == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Receipt Details')),
        body: const Center(
          child: Text(
            'No order found. Clear checkout and try again.',
            style: TextStyle(fontSize: 18, color: AppTheme.textSecondary),
          ),
        ),
      );
    }

    final counterConfig = printerProvider.counterConfig;
    final isPrinterConnected = counterConfig != null && counterConfig.isEnabled && counterConfig.status == 'Connected';

    // Cafe metadata fallback
    final cafeName = _cafeDetails?['name'] ?? 'Café OS';
    final cafeAddress = _cafeDetails?['address'] ?? 'New Baneshwor, Kathmandu';
    final panVat = _cafeDetails?['pan_vat_number'] ?? '123456789';

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Payment Success & Receipt', style: TextStyle(fontWeight: FontWeight.bold)),
        automaticallyImplyLeading: widget.order != null, // allow back only if viewing from history
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left Side: Beautiful Receipt Preview Card
          Expanded(
            flex: 6,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 450),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Status Success Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle, color: Colors.green.shade600, size: 32),
                          const SizedBox(width: 8),
                          Text(
                            'PAYMENT SUCCESSFUL',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(height: 1, thickness: 1.5, color: Colors.grey),
                      const SizedBox(height: 16),

                      // Café Details
                      if (_isLoadingCafe)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: CircularProgressIndicator(),
                        )
                      else ...[
                        Text(
                          cafeName,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Text(cafeAddress, style: const TextStyle(color: AppTheme.textSecondary), textAlign: TextAlign.center),
                        Text('PAN/VAT: $panVat', style: const TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
                      ],
                      const SizedBox(height: 16),
                      const Divider(height: 1, thickness: 1.5, color: Colors.grey),
                      const SizedBox(height: 16),

                      // Meta details
                      _buildMetaRow('Bill Number:', '#${resolvedOrder.billNumber ?? "N/A"}'),
                      _buildMetaRow('Date / Time:', resolvedOrder.createdAt != null
                          ? resolvedOrder.createdAt!.toLocal().toString().substring(0, 16)
                          : DateTime.now().toString().substring(0, 16)),
                      _buildMetaRow('Cashier:', resolvedOrder.waiterName ?? resolvedOrder.cashierId ?? 'Staff'),
                      _buildMetaRow(
                        'Type:',
                        '${resolvedOrder.type.toUpperCase()} ${resolvedOrder.tableName != null ? "(${resolvedOrder.tableName})" : ""}',
                      ),
                      _buildMetaRow('Payment Method:', resolvedOrder.paymentMethod?.toUpperCase() ?? 'CASH'),
                      const SizedBox(height: 16),
                      const Divider(height: 1, thickness: 1.5, color: Colors.grey),
                      const SizedBox(height: 16),

                      // Items list
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('ITEMS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textSecondary)),
                      ),
                      const SizedBox(height: 8),
                      ...resolvedItems.map((item) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${item.productName}  x${item.quantity}',
                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                                    ),
                                  ),
                                  Text(
                                    'Rs. ${item.totalPrice.toStringAsFixed(2)}',
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              if (item.notes != null && item.notes!.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(left: 12.0, top: 2.0),
                                  child: Text(
                                    '* Note: ${item.notes}',
                                    style: const TextStyle(fontSize: 12, color: Colors.orange, fontStyle: FontStyle.italic),
                                  ),
                                ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 16),
                      const Divider(height: 1, thickness: 1.5, color: Colors.grey),
                      const SizedBox(height: 16),

                      // Summary Breakups
                      _buildSummaryRow('Subtotal:', resolvedOrder.subtotal),
                      if (resolvedOrder.discount > 0)
                        _buildSummaryRow('Discount:', -resolvedOrder.discount, isDiscount: true),
                      _buildSummaryRow('VAT (13%):', resolvedOrder.taxAmount),
                      if (resolvedOrder.serviceCharge > 0)
                        _buildSummaryRow('Service Charge:', resolvedOrder.serviceCharge),
                      const Divider(height: 1, thickness: 1.5, color: Colors.grey),
                      const SizedBox(height: 12),
                      _buildSummaryRow('Grand Total:', resolvedOrder.grandTotal, isBold: true, size: 20),
                      
                      const SizedBox(height: 24),
                      const Text(
                        'Thank you! Please visit again.',
                        style: TextStyle(fontStyle: FontStyle.italic, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Right Side: Quick Action & Connection Details Panel
          Expanded(
            flex: 4,
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(left: BorderSide(color: Colors.grey.shade200, width: 1.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Receipt Operations', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text(
                    'Manage printouts, sharing, and navigation for this finalized checkout session.',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 32),

                  // Connection status banner
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isPrinterConnected ? Colors.green.shade50 : (counterConfig == null || !counterConfig.isEnabled ? Colors.grey.shade50 : Colors.red.shade50),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isPrinterConnected ? Colors.green.shade100 : (counterConfig == null || !counterConfig.isEnabled ? Colors.grey.shade300 : Colors.red.shade100),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              isPrinterConnected ? Icons.print : Icons.print_disabled,
                              color: isPrinterConnected ? Colors.green.shade700 : (counterConfig == null || !counterConfig.isEnabled ? Colors.grey : Colors.red.shade700),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isPrinterConnected 
                                  ? 'Counter Printer Connected' 
                                  : (counterConfig == null || !counterConfig.isEnabled ? 'Counter Printer Disabled' : 'Counter Printer Offline'),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isPrinterConnected ? Colors.green.shade800 : (counterConfig == null || !counterConfig.isEnabled ? Colors.grey.shade700 : Colors.red.shade800),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (isPrinterConnected && counterConfig != null)
                          Text(
                            counterConfig.connectionType == PrinterConnectionType.bluetooth
                                ? 'Bluetooth: ${counterConfig.btName ?? "Thermal Printer"}'
                                : counterConfig.connectionType == PrinterConnectionType.wifi
                                    ? 'WiFi: ${counterConfig.ipAddress}:${counterConfig.port}'
                                    : 'USB: ${counterConfig.usbDeviceName ?? "Standard USB"}',
                            style: TextStyle(color: Colors.green.shade900, fontSize: 13),
                          )
                        else ...[
                          Text(
                            counterConfig == null || !counterConfig.isEnabled
                                ? 'Enable and configure the receipt printer from Settings.'
                                : 'Printer connection failed: ${counterConfig.lastError ?? "Disconnected"}',
                            style: TextStyle(
                              color: counterConfig == null || !counterConfig.isEnabled ? AppTheme.textSecondary : Colors.redAccent,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: counterConfig == null || !counterConfig.isEnabled ? AppTheme.primaryColor : Colors.red.shade700,
                              foregroundColor: Colors.white,
                              elevation: 0,
                            ),
                            icon: const Icon(Icons.settings),
                            label: const Text('Go to Printer Settings'),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const PrinterSettingsScreen()),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 48),

                  // Action Buttons List
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.print),
                    label: const Text('Print Receipt', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    onPressed: () => _printReceipt(resolvedOrder, resolvedItems),
                  ),
                  const SizedBox(height: 16),
                  if (_printedOnce) ...[
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(color: AppTheme.primaryColor),
                      ),
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('Reprint Receipt', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      onPressed: () => _printReceipt(resolvedOrder, resolvedItems),
                    ),
                    const SizedBox(height: 16),
                  ],
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    icon: const Icon(Icons.share),
                    label: const Text('Share Receipt', style: TextStyle(fontSize: 16)),
                    onPressed: () => _shareReceipt(resolvedOrder, resolvedItems),
                  ),
                  const Spacer(),

                  // Bottom Button: Return to POS/History
                  AppButton(
                    text: widget.order != null ? 'Close' : 'New Order',
                    onPressed: () {
                      if (widget.order != null) {
                        Navigator.pop(context); // Close view details
                      } else {
                        posProvider.clearCart();
                        Navigator.pop(context); // Pop back to POS table grid
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, double amount, {bool isBold = false, double size = 14, bool isDiscount = false}) {
    final style = TextStyle(
      fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
      fontSize: size,
      color: isDiscount ? Colors.red : AppTheme.textPrimary,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text('Rs. ${amount.toStringAsFixed(2)}', style: style),
        ],
      ),
    );
  }
}
