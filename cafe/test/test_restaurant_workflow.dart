import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:cafe/core/network/supabase_config.dart';

void main() {
  late SupabaseClient client;

  setUpAll(() {
    client = SupabaseClient(
      SupabaseConfig.supabaseUrl,
      SupabaseConfig.supabaseAnonKey,
      authOptions: const AuthClientOptions(
        authFlowType: AuthFlowType.implicit,
      ),
    );
  });

  test('Premium Restaurant Workflow & Stress Test', () async {
    print('================================================================');
    print('  STARTING INTEGRATION & STRESS TEST FOR RESTAURANT WORKFLOW  ');
    print('================================================================');

    // 1. Super Admin logs in
    print('Step 1: Logging in as Super Admin...');
    final adminSession = await client.auth.signInWithPassword(
      email: 'mausamban9@gmail.com',
      password: '123456',
    );
    print('✓ Super Admin authenticated successfully! Token: ${adminSession.session?.accessToken.substring(0, 10)}...');

    // Super Admin creates a new Premium Café using the RPC
    final randId = DateTime.now().millisecondsSinceEpoch % 100000;
    final cafeName = 'Stress Test Café $randId';
    final ownerEmail = 'owner$randId@stress.com';
    final ownerPassword = 'password123';

    print('Creating Cafe: $cafeName with Owner: $ownerEmail...');
    
    // Call the database function to create cafe, profile, and subscription programmatically
    final ownerPhone = '9841' + (DateTime.now().millisecondsSinceEpoch % 1000000).toString().padLeft(6, '0');
    await client.rpc('create_cafe_with_owner_v2', params: {
      'p_cafe_name': cafeName,
      'p_address': 'Durbarmarg, Kathmandu',
      'p_pan_vat': '123456789',
      'p_phone': ownerPhone,
      'p_owner_name': 'Stress Cafe Owner',
      'p_email': ownerEmail,
      'p_password': ownerPassword,
      'p_plan_type': 'Premium',
      'p_monthly_fee': 5000.0,
      'p_subscription_start': DateTime.now().toIso8601String(),
      'p_subscription_end': DateTime.now().add(const Duration(days: 365)).toIso8601String(),
      'p_status': 'active',
    });
    print('✓ Café and Owner created successfully!');

    // 2. Newly created Owner logs in
    print('Step 2: Authenticating as the newly created Café Owner...');
    final ownerSession = await client.auth.signInWithPassword(
      email: ownerEmail,
      password: ownerPassword,
    );
    final ownerUid = ownerSession.user!.id;
    
    // Get the cafe ID of the owner's profile
    final ownerProfile = await client.from('profiles').select('cafe_id').eq('id', ownerUid).single();
    final cafeId = ownerProfile['cafe_id'] as String;
    print('✓ Owner authenticated! Café ID: $cafeId');

    // 3. Owner creates staff: 2 waiters, 1 cashier, 1 kitchen
    print('Step 3: Creating Waiters, Cashier, and Kitchen staff...');
    
    Future<String> createStaffUser(String email, String password) async {
      final tempClient = SupabaseClient(
        SupabaseConfig.supabaseUrl,
        SupabaseConfig.supabaseAnonKey,
        authOptions: const AuthClientOptions(
          authFlowType: AuthFlowType.implicit,
        ),
      );
      final res = await tempClient.auth.signUp(
        email: email,
        password: password,
      );
      final uid = res.user!.id;
      tempClient.dispose();
      return uid;
    }

    final waiter1Email = 'waiter1_$randId@stress.com';
    final waiter2Email = 'waiter2_$randId@stress.com';
    final cashierEmail = 'cashier_$randId@stress.com';
    final kitchenEmail = 'kitchen_$randId@stress.com';

    final waiter1Id = await createStaffUser(waiter1Email, 'password123');
    final waiter2Id = await createStaffUser(waiter2Email, 'password123');
    final cashierId = await createStaffUser(cashierEmail, 'password123');
    final kitchenId = await createStaffUser(kitchenEmail, 'password123');

    // Insert staff profiles under the owner's cafe
    await client.from('profiles').insert([
      {
        'id': waiter1Id,
        'cafe_id': cafeId,
        'full_name': 'Stress Waiter 1',
        'role': 'waiter',
        'is_active': true,
      },
      {
        'id': waiter2Id,
        'cafe_id': cafeId,
        'full_name': 'Stress Waiter 2',
        'role': 'waiter',
        'is_active': true,
      },
      {
        'id': cashierId,
        'cafe_id': cafeId,
        'full_name': 'Stress Cashier',
        'role': 'cashier',
        'is_active': true,
      },
      {
        'id': kitchenId,
        'cafe_id': cafeId,
        'full_name': 'Stress Chef',
        'role': 'kitchen',
        'is_active': true,
      }
    ]);
    print('✓ Profiles for roles created successfully');

    // Seed Tables
    final table1Id = const Uuid().v4();
    final table2Id = const Uuid().v4();

    print('Creating Tables for Dining area...');
    await client.from('tables').insert([
      {
        'id': table1Id,
        'cafe_id': cafeId,
        'name': 'Table 1',
        'status': 'free',
        'is_occupied': false,
      },
      {
        'id': table2Id,
        'cafe_id': cafeId,
        'name': 'Table 2',
        'status': 'free',
        'is_occupied': false,
      }
    ]);
    print('✓ Table 1 and Table 2 created successfully');

    // Seed Categories & Products
    final categoryId = const Uuid().v4();
    final productId = const Uuid().v4();

    print('Seeding Category and Product Menu...');
    await client.from('categories').insert({
      'id': categoryId,
      'cafe_id': cafeId,
      'name': 'Stress Food',
    });

    await client.from('products').insert({
      'id': productId,
      'cafe_id': cafeId,
      'category_id': categoryId,
      'name': 'Momo & Cola Combo',
      'price': 400.0,
      'cost_price': 150.0,
      'stock_quantity': 500,
      'is_available': true,
      'is_stock_tracked': true,
    });
    print('✓ Products seeded successfully');

    // 4. Waiter 1 opens Table 1, adds items, and sends to Kitchen
    print('Step 4: Waiter 1 places KOT order for Table 1...');
    final order1Id = const Uuid().v4();
    await client.from('orders').insert({
      'id': order1Id,
      'cafe_id': cafeId,
      'table_id': table1Id,
      'waiter_id': waiter1Id,
      'type': 'dine_in',
      'status': 'pending',
      'subtotal': 400.0,
      'discount': 0.0,
      'tax_amount': 52.00,
      'service_charge': 0.0,
      'grand_total': 452.00,
    });

    await client.from('order_items').insert({
      'order_id': order1Id,
      'product_id': productId,
      'product_name': 'Momo & Cola Combo',
      'quantity': 1,
      'unit_price': 400.0,
      'total_price': 400.0,
      'notes': 'Extra dipping sauce',
    });

    // Check Table 1 status transitions to 'preparing' via Postgres trigger!
    print('Verifying Table 1 Status updated via Trigger...');
    var t1 = await client.from('tables').select('status, is_occupied').eq('id', table1Id).single();
    print('-> Table 1 Status: ${t1['status']} | Occupied: ${t1['is_occupied']}');
    expect(t1['status'], equals('preparing'));
    expect(t1['is_occupied'], isTrue);

    // 5. Waiter 2 opens Table 2, adds items, and sends to Kitchen
    print('Step 5: Waiter 2 places KOT order for Table 2...');
    final order2Id = const Uuid().v4();
    await client.from('orders').insert({
      'id': order2Id,
      'cafe_id': cafeId,
      'table_id': table2Id,
      'waiter_id': waiter2Id,
      'type': 'dine_in',
      'status': 'pending',
      'subtotal': 800.0,
      'discount': 0.0,
      'tax_amount': 104.00,
      'service_charge': 0.0,
      'grand_total': 904.00,
    });

    await client.from('order_items').insert({
      'order_id': order2Id,
      'product_id': productId,
      'product_name': 'Momo & Cola Combo',
      'quantity': 2,
      'unit_price': 400.0,
      'total_price': 800.0,
    });

    var t2 = await client.from('tables').select('status, is_occupied').eq('id', table2Id).single();
    print('-> Table 2 Status: ${t2['status']} | Occupied: ${t2['is_occupied']}');
    expect(t2['status'], equals('preparing'));

    // 6. Kitchen staff receives and updates: Order 1 -> Preparing, Order 2 -> Ready
    print('Step 6: Kitchen Staff updates KOT statuses...');
    
    // Order 1 -> preparing
    await client.from('orders').update({'status': 'preparing'}).eq('id', order1Id);
    print('✓ Order 1 marked as Preparing');

    // Order 2 -> ready
    await client.from('orders').update({'status': 'ready'}).eq('id', order2Id);
    print('✓ Order 2 marked as Ready');

    // 7. Verify table statuses update correctly in realtime
    print('Step 7: Verifying Table statuses update correctly via triggers...');
    t1 = await client.from('tables').select('status').eq('id', table1Id).single();
    t2 = await client.from('tables').select('status').eq('id', table2Id).single();
    print('-> Table 1 status (Kitchen Preparing): ${t1['status']}');
    print('-> Table 2 status (Kitchen Ready): ${t2['status']}');
    expect(t1['status'], equals('preparing'));
    expect(t2['status'], equals('ready'));

    // Waiter serves Table 2 (order status -> served, table status -> occupied)
    print('Waiter serves Table 2...');
    await client.from('orders').update({'status': 'served'}).eq('id', order2Id);
    t2 = await client.from('tables').select('status').eq('id', table2Id).single();
    print('-> Table 2 status (Served): ${t2['status']}');
    expect(t2['status'], equals('occupied'));

    // 8. Cashier opens Table 1 (Order 1 -> billed, Table 1 -> billing_pending)
    print('Step 8: Cashier opens Table 1 for Checkout...');
    await client.from('orders').update({'status': 'billed'}).eq('id', order1Id);
    
    t1 = await client.from('tables').select('status').eq('id', table1Id).single();
    print('-> Table 1 status (Opened for Billing): ${t1['status']}');
    expect(t1['status'], equals('billing_pending'));

    // Cashier completes payment for Table 1 (Order 1 -> completed, Table 1 -> free)
    print('Cashier completes payment and checkout for Table 1...');
    await client.from('orders').update({
      'status': 'completed',
      'payment_method': 'cash',
      'cashier_id': cashierId,
    }).eq('id', order1Id);

    t1 = await client.from('tables').select('status, is_occupied').eq('id', table1Id).single();
    print('-> Table 1 status (Completed): ${t1['status']} | Occupied: ${t1['is_occupied']}');
    expect(t1['status'], equals('free'));
    expect(t1['is_occupied'], isFalse);

    // 9. Verify Order Status History Tracking Timeline
    print('Step 9: Verifying Order Status History logs generated by triggers...');
    final history = await client
        .from('order_status_history')
        .select()
        .eq('order_id', order1Id)
        .order('changed_at', ascending: true);
    print('Timeline History log count: ${history.length}');
    for (var log in history) {
      print('  - Log Status: ${log['status']} at ${log['changed_at']}');
    }
    expect(history.length, greaterThanOrEqualTo(2));

    // Cleanup Café to keep database clean
    print('Cleaning up stress test data...');
    await client.from('cafes').delete().eq('id', cafeId);
    print('✓ Cleanup complete!');

    print('================================================================');
    print('  ALL STRESS TEST SCENARIOS PASSED SUCCESSFULLY! 100% CORRECT   ');
    print('================================================================');
  });
}
