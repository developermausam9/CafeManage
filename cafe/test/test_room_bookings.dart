import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cafe/core/network/supabase_config.dart';

void main() {
  test('End-to-End Room Booking Integration Test', () async {
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
    final roomNumber = 'TestRoom-999';
    final insertRoomRes = await client.from('rooms').insert({
      'cafe_id': cafeId,
      'room_number': roomNumber,
      'type': 'deluxe',
      'status': 'available',
      'price_per_night': 5000.0,
      'floor_number': 3,
      'max_occupancy': 3,
    }).select().single();

    final roomId = insertRoomRes['id'] as String;
    expect(roomId, isNotEmpty);
    print('Created Test Room: $roomId');

    try {
      // 3. Verify availability of our test room
      // Test overlaps: Booking 1 (June 10 - June 15)
      // Check availability for June 12 - June 14 (should be available since no booking exists yet)
      final checkInDate = '2026-06-12';
      final checkOutDate = '2026-06-14';

      final activeBookings = await client
          .from('room_bookings')
          .select()
          .eq('cafe_id', cafeId)
          .eq('room_id', roomId)
          .not('status', 'eq', 'cancelled');
      
      // Since no booking exists, it must be available
      final isOccupied = activeBookings.any((b) {
        final bIn = b['check_in_date'] as String;
        final bOut = b['check_out_date'] as String;
        return checkInDate.compareTo(bOut) < 0 && bIn.compareTo(checkOutDate) < 0;
      });
      expect(isOccupied, isFalse);
      print('Test Room is available for range $checkInDate to $checkOutDate');

      // 4. Create a booking
      final insertBookingRes = await client.from('room_bookings').insert({
        'cafe_id': cafeId,
        'room_id': roomId,
        'guest_name': 'Integration Test Guest',
        'guest_phone': '+9779800000000',
        'guest_email': 'test@example.com',
        'check_in_date': checkInDate,
        'check_out_date': checkOutDate,
        'status': 'pending',
        'total_amount': 10000.0,
        'payment_status': 'pending',
        'transaction_ref': 'TXN_REF_99999',
      }).select().single();


      final bookingId = insertBookingRes['id'] as String;
      expect(bookingId, isNotEmpty);
      print('Created Booking: $bookingId');

      // Update room status to occupied
      await client.from('rooms').update({'status': 'occupied'}).eq('id', roomId);
      print('Room status updated to occupied');

      // 5. Verify room is now occupied/unavailable for overlapping dates
      final recheckBookings = await client
          .from('room_bookings')
          .select()
          .eq('cafe_id', cafeId)
          .eq('room_id', roomId)
          .not('status', 'eq', 'cancelled');
      
      final isOccupiedNow = recheckBookings.any((b) {
        final bIn = b['check_in_date'] as String;
        final bOut = b['check_out_date'] as String;
        return checkInDate.compareTo(bOut) < 0 && bIn.compareTo(checkOutDate) < 0;
      });
      expect(isOccupiedNow, isTrue);
      print('Verified: Test Room is now correctly flagged as occupied/unavailable for range $checkInDate to $checkOutDate');

      // 6. Clean up booking
      await client.from('room_bookings').delete().eq('id', bookingId);
      print('Deleted Booking');

    } finally {
      // Clean up room
      await client.from('rooms').delete().eq('id', roomId);
      print('Deleted Test Room');
    }
  });
}
