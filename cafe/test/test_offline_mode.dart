import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cafe/core/network/supabase_config.dart';
import 'package:cafe/core/utils/either.dart';
import 'package:cafe/core/error/failures.dart';
import 'package:cafe/core/services/sync_service.dart';
import 'package:cafe/core/services/connectivity_service.dart';
import 'package:cafe/features/orders/presentation/providers/pos_provider.dart';
import 'package:cafe/features/orders/data/models/order_model.dart';
import 'package:cafe/features/orders/data/models/order_item_model.dart';
import 'package:cafe/features/orders/domain/usecases/create_order_usecase.dart';
import 'package:cafe/features/orders/domain/repositories/order_repository.dart';
import 'package:cafe/features/menu/data/models/product_model.dart';

// Fake implementations for testing
class FakeConnectivityService extends ConnectivityService {
  bool _online = true;
  @override
  bool get isOnline => _online;

  void setOnline(bool val) {
    _online = val;
    notifyListeners();
  }
}

class FakeOrderRepository implements OrderRepository {
  @override
  Future<Either<Failure, List<OrderModel>>> getOrders(String cafeId) async {
    return const Right([]);
  }

  @override
  Future<Either<Failure, OrderModel>> createOrder(OrderModel order, List<OrderItemModel> items) async {
    return Right(order);
  }

  @override
  Future<Either<Failure, OrderModel>> updateOrderStatus(String orderId, String cafeId, String status) async {
    throw UnimplementedError();
  }
}

class FakeCreateOrderUseCase extends CreateOrderUseCase {
  FakeCreateOrderUseCase() : super(FakeOrderRepository());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late FakeConnectivityService connectivityService;
  late SyncService syncService;
  late PosProvider posProvider;

  setUpAll(() async {
    // Set up Hive in a temporary directory
    tempDir = await Directory.systemTemp.createTemp('cafe_hive_test');
    Hive.init(tempDir.path);
    await Hive.openBox('cache');
    await Hive.openBox('offline_orders');

    // Initialize SharedPreferences mock values to resolve plugin lookup
    SharedPreferences.setMockInitialValues({});

    // Initialize Supabase instance in local mock configuration
    try {
      await Supabase.initialize(
        url: SupabaseConfig.supabaseUrl,
        anonKey: SupabaseConfig.supabaseAnonKey,
      );
    } catch (e) {
      // Already initialized or caught silently in test environment
    }
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  setUp(() {
    connectivityService = FakeConnectivityService();
    syncService = SyncService(
      client: Supabase.instance.client,
      connectivityService: connectivityService,
    );
    
    posProvider = PosProvider(
      createOrderUseCase: FakeCreateOrderUseCase(),
      connectivityService: connectivityService,
      syncService: syncService,
    );
  });

  test('OFFLINE ARCHITECTURE TEST: Product Caching, Offline Creation, Cart & Sync', () async {
    print('===========================================================');
    print(' STARTING OFFLINE ARCHITECTURE & PERSISTENCE TEST ');
    print('===========================================================');

    final cafeId = const Uuid().v4();
    final waiterId = const Uuid().v4();
    final productId = const Uuid().v4();

    // 1. Setup cache box and seed mock product listing
    final cacheBox = Hive.box('cache');
    final cacheKey = 'products_$cafeId';

    final testProduct = ProductModel(
      id: productId,
      cafeId: cafeId,
      name: 'Iced Latte Extra Cold',
      sellingPrice: 180.0,
      stockQuantity: 100,
      isStockTracked: true,
    );

    // Cache products list locally to simulate "Cached Products" state from previous online session
    await cacheBox.put(cacheKey, jsonEncode([testProduct.toJson()]));
    print('✓ Step 1: Seeded 1 product (Iced Latte, Qty: 100) in local Hive cache.');

    // 2. Go offline
    connectivityService.setOnline(false);
    expect(connectivityService.isOnline, isFalse);
    print('✓ Step 2: Set connectivity status to OFFLINE.');

    // 3. Load product and build cart offline
    final cachedData = cacheBox.get(cacheKey);
    expect(cachedData, isNotNull);
    final List<dynamic> jsonList = jsonDecode(cachedData);
    final products = jsonList.map((json) => ProductModel.fromJson(json)).toList();
    
    expect(products.length, equals(1));
    expect(products.first.name, equals('Iced Latte Extra Cold'));
    print('✓ Step 3: Verified products can be browse/listed completely offline from cache.');

    // Add to PosProvider cart
    posProvider.addToCart(products.first);
    expect(posProvider.cart.length, equals(1));
    expect(posProvider.subtotal, equals(180.0));
    print('✓ Step 4: Product added to POS cart successfully offline.');

    // 4. Place order offline
    final success = await posProvider.sendToKitchen(cafeId, waiterId);
    expect(success, isTrue);
    print('✓ Step 5: KOT Order submitted successfully offline (sent to kitchen local queue).');

    // 5. Verify order exists inside "offline_orders" Hive box (App Restart Persistence)
    final offlineBox = Hive.box('offline_orders');
    expect(offlineBox.length, equals(1));

    final queuedOrderJsonString = offlineBox.getAt(0);
    expect(queuedOrderJsonString, isNotNull);

    final Map<String, dynamic> offlineData = jsonDecode(queuedOrderJsonString);
    final orderMap = offlineData['order'] as Map<String, dynamic>;
    final itemsList = offlineData['items'] as List;

    expect(orderMap['status'], equals('kitchen_sent'));
    expect(itemsList.length, equals(1));
    expect(itemsList.first['product_name'], equals('Iced Latte Extra Cold'));
    print('✓ Step 6: Verified app persistence — order successfully queued with items inside offline box.');

    // 6. Verify local cache stock is modified
    final updatedCachedData = cacheBox.get(cacheKey);
    final List<dynamic> updatedJsonList = jsonDecode(updatedCachedData);
    final updatedStock = updatedJsonList.first['stock_quantity'] as int;
    
    expect(updatedStock, equals(99)); // Initial 100 - 1 ordered = 99
    print('✓ Step 7: Verified local stock balance was decremented offline from 100 to $updatedStock.');

    // 7. Clear local queue to finish test clean
    await offlineBox.clear();
    await cacheBox.clear();
    print('===========================================================');
    print('          OFFLINE ARCHITECTURE QA TEST PASSED 100%         ');
    print('===========================================================');
  });
}
