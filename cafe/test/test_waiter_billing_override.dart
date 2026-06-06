import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

  test('Waiter Billing Override Setting - Fetch & Update Logic', () async {
    print('================================================================');
    print(' STARTING WAITER BILLING OVERRIDE PERMISSION TEST              ');
    print('================================================================');

    // 1. Super Admin logs in
    print('Step 1: Logging in as Super Admin to perform setup...');
    final adminSession = await client.auth.signInWithPassword(
      email: 'mausamban9@gmail.com',
      password: '123456',
    );
    expect(adminSession.user, isNotNull);
    print('✓ Super Admin authenticated successfully!');

    // Create a new program Cafe for isolation
    final randId = DateTime.now().millisecondsSinceEpoch % 100000;
    final cafeName = 'Override Test Café $randId';
    final ownerEmail = 'owner_override_$randId@stress.com';
    final ownerPassword = 'password123';

    print('Creating Cafe: $cafeName with Owner: $ownerEmail...');
    final ownerPhone = '9841' + (DateTime.now().millisecondsSinceEpoch % 1000000).toString().padLeft(6, '0');
    await client.rpc('create_cafe_with_owner_v2', params: {
      'p_cafe_name': cafeName,
      'p_address': 'Jhamsikhel, Lalitpur',
      'p_pan_vat': '987654321',
      'p_phone': ownerPhone,
      'p_owner_name': 'Override Owner',
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
    print('Step 2: Authenticating as the Café Owner...');
    final ownerSession = await client.auth.signInWithPassword(
      email: ownerEmail,
      password: ownerPassword,
    );
    final ownerUid = ownerSession.user!.id;
    
    // Get the cafe ID of the owner's profile
    final ownerProfile = await client.from('profiles').select('cafe_id').eq('id', ownerUid).single();
    final cafeId = ownerProfile['cafe_id'] as String;
    print('✓ Owner authenticated! Café ID: $cafeId');

    // 3. Test update and fetch settings for this Cafe
    print('Step 3: Updating waiter billing override setting (Enable)...');
    await client.from('settings').upsert({
      'cafe_id': cafeId,
      'waiter_billing_enabled': true,
    }, onConflict: 'cafe_id');
    print('✓ Upsert complete.');

    print('Step 4: Verifying the setting is stored correctly...');
    final settingsVal = await client
        .from('settings')
        .select('waiter_billing_enabled')
        .eq('cafe_id', cafeId)
        .single();
    
    expect(settingsVal['waiter_billing_enabled'], isTrue);
    print('✓ Waiter Billing Override is enabled correctly!');

    print('Step 5: Updating waiter billing override setting (Disable)...');
    await client.from('settings').upsert({
      'cafe_id': cafeId,
      'waiter_billing_enabled': false,
    }, onConflict: 'cafe_id');

    final settingsValDisabled = await client
        .from('settings')
        .select('waiter_billing_enabled')
        .eq('cafe_id', cafeId)
        .single();
    
    expect(settingsValDisabled['waiter_billing_enabled'], isFalse);
    print('✓ Waiter Billing Override is disabled correctly!');

    // Cleanup Cafe data
    print('Cleaning up test data...');
    await client.from('cafes').delete().eq('id', cafeId);
    print('✓ Cleanup complete!');
    print('================================================================');
    print('  WAITER BILLING OVERRIDE TEST PASSED 100%                     ');
    print('================================================================');
  });
}
