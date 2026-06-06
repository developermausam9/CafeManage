import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/presentation/theme/app_theme.dart';
import '../providers/analytics_provider.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Detailed Reports'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download),
            tooltip: 'Export CSV (Coming Soon)',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('CSV Export coming soon!')));
            },
          )
        ],
      ),
      body: Consumer<AnalyticsProvider>(
        builder: (context, provider, child) {
          if (provider.state == AnalyticsState.loading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.state == AnalyticsState.error) {
            return Center(child: Text(provider.errorMessage ?? 'Error loading reports'));
          }

          // Use the raw data from the provider to build a table
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              // Offline banner
              if (provider.isUsingCachedData)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(provider.isCacheEmpty ? Icons.wifi_off : Icons.history,
                          size: 16, color: Colors.amber.shade800),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          provider.isCacheEmpty
                              ? 'No offline data yet — connect once to cache reports.'
                              : 'Showing cached offline report data.',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.amber.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              _buildReportSection('Sales by Payment Method', _buildPaymentTable(provider)),
              const SizedBox(height: 32),
              _buildReportSection('Top Selling Products', _buildProductsTable(provider)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildReportSection(String title, Widget table) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.05),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
          ),
          table,
        ],
      ),
    );
  }

  Widget _buildPaymentTable(AnalyticsProvider provider) {
    final data = provider.salesByPaymentMethod;
    if (data.isEmpty) return const Padding(padding: EdgeInsets.all(16), child: Text('No data available.'));

    return DataTable(
      columns: const [
        DataColumn(label: Text('Payment Method', style: TextStyle(fontWeight: FontWeight.bold))),
        DataColumn(label: Text('Total Revenue', style: TextStyle(fontWeight: FontWeight.bold))),
      ],
      rows: data.entries.map((entry) {
        return DataRow(
          cells: [
            DataCell(Text(entry.key)),
            DataCell(Text('Rs. ${entry.value.toStringAsFixed(2)}')),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildProductsTable(AnalyticsProvider provider) {
    final data = provider.topProducts;
    if (data.isEmpty) return const Padding(padding: EdgeInsets.all(16), child: Text('No data available.'));

    // Sort by quantity descending
    final sortedEntries = data.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top10 = sortedEntries.take(10).toList();

    return DataTable(
      columns: const [
        DataColumn(label: Text('Product ID', style: TextStyle(fontWeight: FontWeight.bold))),
        DataColumn(label: Text('Quantity Sold', style: TextStyle(fontWeight: FontWeight.bold))),
      ],
      rows: top10.map((entry) {
        return DataRow(
          cells: [
            DataCell(Text(entry.key.substring(0, 8) + '...')), // In real app, join with product name
            DataCell(Text('${entry.value}')),
          ],
        );
      }).toList(),
    );
  }
}
