import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cafe/core/network/supabase_config.dart';

void main() {
  test('test signin', () async {
    final client = SupabaseClient(
      SupabaseConfig.supabaseUrl,
      SupabaseConfig.supabaseAnonKey,
      authOptions: const AuthClientOptions(
        authFlowType: AuthFlowType.implicit,
      ),
    );

    try {
      final res = await client.auth.signInWithPassword(
        email: 'developermausam9@gmail.com',
        password: '123456',
      );
      print("SUCCESSFULLY SIGNED IN PROGRAMMATICALLY! Session token: ${res.session?.accessToken}");
      expect(res.session, isNotNull);
    } catch (e, s) {
      print("SIGN IN FAILED: $e");
      print(s);
      fail("Sign in failed");
    }
  });
}
