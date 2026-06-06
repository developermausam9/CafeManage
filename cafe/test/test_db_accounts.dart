import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cafe/core/network/supabase_config.dart';

void main() {
  test('List active owner accounts in DB', () async {
    final client = SupabaseClient(
      SupabaseConfig.supabaseUrl,
      SupabaseConfig.supabaseAnonKey,
    );

    print('Authenticating as Super Admin...');
    await client.auth.signInWithPassword(
      email: 'mausamban9@gmail.com',
      password: '123456',
    );

    print('Querying active profiles and cafes...');
    final profiles = await client.from('profiles').select('*');
    final cafes = await client.from('cafes').select('*');
    
    print('Found ${profiles.length} profiles:');
    for (var p in profiles) {
      print('Profile ID: ${p['id']} | Full Name: ${p['full_name']} | Role: ${p['role']} | Cafe ID: ${p['cafe_id']}');
    }

    print('Found ${cafes.length} cafes:');
    for (var c in cafes) {
      print('Cafe ID: ${c['id']} | Name: ${c['name']}');
    }

    print('All done!');
  });
}
