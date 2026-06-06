import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../../core/presentation/theme/app_theme.dart';
import '../../../../core/presentation/widgets/stat_card.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../presentation/providers/analytics_provider.dart';
import '../../../operations/presentation/providers/operations_provider.dart';

class AnalyticsDashboardScreen extends StatefulWidget {
  const AnalyticsDashboardScreen({super.key});

  @override
  State<AnalyticsDashboardScreen> createState() => _AnalyticsDashboardScreenState();
}

class _AnalyticsDashboardScreenState extends State<AnalyticsDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cafeId = context.read<AuthProvider>().cafeId;
      if (cafeId != null) {
        context.read<AnalyticsProvider>().init(cafeId);
        context.read<OperationsProvider>().init(cafeId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Consumer<AnalyticsProvider>(
        builder: (context, provider, child) {
          if (provider.state == AnalyticsState.loading && provider.totalSales == 0) {
            return const Center(child: CircularProgressIndicator());
          }

          // Hard error only if we have no cached data at all
          if (provider.state == AnalyticsState.error) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.wifi_off, size: 48, color: Colors.orange),
                  const SizedBox(height: 16),
                  const Text(
                    'No offline data available yet.',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Connect to the internet once to sync your data.',
                    style: TextStyle(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () {
                      final cafeId = context.read<AuthProvider>().cafeId;
                      if (cafeId != null) provider.init(cafeId);
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final size = MediaQuery.of(context).size;
          final isDesktop = size.width > 950;
          final isMobile = size.width <= 600;

          return RefreshIndicator(
            onRefresh: () async {
              final cafeId = context.read<AuthProvider>().cafeId;
              if (cafeId != null) {
                await provider.fetchData();
                await context.read<OperationsProvider>().fetchAll();
              }
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Offline cache banner
                  if (provider.isUsingCachedData) ...[
                    _buildOfflineBanner(provider.isCacheEmpty),
                    const SizedBox(height: 16),
                  ],
                  _buildHeader(provider, isMobile),
                  const SizedBox(height: 24),
                  // If offline AND cache empty, show full empty-state
                  if (provider.isUsingCachedData && provider.isCacheEmpty)
                    _buildEmptyOfflineState()
                  else ...[
                    _buildStatGrid(provider, size),
                    const SizedBox(height: 24),
                    if (isDesktop)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 2, child: _buildResponsiveBarChart(provider, isMobile)),
                          const SizedBox(width: 24),
                          Expanded(flex: 1, child: _buildPieChart(provider)),
                        ],
                      )
                    else
                      Column(
                        children: [
                          _buildResponsiveBarChart(provider, isMobile),
                          const SizedBox(height: 24),
                          _buildPieChart(provider),
                        ],
                      ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Amber banner shown when displaying cached offline data.
  Widget _buildOfflineBanner(bool isEmpty) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isEmpty ? Colors.orange.shade50 : Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isEmpty ? Colors.orange.shade200 : Colors.amber.shade300,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isEmpty ? Icons.wifi_off : Icons.history,
            size: 18,
            color: isEmpty ? Colors.orange.shade700 : Colors.amber.shade800,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isEmpty
                  ? 'No offline data available yet. Connect to the internet once to sync.'
                  : 'Showing cached offline data — pull down to refresh when online.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isEmpty ? Colors.orange.shade800 : Colors.amber.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Full-page empty state for when we are offline and have no cache at all.
  Widget _buildEmptyOfflineState() {
    return SizedBox(
      height: 340,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 72, color: Colors.orange.shade200),
            const SizedBox(height: 20),
            const Text(
              'No offline data available yet.',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Connect to the internet once to cache your analytics.',
              style: TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildHeader(AnalyticsProvider provider, bool isMobile) {
    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Overview', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'Today', label: Text('Today')),
                ButtonSegment(value: 'Weekly', label: Text('Weekly')),
                ButtonSegment(value: 'Monthly', label: Text('Monthly')),
              ],
              selected: {provider.timeFilter},
              onSelectionChanged: (set) => provider.setFilter(set.first),
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text('Overview', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'Today', label: Text('Today')),
            ButtonSegment(value: 'Weekly', label: Text('Weekly')),
            ButtonSegment(value: 'Monthly', label: Text('Monthly')),
          ],
          selected: {provider.timeFilter},
          onSelectionChanged: (set) => provider.setFilter(set.first),
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );
  }

  Widget _buildStatGrid(AnalyticsProvider provider, Size size) {
    return Consumer<OperationsProvider>(
      builder: (context, ops, child) {
        final start = provider.startDate ?? DateTime.now().subtract(const Duration(days: 1));
        final end = provider.endDate ?? DateTime.now();

        // 1. Total Expenses in selected range only
        final filteredExpenses = ops.expenses.where((e) {
          return (e.date.isAfter(start) || e.date.isAtSameMomentAs(start)) &&
                 (e.date.isBefore(end) || e.date.isAtSameMomentAs(end));
        }).toList();
        final double totalExpenses = filteredExpenses.fold(0.0, (sum, item) => sum + item.amount);

        // 2. Outstanding Customer Dues (remaining unpaid balance overall)
        final double outstandingCustomerDue = ops.totalCustomerDue;

        // 3. Outstanding Supplier Payables overall
        final double outstandingSupplierPayable = ops.totalSupplierPayable;

        // Revenue calculations
        final double collectedRev = provider.collectedRevenue;
        final double creditSalesVal = provider.dueRevenue; // Credit sales (uncollected remaining dues in period)
        final double totalCogsVal = provider.totalCogs;
        final double netProfit = collectedRev - totalCogsVal - totalExpenses;
        final int completedOrdersCount = provider.completedOrders.length;

        // Determine available grid width (subtracting sidebar if desktop)
        final double gridWidth = size.width - 48 - (size.width > 800 ? 250 : 0);

        // Dynamically compute cross-axis count so each card has a premium minimum width of 220 logical pixels
        int crossAxisCount = (gridWidth / 220.0).floor().clamp(1, 4);

        // Dynamically compute the aspect ratio to guarantee a minimum height of 90 logical pixels and prevent overflows
        final double cardWidth = (gridWidth - (16 * (crossAxisCount - 1))) / crossAxisCount;
        double aspect = 2.2;
        final double heightWithDefaultAspect = cardWidth / aspect;
        if (heightWithDefaultAspect < 90.0) {
          aspect = cardWidth / 90.0;
        }

        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: aspect,
          children: [
            StatCard(
              title: 'Collected Revenue',
              value: 'Rs. ${collectedRev.toStringAsFixed(0)}',
              icon: Icons.payments,
              iconColor: Colors.green,
              tooltip: 'Collected Revenue = Cash + QR + Card payments + Dues paid in this period',
            ),
            StatCard(
              title: 'Credit Sales',
              value: 'Rs. ${creditSalesVal.toStringAsFixed(0)}',
              icon: Icons.assignment_late,
              iconColor: Colors.orange,
              tooltip: 'Credit Sales = Total unpaid remaining due of due orders created in this period',
            ),
            StatCard(
              title: 'Cost of Goods Sold',
              value: 'Rs. ${totalCogsVal.toStringAsFixed(0)}',
              icon: Icons.inventory,
              iconColor: Colors.brown,
              tooltip: 'COGS = Sum of (sold quantity × product cost price) scaled by payment collected ratio',
            ),
            StatCard(
              title: 'Total Expenses',
              value: 'Rs. ${totalExpenses.toStringAsFixed(0)}',
              icon: Icons.money_off,
              iconColor: Colors.red,
              tooltip: 'Total Expenses = Sum of all expenses within this period',
            ),
            StatCard(
              title: 'Net Profit',
              value: 'Rs. ${netProfit.toStringAsFixed(0)}',
              icon: Icons.trending_up,
              iconColor: Colors.blue,
              tooltip: 'Net Profit = Collected Revenue - COGS - Expenses',
            ),
            StatCard(
              title: 'Completed Orders',
              value: '$completedOrdersCount',
              icon: Icons.check_circle,
              iconColor: Colors.teal,
              tooltip: 'Completed Orders = Count of completed orders in this period',
            ),
            StatCard(
              title: 'Customer Dues',
              value: 'Rs. ${outstandingCustomerDue.toStringAsFixed(0)}',
              icon: Icons.warning_amber,
              iconColor: Colors.amber,
              tooltip: 'Customer Dues = Total outstanding unpaid customer balances',
            ),
            StatCard(
              title: 'Supplier Payable',
              value: 'Rs. ${outstandingSupplierPayable.toStringAsFixed(0)}',
              icon: Icons.local_shipping,
              iconColor: Colors.purple,
              tooltip: 'Supplier Payables = Total outstanding unpaid supplier invoices',
            ),
          ],
        );
      },
    );
  }

  Widget _buildResponsiveBarChart(AnalyticsProvider provider, bool isMobile) {
    final data = provider.groupedRevenueData;
    if (data.isEmpty) {
      return Container(
        height: 380,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: const Text('No revenue data recorded', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.bold)),
      );
    }

    double maxVal = 0.0;
    for (var d in data) {
      if (d.value > maxVal) maxVal = d.value;
    }
    if (maxVal == 0) maxVal = 1000.0;

    final List<BarChartGroupData> barGroups = [];
    for (int i = 0; i < data.length; i++) {
      final item = data[i];
      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: item.value,
              color: AppTheme.primaryColor,
              width: isMobile ? 8 : 14,
              borderRadius: BorderRadius.circular(4),
              backDrawRodData: BackgroundBarChartRodData(
                show: true,
                toY: maxVal * 1.1,
                color: Colors.grey.shade100,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      height: 385,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.01),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Revenue Trend', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  provider.timeFilter,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxVal * 1.2,
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => AppTheme.primaryColor,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final label = data[group.x].label;
                      return BarTooltipItem(
                        '$label\nRs. ${rod.toY.toStringAsFixed(0)}',
                        const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= data.length) return const SizedBox.shrink();
                        
                        final label = data[index].label;
                        if (provider.timeFilter == 'Today') {
                          final show = isMobile ? (index % 3 == 0) : (index % 2 == 0);
                          if (!show) return const SizedBox.shrink();
                        }
                        
                        return SideTitleWidget(
                          axisSide: meta.axisSide,
                          space: 4,
                          child: Text(
                            label,
                            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 42,
                      getTitlesWidget: (value, meta) {
                        if (value == 0) return const SizedBox.shrink();
                        String label = 'Rs. ${value.toStringAsFixed(0)}';
                        if (value >= 1000) {
                          label = 'Rs. ${(value / 1000).toStringAsFixed(1)}k';
                        }
                        return SideTitleWidget(
                          axisSide: meta.axisSide,
                          space: 4,
                          child: Text(
                            label,
                            style: const TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.w600),
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.grey.shade100,
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: barGroups,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildSummaryIndicator(
                'Total Collected',
                'Rs. ${provider.collectedRevenue.toStringAsFixed(0)}',
                Icons.account_balance_wallet,
              ),
              _buildSummaryIndicator(
                'Best Sales ${provider.timeFilter == 'Today' ? 'Hour' : 'Day'}',
                provider.bestSalesHourOrDay,
                Icons.star,
              ),
              _buildSummaryIndicator(
                'Avg Order Value',
                'Rs. ${provider.averageOrderValue.toStringAsFixed(0)}',
                Icons.analytics,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryIndicator(String label, String value, IconData icon) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppTheme.primaryColor.withOpacity(0.6)),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildPieChart(AnalyticsProvider provider) {
    final paymentData = provider.salesByPaymentMethod;
    if (paymentData.isEmpty) return const SizedBox.shrink();

    final colors = [Colors.blue, Colors.green, Colors.orange, Colors.red];
    int colorIndex = 0;

    final sections = paymentData.entries.map((entry) {
      final color = colors[colorIndex % colors.length];
      colorIndex++;
      return PieChartSectionData(
        color: color,
        value: entry.value,
        title: entry.key,
        radius: 60,
        titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
      );
    }).toList();

    return Container(
      height: 385,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Payment Methods', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              if (provider.orders.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(left: 8.0),
                  child: Text('(Interactive Demo)', style: TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 40,
                sections: sections,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
