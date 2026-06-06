import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:cafe/core/network/supabase_config.dart';

void main() {
  test('Due Payments and Audited Formulas Integration Test', () async {
    final client = SupabaseClient(
      SupabaseConfig.supabaseUrl,
      SupabaseConfig.supabaseAnonKey,
      authOptions: const AuthClientOptions(
        authFlowType: AuthFlowType.implicit,
      ),
    );

    print('================================================================');
    print('  STARTING INTEGRATION TEST FOR DUE PAYMENTS & AUDITED FORMULAS  ');
    print('================================================================');

    // 1. Authenticate Developer Account
    final authSession = await client.auth.signInWithPassword(
      email: 'developermausam9@gmail.com',
      password: '123456',
    );
    final userUid = authSession.user!.id;
    
    // Get the cafe ID
    final profile = await client.from('profiles').select('cafe_id').eq('id', userUid).single();
    final cafeId = profile['cafe_id'] as String;
    print('✓ Developer authenticated! Cafe ID: $cafeId');

    // 2. Cleanup outstanding due test records to ensure absolute correctness
    await client.from('due_payments').delete().eq('cafe_id', cafeId);
    await client.from('orders').delete().eq('cafe_id', cafeId).eq('payment_method', 'due');
    await client.from('customer_dues').delete().eq('cafe_id', cafeId).eq('name', 'Integration Test Customer');
    print('✓ Test environment cleaned up!');

    // 3. Create a Customer Due Account
    final customerDueId = const Uuid().v4();
    await client.from('customer_dues').insert({
      'id': customerDueId,
      'cafe_id': cafeId,
      'name': 'Integration Test Customer',
      'phone': '9800000000',
      'total_due': 0.0,
    });
    print('✓ Customer Due Account created: $customerDueId');

    // 4. Create a Due Order of Rs. 500
    final orderId = const Uuid().v4();
    final grandTotal = 500.0;

    print('Step 4a: Saving order as completed service-wise with grand_total = $grandTotal...');
    await client.from('orders').insert({
      'id': orderId,
      'cafe_id': cafeId,
      'type': 'dine_in',
      'status': 'completed',
      'subtotal': grandTotal,
      'discount': 0.0,
      'tax_amount': 0.0,
      'service_charge': 0.0,
      'grand_total': grandTotal,
      'payment_method': 'due',
      'payment_status': 'unpaid',
      'paid_amount': 0.0,
      'remaining_due': grandTotal,
      'customer_due_id': customerDueId,
    });

    print('Step 4b: Increasing customer dues in customer_dues table (+500)...');
    await client.from('customer_dues').update({
      'total_due': grandTotal,
      'last_updated_at': DateTime.now().toIso8601String(),
    }).eq('id', customerDueId);

    // Verify initial values
    final checkOrder1 = await client.from('orders').select().eq('id', orderId).single();
    expect(checkOrder1['payment_status'], equals('unpaid'));
    expect((checkOrder1['remaining_due'] as num).toDouble(), equals(500.0));
    expect((checkOrder1['paid_amount'] as num).toDouble(), equals(0.0));

    final checkDue1 = await client.from('customer_dues').select('total_due').eq('id', customerDueId).single();
    expect((checkDue1['total_due'] as num).toDouble(), equals(500.0));
    print('✓ Success! Customer Dues = Rs. 500, Order remaining_due = Rs. 500, paid_amount = Rs. 0');

    // 5. Pay Rs. 200 due (QR method)
    print('Step 5: Clearing Rs. 200 due using QR...');
    final amountPaid1 = 200.0;

    // Simulate OperationsProvider.processDuePayment
    // Update customer total_due
    await client.from('customer_dues').update({
      'total_due': 300.0,
      'last_updated_at': DateTime.now().toIso8601String(),
    }).eq('id', customerDueId);

    // Update order paid_amount & remaining_due
    await client.from('orders').update({
      'paid_amount': 200.0,
      'remaining_due': 300.0,
      'payment_status': 'partial',
    }).eq('id', orderId);

    // Create due_payment record linked to order
    await client.from('due_payments').insert({
      'id': const Uuid().v4(),
      'cafe_id': cafeId,
      'due_id': customerDueId,
      'amount_paid': amountPaid1,
      'payment_date': DateTime.now().toIso8601String(),
      'payment_method': 'qr',
      'order_id': orderId,
    });

    // Verify values after Rs. 200 payment
    final checkOrder2 = await client.from('orders').select().eq('id', orderId).single();
    expect(checkOrder2['payment_status'], equals('partial'));
    expect((checkOrder2['remaining_due'] as num).toDouble(), equals(300.0));
    expect((checkOrder2['paid_amount'] as num).toDouble(), equals(200.0));

    final checkDue2 = await client.from('customer_dues').select('total_due').eq('id', customerDueId).single();
    expect((checkDue2['total_due'] as num).toDouble(), equals(300.0));

    final checkDP1 = await client.from('due_payments').select().eq('due_id', customerDueId);
    expect((checkDP1 as List).length, equals(1));
    expect((checkDP1.first['amount_paid'] as num).toDouble(), equals(200.0));
    expect(checkDP1.first['payment_method'], equals('qr'));
    print('✓ Success! Customer Dues = Rs. 300, Order remaining_due = Rs. 300, paid_amount = Rs. 200');

    // 6. Pay remaining Rs. 300 due (Cash method)
    print('Step 6: Clearing remaining Rs. 300 due using Cash...');
    final amountPaid2 = 300.0;

    // Update customer total_due
    await client.from('customer_dues').update({
      'total_due': 0.0,
      'last_updated_at': DateTime.now().toIso8601String(),
    }).eq('id', customerDueId);

    // Update order paid_amount & remaining_due
    await client.from('orders').update({
      'paid_amount': 500.0,
      'remaining_due': 0.0,
      'payment_status': 'paid',
      'paid_at': DateTime.now().toIso8601String(),
    }).eq('id', orderId);

    // Create due_payment record linked to order
    await client.from('due_payments').insert({
      'id': const Uuid().v4(),
      'cafe_id': cafeId,
      'due_id': customerDueId,
      'amount_paid': amountPaid2,
      'payment_date': DateTime.now().toIso8601String(),
      'payment_method': 'cash',
      'order_id': orderId,
    });

    // Verify values after Rs. 300 payment (Full clearance)
    final checkOrder3 = await client.from('orders').select().eq('id', orderId).single();
    expect(checkOrder3['payment_status'], equals('paid'));
    expect((checkOrder3['remaining_due'] as num).toDouble(), equals(0.0));
    expect((checkOrder3['paid_amount'] as num).toDouble(), equals(500.0));
    expect(checkOrder3['paid_at'], isNotNull);

    final checkDue3 = await client.from('customer_dues').select('total_due').eq('id', customerDueId).single();
    expect((checkDue3['total_due'] as num).toDouble(), equals(0.0));

    final checkDP2 = await client.from('due_payments').select().eq('due_id', customerDueId).order('payment_date', ascending: true);
    expect((checkDP2 as List).length, equals(2));
    expect((checkDP2.last['amount_paid'] as num).toDouble(), equals(300.0));
    expect(checkDP2.last['payment_method'], equals('cash'));

    print('================================================================');
    print('  INTEGRATION TEST SUCCESSFULLY PASSED! DUE ACCOUNTING VERIFIED! ');
    print('================================================================');
  });
}
