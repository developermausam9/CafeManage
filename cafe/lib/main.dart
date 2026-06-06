import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'core/network/supabase_config.dart';
import 'core/services/connectivity_service.dart';
import 'core/services/sync_service.dart';
import 'features/auth/data/datasources/auth_remote_data_source.dart';
import 'features/auth/data/repositories/auth_repository_impl.dart';
import 'features/auth/domain/usecases/login_usecase.dart';
import 'features/auth/domain/usecases/logout_usecase.dart';
import 'features/auth/domain/usecases/get_current_profile_usecase.dart';
import 'features/auth/presentation/providers/auth_provider.dart';
import 'features/auth/presentation/pages/auth_wrapper.dart';
import 'features/menu/data/datasources/product_remote_data_source.dart';
import 'features/menu/data/repositories/product_repository_impl.dart';
import 'features/menu/domain/usecases/get_products_usecase.dart';
import 'features/menu/domain/usecases/add_product_usecase.dart';
import 'features/menu/domain/usecases/update_product_usecase.dart';
import 'features/menu/domain/usecases/delete_product_usecase.dart';
import 'features/menu/presentation/providers/product_provider.dart';
import 'features/cafes/data/datasources/cafe_remote_data_source.dart';
import 'features/cafes/data/repositories/cafe_repository_impl.dart';
import 'features/cafes/domain/usecases/get_cafe_details_usecase.dart';
import 'features/cafes/presentation/providers/business_setup_provider.dart';

import 'features/orders/data/datasources/order_remote_data_source.dart';
import 'features/orders/data/repositories/order_repository_impl.dart';
import 'features/orders/domain/usecases/create_order_usecase.dart';
import 'features/orders/presentation/providers/pos_provider.dart';
import 'features/orders/presentation/providers/table_provider.dart';
import 'features/orders/presentation/providers/room_provider.dart';


import 'core/presentation/providers/printer_provider.dart';
import 'features/kitchen/presentation/providers/kitchen_provider.dart';

import 'features/analytics/data/datasources/analytics_remote_data_source.dart';
import 'features/analytics/data/repositories/analytics_repository_impl.dart';
import 'features/analytics/domain/usecases/get_dashboard_data_usecase.dart';
import 'features/analytics/presentation/providers/analytics_provider.dart';

import 'features/operations/data/datasources/operations_remote_data_source.dart';
import 'features/operations/data/repositories/operations_repository_impl.dart';
import 'features/operations/presentation/providers/operations_provider.dart';

import 'core/services/notification_service.dart';
import 'core/utils/snackbar_helper.dart';

// Super Admin
import 'features/super_admin/data/datasources/super_admin_remote_data_source.dart';
import 'features/super_admin/data/repositories/super_admin_repository_impl.dart';
import 'features/super_admin/domain/usecases/get_all_cafes_usecase.dart';
import 'features/super_admin/domain/usecases/get_super_admin_stats_usecase.dart';
import 'features/super_admin/domain/usecases/suspend_cafe_usecase.dart';
import 'features/super_admin/domain/usecases/update_subscription_usecase.dart';
import 'features/super_admin/domain/usecases/create_cafe_usecase.dart';
import 'features/super_admin/domain/usecases/update_cafe_usecase.dart';
import 'features/super_admin/presentation/providers/super_admin_provider.dart';
import 'features/auth/presentation/providers/subscription_provider.dart';
import 'features/notifications/presentation/providers/notification_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Notifications & request POST_NOTIFICATIONS permission (Android 13+)
  await NotificationService().init();
  await NotificationService().requestPermission();

  // Initialize Hive for offline caching
  await Hive.initFlutter();
  await Hive.openBox('cache');
  await Hive.openBox('offline_orders');
  await Hive.openBox('printer_settings');

  // Initialize Supabase
  await SupabaseConfig.initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Basic Dependency Injection setup
    final client = SupabaseConfig.client;

    // Auth dependencies
    final authRemoteDS = AuthRemoteDataSourceImpl(client);
    final authRepo = AuthRepositoryImpl(authRemoteDS);
    
    // Cafe dependencies
    final cafeRemoteDS = CafeRemoteDataSourceImpl(client);
    final cafeRepo = CafeRepositoryImpl(cafeRemoteDS);

    // Product dependencies
    final productRemoteDS = ProductRemoteDataSourceImpl(client);
    final productRepo = ProductRepositoryImpl(productRemoteDS);

    // Order dependencies
    final orderRemoteDS = OrderRemoteDataSourceImpl(client);
    final orderRepo = OrderRepositoryImpl(orderRemoteDS);

    // Analytics dependencies
    final analyticsRemoteDS = AnalyticsRemoteDataSourceImpl(client);
    final analyticsRepo = AnalyticsRepositoryImpl(analyticsRemoteDS);

    // Operations dependencies
    final operationsRemoteDS = OperationsRemoteDataSourceImpl(client);
    final operationsRepo = OperationsRepositoryImpl(operationsRemoteDS);

    // Connectivity and Sync Services
    final connectivityService = ConnectivityService();
    final syncService = SyncService(client: client, connectivityService: connectivityService);

    // Super Admin dependencies
    final superAdminRemoteDS = SuperAdminRemoteDataSource(client);
    final superAdminRepo = SuperAdminRepositoryImpl(superAdminRemoteDS);

    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: connectivityService),
        Provider.value(value: syncService),
        ChangeNotifierProvider(
          create: (_) => SubscriptionProvider(client),
        ),
        ChangeNotifierProvider(
          create: (_) => NotificationProvider(),
        ),
        ChangeNotifierProvider(
          create: (_) => SuperAdminProvider(
            getAllCafesUseCase: GetAllCafesUseCase(superAdminRepo),
            getSuperAdminStatsUseCase: GetSuperAdminStatsUseCase(superAdminRepo),
            suspendCafeUseCase: SuspendCafeUseCase(superAdminRepo),
            reactivateCafeUseCase: ReactivateCafeUseCase(superAdminRepo),
            updateSubscriptionUseCase: UpdateSubscriptionUseCase(superAdminRepo),
            createCafeUseCase: CreateCafeUseCase(superAdminRepo),
            updateCafeUseCase: UpdateCafeUseCase(superAdminRepo),
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => AnalyticsProvider(
            getDashboardDataUseCase: GetDashboardDataUseCase(analyticsRepo),
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => OperationsProvider(repository: operationsRepo),
        ),
        ChangeNotifierProvider(
          create: (_) => PrinterProvider(),
        ),
        ChangeNotifierProvider(
          create: (_) => KitchenProvider(),
        ),
        ChangeNotifierProvider(
          create: (_) => AuthProvider(
            loginUseCase: LoginUseCase(authRepo),
            logoutUseCase: LogoutUseCase(authRepo),
            getCurrentProfileUseCase: GetCurrentProfileUseCase(authRepo),
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => BusinessSetupProvider(
            getCafeDetailsUseCase: GetCafeDetailsUseCase(cafeRepo),
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => ProductProvider(
            getProductsUseCase: GetProductsUseCase(productRepo),
            addProductUseCase: AddProductUseCase(productRepo),
            updateProductUseCase: UpdateProductUseCase(productRepo),
            deleteProductUseCase: DeleteProductUseCase(productRepo),
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => TableProvider(),
        ),
        ChangeNotifierProvider(
          create: (_) => RoomProvider(),
        ),
        ChangeNotifierProvider(
          create: (_) => PosProvider(
            createOrderUseCase: CreateOrderUseCase(orderRepo),
            connectivityService: connectivityService,
            syncService: syncService,
          ),
        ),
      ],
      child: MaterialApp(
        title: 'Café POS',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
          useMaterial3: true,
        ),
        home: const AuthWrapper(),
        scaffoldMessengerKey: SnackbarHelper.scaffoldMessengerKey,
      ),
    );
  }
}
