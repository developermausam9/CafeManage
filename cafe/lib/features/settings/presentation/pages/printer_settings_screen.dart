import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import '../../../../core/presentation/providers/printer_provider.dart';
import '../../../../core/presentation/theme/app_theme.dart';
import '../../../../core/services/models/printer_config_model.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart' as bt;

class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Counter inputs
  final _counterIpController = TextEditingController();
  final _counterPortController = TextEditingController();
  
  // Kitchen inputs
  final _kitchenIpController = TextEditingController();
  final _kitchenPortController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    
    // Initialize input controllers with saved config values
    final provider = context.read<PrinterProvider>();
    _counterIpController.text = provider.counterConfig?.ipAddress ?? '';
    _counterPortController.text = (provider.counterConfig?.port ?? 9100).toString();
    _kitchenIpController.text = provider.kitchenConfig?.ipAddress ?? '';
    _kitchenPortController.text = (provider.kitchenConfig?.port ?? 9100).toString();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _counterIpController.dispose();
    _counterPortController.dispose();
    _kitchenIpController.dispose();
    _kitchenPortController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        appBar: AppBar(
          title: const Text('Printer Settings', style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.white,
          elevation: 0,
        ),
        body: const Center(
          child: Text(
            'Printing configurations are managed on standard mobile/tablet clients.',
            style: TextStyle(fontSize: 18, color: AppTheme.textSecondary),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Advanced Printing Dashboard', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        backgroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primaryColor,
          unselectedLabelColor: AppTheme.textSecondary,
          indicatorColor: AppTheme.primaryColor,
          indicatorWeight: 3,
          tabs: const [
            Tab(icon: Icon(Icons.receipt_long), text: 'Counter Receipt Printer'),
            Tab(icon: Icon(Icons.restaurant_menu), text: 'Kitchen KOT Printer'),
          ],
        ),
      ),
      body: Consumer<PrinterProvider>(
        builder: (context, provider, child) {
          final counter = provider.counterConfig;
          final kitchen = provider.kitchenConfig;

          if (counter == null || kitchen == null) {
            return const Center(child: CircularProgressIndicator());
          }

          return TabBarView(
            controller: _tabController,
            children: [
              _buildPrinterConfigPane(
                config: counter,
                provider: provider,
                ipController: _counterIpController,
                portController: _counterPortController,
              ),
              _buildPrinterConfigPane(
                config: kitchen,
                provider: provider,
                ipController: _kitchenIpController,
                portController: _kitchenPortController,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPrinterConfigPane({
    required PrinterConfig config,
    required PrinterProvider provider,
    required TextEditingController ipController,
    required TextEditingController portController,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Live Diagnostic Card
          _buildDiagnosticCard(config, provider),
          const SizedBox(height: 16),

          // Job Routing Card
          _buildJobRoutingCard(config),
          const SizedBox(height: 16),

          // 2. Main Config Card
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 0,
            borderOnForeground: true,
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Configuration Settings',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                      ),
                      Row(
                        children: [
                          const Text('Enabled', style: TextStyle(fontWeight: FontWeight.w600)),
                          Switch(
                            value: config.isEnabled,
                            activeColor: AppTheme.primaryColor,
                            onChanged: (val) {
                              final updated = config.copyWith(isEnabled: val);
                              provider.savePrinterConfig(updated);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Divider(height: 32),

                  // Connection Type Selector
                  const Text('Connection Interface', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 12),
                  _buildConnectionSelector(config, provider),
                  const SizedBox(height: 24),

                  // Paper Width Selector
                  const Text('Paper Size Width', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 12),
                  _buildPaperSizeSelector(config, provider),
                  const Divider(height: 48),

                  // Active connection fields
                  if (config.connectionType == PrinterConnectionType.bluetooth)
                    _buildBluetoothFields(config, provider)
                  else if (config.connectionType == PrinterConnectionType.wifi)
                    _buildWifiFields(config, provider, ipController, portController)
                  else if (config.connectionType == PrinterConnectionType.usb)
                    _buildUsbFields(config, provider),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosticCard(PrinterConfig config, PrinterProvider provider) {
    Color statusColor;
    IconData statusIcon;

    switch (config.status) {
      case 'Connected':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'Connecting...':
      case 'Printing...':
        statusColor = Colors.orange;
        statusIcon = Icons.hourglass_top;
        break;
      case 'Error':
        statusColor = Colors.redAccent;
        statusIcon = Icons.error;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.offline_share;
    }

    String connectionTarget = '';
    switch (config.connectionType) {
      case PrinterConnectionType.wifi:
        connectionTarget = '${config.ipAddress ?? "Not Configured"}:${config.port}';
        break;
      case PrinterConnectionType.bluetooth:
        connectionTarget = config.btName != null ? '${config.btName} (${config.btAddress})' : 'Not Paired';
        break;
      case PrinterConnectionType.usb:
        connectionTarget = config.usbDeviceName ?? 'Standard POS USB Printer 1';
        break;
    }

    return Container(
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withOpacity(0.3), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(statusIcon, color: statusColor, size: 28),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              config.name,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  config.status.toUpperCase(),
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: statusColor),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.sync),
                      color: statusColor,
                      onPressed: () => provider.verifyConnection(config),
                      tooltip: 'Check Connection',
                    ),
                  ],
                ),
                
                const Divider(height: 32, thickness: 0.5),
                
                // Diagnostics and System Info Section
                const Row(
                  children: [
                    Icon(Icons.analytics_outlined, size: 16, color: AppTheme.textSecondary),
                    const SizedBox(width: 6),
                    Text(
                      'DIAGNOSTICS & SYSTEM INFO',
                      style: TextStyle(
                        fontSize: 12, 
                        fontWeight: FontWeight.bold, 
                        color: AppTheme.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                _buildDiagnosticRow('Printer Target Name', config.name),
                _buildDiagnosticRow('Connection Interface', config.connectionType.toString().split('.').last.toUpperCase()),
                _buildDiagnosticRow('Diagnostics Address', connectionTarget),
                _buildDiagnosticRow('Paper Width Size', config.paperSize),
                _buildDiagnosticRow(
                  'Last Online Sync', 
                  config.lastPrintTime != null 
                      ? '${config.lastPrintTime!.toLocal().toString().substring(11, 16)} (${config.lastPrintTime!.toLocal().toString().substring(0, 10)})' 
                      : 'Never Printed'
                ),
                
                if (config.lastError != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade100),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber, size: 16, color: Colors.red.shade800),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Active Error: ${config.lastError}',
                            style: TextStyle(color: Colors.red.shade800, fontSize: 12, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosticRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
        ],
      ),
    );
  }

  Widget _buildJobRoutingCard(PrinterConfig config) {
    final isCounter = config.name.contains('Counter');
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      color: AppTheme.primaryColor.withOpacity(0.02),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.route, color: AppTheme.primaryColor, size: 22),
                const SizedBox(width: 8),
                const Text(
                  'Smart Job Routing Configuration',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.primaryColor),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isCounter ? Colors.teal.shade50 : Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isCounter ? 'COUNTER RECEIPT' : 'KITCHEN KOT',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      color: isCounter ? Colors.teal.shade700 : Colors.indigo.shade700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isCounter 
                        ? 'Automatically routes all customer billing receipts, reprints, and tax invoices here.'
                        : 'Automatically routes all active kitchen tickets, item additions, and cancellations here.',
                    style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionSelector(PrinterConfig config, PrinterProvider provider) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _buildSelectorButton(
            label: 'Bluetooth',
            icon: Icons.bluetooth,
            isSelected: config.connectionType == PrinterConnectionType.bluetooth,
            onTap: () {
              final updated = config.copyWith(connectionType: PrinterConnectionType.bluetooth);
              provider.savePrinterConfig(updated);
            },
          ),
          _buildSelectorButton(
            label: 'WiFi / LAN',
            icon: Icons.wifi,
            isSelected: config.connectionType == PrinterConnectionType.wifi,
            onTap: () {
              final updated = config.copyWith(connectionType: PrinterConnectionType.wifi);
              provider.savePrinterConfig(updated);
            },
          ),
          _buildSelectorButton(
            label: 'USB Connection',
            icon: Icons.usb,
            isSelected: config.connectionType == PrinterConnectionType.usb,
            onTap: () {
              final updated = config.copyWith(connectionType: PrinterConnectionType.usb);
              provider.savePrinterConfig(updated);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSelectorButton({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))]
                : null,
          ),
          child: Column(
            children: [
              Icon(icon, color: isSelected ? AppTheme.primaryColor : AppTheme.textSecondary, size: 20),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? AppTheme.primaryColor : AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaperSizeSelector(PrinterConfig config, PrinterProvider provider) {
    return Row(
      children: [
        _buildSegmentedWidthButton(
          label: '58mm Standard',
          subtitle: 'KOTs & small bills',
          isSelected: config.paperSize == '58mm',
          onTap: () {
            final updated = config.copyWith(paperSize: '58mm');
            provider.savePrinterConfig(updated);
          },
        ),
        const SizedBox(width: 16),
        _buildSegmentedWidthButton(
          label: '80mm Thermal',
          subtitle: 'Large cashier bills',
          isSelected: config.paperSize == '80mm',
          onTap: () {
            final updated = config.copyWith(paperSize: '80mm');
            provider.savePrinterConfig(updated);
          },
        ),
      ],
    );
  }

  Widget _buildSegmentedWidthButton({
    required String label,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryColor.withOpacity(0.05) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppTheme.primaryColor : Colors.grey.shade300,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBluetoothFields(PrinterConfig config, PrinterProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Paired Devices', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => provider.scanDevices(),
              tooltip: 'Scan Devices',
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (provider.devices.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
            child: const Text(
              'No paired bluetooth devices found. Ensure device bluetooth is enabled and paired inside Android Settings.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: config.btAddress,
                hint: const Text('Select a Bluetooth Printer'),
                isExpanded: true,
                items: provider.devices.map((device) {
                  return DropdownMenuItem<String>(
                    value: device.address,
                    child: Text('${device.name} (${device.address})'),
                  );
                }).toList(),
                onChanged: (address) {
                  if (address != null) {
                    final selected = provider.devices.firstWhere((d) => d.address == address);
                    final updated = config.copyWith(
                      btAddress: selected.address,
                      btName: selected.name,
                    );
                    provider.savePrinterConfig(updated);
                  }
                },
              ),
            ),
          ),
        const SizedBox(height: 24),
        _buildActionButtons(config, provider),
      ],
    );
  }

  Widget _buildWifiFields(
    PrinterConfig config,
    PrinterProvider provider,
    TextEditingController ipController,
    TextEditingController portController,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Network IP Configuration', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: ipController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'IP Address',
                  hintText: 'e.g. 192.168.1.100',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.computer),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 1,
              child: TextField(
                controller: portController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Port',
                  hintText: '9100',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.save),
                label: const Text('Save Network Configuration', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () {
                  final ip = ipController.text.trim();
                  final port = int.tryParse(portController.text.trim()) ?? 9100;
                  
                  if (ip.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('IP Address cannot be empty'), backgroundColor: Colors.redAccent),
                    );
                    return;
                  }

                  final updated = config.copyWith(ipAddress: ip, port: port);
                  provider.savePrinterConfig(updated);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Printer network settings saved successfully'), backgroundColor: Colors.green),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildActionButtons(config, provider),
      ],
    );
  }

  Widget _buildUsbFields(PrinterConfig config, PrinterProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('USB Configuration', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.usb, color: Colors.green),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Detected Device: ${config.usbDeviceName ?? "Standard POS USB Printer 1"}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'USB printing utilizes device platform channels. The service will target root device interfaces.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _buildActionButtons(config, provider),
      ],
    );
  }

  Widget _buildActionButtons(PrinterConfig config, PrinterProvider provider) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor.withOpacity(0.1),
              foregroundColor: AppTheme.primaryColor,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            icon: const Icon(Icons.network_check),
            label: const Text('Test Connection', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () async {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Verifying connection to ${config.name}...')),
              );
              await provider.verifyConnection(config);
              if (config.lastError != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Connection failed: ${config.lastError}'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Connected successfully! Status: ${config.status}'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.print),
            label: const Text('Send Test Print', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () async {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Sending test print to ${config.name}...')),
              );
              await provider.testPrint(config);
              if (config.lastError != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Test print failed: ${config.lastError}'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Test print completed successfully!'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
          ),
        ),
      ],
    );
  }
}
