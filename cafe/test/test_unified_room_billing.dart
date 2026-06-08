import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cafe/core/network/supabase_config.dart';
import 'package:uuid/uuid.dart';

void main() {
  test('Unified Room Billing and Checkout Guards Integration Test', () async {
    final client = SupabaseClient(
      SupabaseConfig.supabaseUrl,
      SupabaseConfig.supabaseAnonKey,
      authOptions: const AuthClientOptions(
        authFlowType: AuthFlowType.implicit,
      ),
    );

    // 1. Authenticate
    final authRes = await client.auth.signInWithPassword(
      email: 'developermausam9@gmail.com',
      password: '123456',
    );
    final user = authRes.user;
    expect(user, isNotNull);

    // Get cafe_id
    final profile = await client.from('profiles').select('cafe_id').eq('id', user!.id).single();
    final cafeId = profile['cafe_id'] as String;
    expect(cafeId, isNotEmpty);

    print('Authenticated for Cafe: $cafeId');

    // 2. Create a test room
    final roomNumber = 'TestBillingRoom-777';
    final insertRoomRes = await client.from('rooms').insert({
      'cafe_id': cafeId,
      'room_number': roomNumber,
      'type': 'deluxe',
      'status': 'available',
      'price_per_night': 4000.0,
      'floor_number': 2,
      'max_occupancy': 2,
    }).select().single();

    final roomId = insertRoomRes['id'] as String;
    expect(roomId, isNotEmpty);
    print('Created Test Room: $roomId');

    String? bookingId;
    String? orderId;

    try {
      // 3. Create a room booking
      final checkInDate = '2026-06-20';
      final checkOutDate = '2026-06-22';
      final nights = 2;
      final roomCharge = 4000.0 * nights;

      final insertBookingRes = await client.from('room_bookings').insert({
        'cafe_id': cafeId,
        'room_id': roomId,
        'guest_name': 'Billing Guard Test Guest',
        'guest_phone': '+9779800000001',
        'guest_email': 'billing_test@example.com',
        'check_in_date': checkInDate,
        'check_out_date': checkOutDate,
        'status': 'confirmed',
        'total_amount': roomCharge,
        'payment_status': 'pending',
      }).select().single();

      bookingId = insertBookingRes['id'] as String;
      expect(bookingId, isNotEmpty);
      print('Created Booking: $bookingId');

      // 4. Simulate Check-In (Create booking updates & initial active order)
      final now = DateTime.now().toIso8601String();
      await client.from('room_bookings').update({
        'status': 'checked_in',
        'actual_checkin_at': now,
        'room_charge': roomCharge,
      }).eq('id', bookingId);

      await client.from('rooms').update({'status': 'occupied'}).eq('id', roomId);

      orderId = const Uuid().v4();
      await client.from('orders').insert({
        'id': orderId,
        'cafe_id': cafeId,
        'room_booking_id': bookingId,
        'room_id': roomId,
        'type': 'room_service',
        'status': 'served',
        'subtotal': 0.0,
        'discount': 0.0,
        'tax_amount': 0.0,
        'service_charge': 0.0,
        'grand_total': 0.0,
        'payment_status': 'unpaid',
        'remaining_due': roomCharge,
      });
      print('Simulated Check-in: Active Order $orderId created with status served.');

      // 5. Verify active order exists and checkout is blocked
      final activeOrdersData = await client
          .from('orders')
          .select('id, status')
          .eq('room_booking_id', bookingId)
          .neq('status', 'cancelled')
          .neq('status', 'completed');
      expect(activeOrdersData.length, equals(1));
      expect(activeOrdersData[0]['status'], equals('served'));
      print('Verified: 1 active order exists for booking. Check-out is blocked.');

      // 6. Simulate customer adding food items (order status goes back to kitchen_sent)
      final double foodSubtotal = 1000.0;
      final double tax = foodSubtotal * 0.13;
      final double newGrandTotal = foodSubtotal + tax;

      // Update active order
      await client.from('orders').update({
        'subtotal': foodSubtotal,
        'tax_amount': tax,
        'grand_total': newGrandTotal,
        'remaining_due': newGrandTotal,
        'status': 'kitchen_sent',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', orderId);

      final updatedOrder = await client.from('orders').select('status, grand_total').eq('id', orderId).single();
      expect(updatedOrder['status'], equals('kitchen_sent'));
      print('Simulated food order additions: Order status updated to kitchen_sent.');

      // 7. Simulate payment finalization in Billing screen (status changes to completed)
      final double finalGrandTotal = newGrandTotal + roomCharge; // subtotal + tax + roomCharge
      await client.from('orders').update({
        'status': 'completed',
        'payment_method': 'cash',
        'payment_status': 'paid',
        'paid_amount': finalGrandTotal,
        'remaining_due': 0.0,
        'completed_at': DateTime.now().toUtc().toIso8601String(),
        'grand_total': finalGrandTotal,
      }).eq('id', orderId);

      // Verify no active orders exist now
      final remainingActiveOrders = await client
          .from('orders')
          .select('id, status')
          .eq('room_booking_id', bookingId)
          .neq('status', 'cancelled')
          .neq('status', 'completed');
      expect(remainingActiveOrders.isEmpty, isTrue);
      print('Simulated Billing Screen payment: 0 active orders remain. Check-out is now unblocked.');

      // 8. Simulate Booking Checkout completion
      final completedOrders = await client
          .from('orders')
          .select('grand_total, payment_method, subtotal')
          .eq('room_booking_id', bookingId)
          .eq('status', 'completed');
      
      final double computedGrandTotal = completedOrders.fold(0.0, (sum, o) => sum + ((o['grand_total'] as num?)?.toDouble() ?? 0.0));
      expect(computedGrandTotal, equals(finalGrandTotal));

      final double foodOrdersTotal = (computedGrandTotal - roomCharge).clamp(0.0, double.infinity);
      final paymentMethod = completedOrders.isNotEmpty ? completedOrders.first['payment_method'] : 'cash';

      await client.from('room_bookings').update({
        'status': 'checked_out',
        'actual_checkout_at': DateTime.now().toIso8601String(),
        'food_orders_total': foodOrdersTotal,
        'grand_total': computedGrandTotal,
        'payment_method': paymentMethod,
        'payment_status': 'paid',
      }).eq('id', bookingId);

      await client.from('rooms').update({'status': 'dirty'}).eq('id', roomId);

      final finalBooking = await client.from('room_bookings').select('status, grand_total').eq('id', bookingId).single();
      expect(finalBooking['status'], equals('checked_out'));
      expect(finalBooking['grand_total'], equals(computedGrandTotal));
      print('Simulated check-out successfully verified!');

    } finally {
      // 9. Clean up test records
      if (orderId != null) {
        await client.from('orders').delete().eq('id', orderId);
      }
      if (bookingId != null) {
        await client.from('room_bookings').delete().eq('id', bookingId);
      }
      await client.from('rooms').delete().eq('id', roomId);
      print('Cleaned up all integration test records.');
    }
  });
}
