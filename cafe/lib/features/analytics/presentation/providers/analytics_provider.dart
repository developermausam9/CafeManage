import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../domain/usecases/get_dashboard_data_usecase.dart';
import '../../../orders/data/models/order_model.dart';
import '../../../orders/data/models/order_item_model.dart';

enum AnalyticsState { initial, loading, loaded, error }

class BarChartGroupCustom {
  final String label;
  final double value;
  BarChartGroupCustom(this.label, this.value);
}

class AnalyticsProvider extends ChangeNotifier {
  final GetDashboardDataUseCase getDashboardDataUseCase;

  AnalyticsState _state = AnalyticsState.initial;
  AnalyticsState get state => _state;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  // Offline cache flags
  bool _isUsingCachedData = false;
  bool _isCacheEmpty = false;
  bool get isUsingCachedData => _isUsingCachedData;
  bool get isCacheEmpty => _isCacheEmpty;

  String _timeFilter = 'Today'; // Today, Weekly, Monthly
  String get timeFilter => _timeFilter;

  DateTime? _startDate;
  DateTime? _endDate;
  DateTime? get startDate => _startDate;
  DateTime? get endDate => _endDate;

  // Raw Data
  List<OrderModel> _orders = [];
  List<OrderItemModel> _items = [];
  Map<String, double> _productCostPrices = {};
  List<Map<String, dynamic>> _duePayments = [];

  List<OrderModel> get orders => List.unmodifiable(_orders);
  List<OrderItemModel> get items => List.unmodifiable(_items);
  Map<String, double> get productCostPrices => Map.unmodifiable(_productCostPrices);
  List<Map<String, dynamic>> get duePayments => List.unmodifiable(_duePayments);

  // Audited Orders
  List<OrderModel> get completedOrders => _orders
      .where((o) => (o.status == 'completed' || o.status == 'paid') &&
                     o.status != 'cancelled' &&
                     o.status != 'voided' &&
                     o.status != 'refunded')
      .toList();

  // Collected Revenue = Cash + QR + Card + Due payments received in period
  double get collectedRevenue {
    final cashQrCard = completedOrders
        .where((o) => o.paymentMethod == 'cash' || o.paymentMethod == 'qr' || o.paymentMethod == 'card')
        .fold(0.0, (sum, o) => sum + o.grandTotal);
        
    final duePaid = _duePayments.fold(0.0, (sum, dp) => sum + (dp['amount_paid'] as num).toDouble());
    
    return cashQrCard + duePaid;
  }

  // Credit Sales = new Due orders not yet collected (remaining_due)
  double get dueRevenue => completedOrders
      .where((o) => o.paymentMethod == 'due')
      .fold(0.0, (sum, o) => sum + o.remainingDue);

  // Total Sales = Paid sales + Credit sales
  double get paidSales => completedOrders
      .where((o) => o.paymentMethod == 'cash' || o.paymentMethod == 'qr' || o.paymentMethod == 'card')
      .fold(0.0, (sum, o) => sum + o.grandTotal);

  double get creditSales => completedOrders
      .where((o) => o.paymentMethod == 'due')
      .fold(0.0, (sum, o) => sum + o.grandTotal);

  double get totalSales => paidSales + creditSales;

  int get totalOrders => completedOrders.length;
  double get averageOrderValue => totalOrders > 0 ? totalSales / totalOrders : 0;

  // Cost of Goods Sold (COGS) for paid/collected sales (scaled proportionally for due orders)
  double get totalCogs {
    double sum = 0.0;
    for (var item in _items) {
      final order = _orders.firstWhere(
        (o) => o.id == item.orderId,
        orElse: () => const OrderModel(id: '', cafeId: '', type: '', status: ''),
      );
      if (order.status == 'completed') {
        final costPrice = _productCostPrices[item.productId ?? ''] ?? 0.0;
        final itemCogs = item.quantity * costPrice;
        
        if (order.paymentMethod == 'due') {
          // Scale COGS by the paid ratio
          final ratio = order.grandTotal > 0 ? (order.paidAmount / order.grandTotal) : 0.0;
          sum += itemCogs * ratio;
        } else {
          sum += itemCogs;
        }
      }
    }
    return sum;
  }

  double get totalProfit => collectedRevenue - totalCogs;

  // Chart Data: group completed orders only by payment method (for Pie Chart)
  Map<String, double> get salesByPaymentMethod {
    final Map<String, double> map = {
      'Cash': 0.0,
      'QR': 0.0,
      'Card': 0.0,
      'Due': 0.0,
    };
    for (var o in completedOrders) {
      final method = o.paymentMethod?.toLowerCase() ?? 'cash';
      String displayName = 'Cash';
      if (method == 'qr') {
        displayName = 'QR';
      } else if (method == 'card') {
        displayName = 'Card';
      } else if (method == 'due') {
        displayName = 'Due';
      }
      map[displayName] = (map[displayName] ?? 0.0) + o.grandTotal;
    }
    // Remove 0.0 entries to keep pie chart clean
    map.removeWhere((key, value) => value == 0.0);
    return map;
  }

  Map<String, int> get topProducts {
    final Map<String, int> map = {};
    for (var item in _items) {
      final order = _orders.firstWhere(
        (o) => o.id == item.orderId,
        orElse: () => const OrderModel(id: '', cafeId: '', type: '', status: ''),
      );
      if (order.status == 'completed') {
        final productName = item.productName;
        map[productName] = (map[productName] ?? 0) + item.quantity.toInt();
      }
    }
    return map;
  }

  // Grouped Revenue Bar Chart data matching the selected filter
  List<BarChartGroupCustom> get groupedRevenueData {
    if (_timeFilter == 'Today') {
      // Group by hours (e.g. 8 AM to 10 PM)
      final Map<int, double> hourlyMap = {};
      
      // Populate completed cash/qr/card orders
      for (var o in completedOrders) {
        if (o.paymentMethod != 'due') {
          final hr = (o.createdAt ?? DateTime.now()).toLocal().hour;
          hourlyMap[hr] = (hourlyMap[hr] ?? 0.0) + o.grandTotal;
        }
      }
      // Populate due payments received
      for (var dp in _duePayments) {
        final dateStr = dp['payment_date'] as String?;
        if (dateStr != null) {
          final hr = DateTime.parse(dateStr).toLocal().hour;
          hourlyMap[hr] = (hourlyMap[hr] ?? 0.0) + (dp['amount_paid'] as num).toDouble();
        }
      }

      // Convert to list of groups (only standard business hours 8 to 22, or whatever hours have sales)
      final List<BarChartGroupCustom> list = [];
      final startHr = 8;
      final endHr = 22;
      for (int h = startHr; h <= endHr; h++) {
        final val = hourlyMap[h] ?? 0.0;
        final label = h == 12 ? '12 PM' : (h > 12 ? '${h - 12} PM' : '$h AM');
        list.add(BarChartGroupCustom(label, val));
      }
      
      return list;
    } else if (_timeFilter == 'Weekly') {
      // Last 7 days
      final List<DateTime> dates = [];
      final now = DateTime.now();
      for (int i = 6; i >= 0; i--) {
        dates.add(DateTime(now.year, now.month, now.day).subtract(Duration(days: i)));
      }

      final Map<String, double> dailyMap = {};
      final weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

      for (var d in dates) {
        final key = '${d.year}-${d.month}-${d.day}';
        dailyMap[key] = 0.0;
      }

      for (var o in completedOrders) {
        if (o.paymentMethod != 'due' && o.createdAt != null) {
          final local = o.createdAt!.toLocal();
          final key = '${local.year}-${local.month}-${local.day}';
          if (dailyMap.containsKey(key)) {
            dailyMap[key] = dailyMap[key]! + o.grandTotal;
          }
        }
      }

      for (var dp in _duePayments) {
        final dateStr = dp['payment_date'] as String?;
        if (dateStr != null) {
          final local = DateTime.parse(dateStr).toLocal();
          final key = '${local.year}-${local.month}-${local.day}';
          if (dailyMap.containsKey(key)) {
            dailyMap[key] = dailyMap[key]! + (dp['amount_paid'] as num).toDouble();
          }
        }
      }

      return dates.map((d) {
        final key = '${d.year}-${d.month}-${d.day}';
        final label = weekdayNames[d.weekday - 1];
        return BarChartGroupCustom(label, dailyMap[key] ?? 0.0);
      }).toList();
    } else {
      // Monthly: Group by week of the month (last 4 weeks)
      final List<BarChartGroupCustom> list = [];
      final now = DateTime.now();
      
      for (int w = 3; w >= 0; w--) {
        final wStart = DateTime(now.year, now.month, now.day).subtract(Duration(days: (w + 1) * 7 - 1));
        final wEnd = DateTime(now.year, now.month, now.day).subtract(Duration(days: w * 7));

        double sum = 0.0;
        for (var o in completedOrders) {
          if (o.paymentMethod != 'due' && o.createdAt != null) {
            final local = o.createdAt!.toLocal();
            if (local.isAfter(wStart.subtract(const Duration(seconds: 1))) && local.isBefore(wEnd.add(const Duration(days: 1)))) {
              sum += o.grandTotal;
            }
          }
        }

        for (var dp in _duePayments) {
          final dateStr = dp['payment_date'] as String?;
          if (dateStr != null) {
            final local = DateTime.parse(dateStr).toLocal();
            if (local.isAfter(wStart.subtract(const Duration(seconds: 1))) && local.isBefore(wEnd.add(const Duration(days: 1)))) {
              sum += (dp['amount_paid'] as num).toDouble();
            }
          }
        }

        final startLabel = '${wStart.day}/${wStart.month}';
        final endLabel = '${wEnd.day}/${wEnd.month}';
        list.add(BarChartGroupCustom('$startLabel-$endLabel', sum));
      }
      return list;
    }
  }

  // Summary Metrics below chart
  String get bestSalesHourOrDay {
    if (_timeFilter == 'Today') {
      final data = groupedRevenueData;
      if (data.isEmpty) return 'N/A';
      var best = data.first;
      for (var d in data) {
        if (d.value > best.value) {
          best = d;
        }
      }
      return best.value > 0 ? best.label : 'N/A';
    } else {
      final data = groupedRevenueData;
      if (data.isEmpty) return 'N/A';
      var best = data.first;
      for (var d in data) {
        if (d.value > best.value) {
          best = d;
        }
      }
      return best.value > 0 ? best.label : 'N/A';
    }
  }

  String? _cafeId;

  AnalyticsProvider({required this.getDashboardDataUseCase});

  void init(String cafeId) {
    _cafeId = cafeId;
    fetchData();
  }

  void setFilter(String filter) {
    _timeFilter = filter;
    fetchData();
  }

  Future<void> fetchDataForRange(String cafeId, DateTime start, DateTime end) async {
    _state = AnalyticsState.loading;
    _isUsingCachedData = false;
    _isCacheEmpty = false;
    notifyListeners();
    _startDate = start;
    _endDate = end;

    final cacheKey = 'dashboard_analytics_${cafeId}_custom_${start.millisecondsSinceEpoch}';
    final cacheBox = Hive.box('cache');

    final result = await getDashboardDataUseCase(
      GetDashboardDataParams(cafeId: cafeId, start: start, end: end),
    );
    result.fold(
      (failure) {
        debugPrint('[AnalyticsProvider] fetchDataForRange failed: ${failure.message}. Trying cache...');
        _loadFromCache(cacheBox, cacheKey);
      },
      (data) {
        _orders = List<OrderModel>.from(data['orders']);
        _items = List<OrderItemModel>.from(data['items']);
        _productCostPrices = Map<String, double>.from(data['costPrices'] ?? {});
        _duePayments = List<Map<String, dynamic>>.from(data['duePayments'] ?? []);
        _isUsingCachedData = false;
        _state = AnalyticsState.loaded;
        _saveToCache(cacheBox, cacheKey, data);
      },
    );
    notifyListeners();
  }

  Future<void> fetchData() async {
    if (_cafeId == null) return;
    _state = AnalyticsState.loading;
    _isUsingCachedData = false;
    _isCacheEmpty = false;
    notifyListeners();

    DateTime now = DateTime.now();
    DateTime end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    DateTime start;

    if (_timeFilter == 'Today') {
      start = DateTime(now.year, now.month, now.day, 0, 0, 0, 0);
    } else if (_timeFilter == 'Weekly') {
      final todayStart = DateTime(now.year, now.month, now.day, 0, 0, 0, 0);
      start = todayStart.subtract(const Duration(days: 6));
    } else {
      // Monthly (Last 30 Days)
      final todayStart = DateTime(now.year, now.month, now.day, 0, 0, 0, 0);
      start = todayStart.subtract(const Duration(days: 29));
    }

    _startDate = start;
    _endDate = end;

    final cacheBox = Hive.box('cache');
    final cacheKey = 'dashboard_analytics_${_cafeId}_$_timeFilter';

    final result = await getDashboardDataUseCase(
      GetDashboardDataParams(cafeId: _cafeId!, start: start, end: end),
    );

    result.fold(
      (failure) {
        debugPrint('[AnalyticsProvider] Remote fetch failed: ${failure.message}. Trying cache...');
        _loadFromCache(cacheBox, cacheKey);
      },
      (data) {
        _orders = List<OrderModel>.from(data['orders']);
        _items = List<OrderItemModel>.from(data['items']);
        _productCostPrices = Map<String, double>.from(data['costPrices'] ?? {});
        _duePayments = List<Map<String, dynamic>>.from(data['duePayments'] ?? []);
        _isUsingCachedData = false;
        _isCacheEmpty = false;
        _state = AnalyticsState.loaded;
        // Persist successful fetch to cache
        _saveToCache(cacheBox, cacheKey, data);
      },
    );

    notifyListeners();
  }

  /// Serialise a successful analytics payload to the Hive cache box.
  void _saveToCache(Box cacheBox, String key, Map<String, dynamic> data) {
    try {
      final payload = {
        'orders': (data['orders'] as List<OrderModel>)
            .map((o) => o.toJson())
            .toList(),
        'items': (data['items'] as List<OrderItemModel>)
            .map((i) => i.toJson())
            .toList(),
        'costPrices': data['costPrices'],
        'duePayments': data['duePayments'],
      };
      cacheBox.put(key, jsonEncode(payload));
    } catch (e) {
      debugPrint('[AnalyticsProvider] Cache save failed: $e');
    }
  }

  /// Load analytics data from the Hive cache. Sets [_isUsingCachedData] and
  /// [_isCacheEmpty] so the UI can render the appropriate offline banner.
  void _loadFromCache(Box cacheBox, String key) {
    final cached = cacheBox.get(key);
    if (cached != null) {
      try {
        final Map<String, dynamic> payload = jsonDecode(cached as String);
        _orders = (payload['orders'] as List)
            .map((j) => OrderModel.fromJson(j as Map<String, dynamic>))
            .toList();
        _items = (payload['items'] as List)
            .map((j) => OrderItemModel.fromJson(j as Map<String, dynamic>))
            .toList();
        _productCostPrices = Map<String, double>.from(
          (payload['costPrices'] as Map<String, dynamic>? ?? {}).map(
            (k, v) => MapEntry(k, (v as num).toDouble()),
          ),
        );
        _duePayments = List<Map<String, dynamic>>.from(
          payload['duePayments'] as List? ?? [],
        );
        _isUsingCachedData = true;
        _isCacheEmpty = false;
        _state = AnalyticsState.loaded;
        return;
      } catch (e) {
        debugPrint('[AnalyticsProvider] Cache decode failed: $e');
      }
    }
    // No usable cache — show empty offline message instead of an error
    _orders = [];
    _items = [];
    _productCostPrices = {};
    _duePayments = [];
    _isUsingCachedData = true;
    _isCacheEmpty = true;
    _state = AnalyticsState.loaded;
  }
}
