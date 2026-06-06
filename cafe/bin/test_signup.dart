import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  final tempClient = SupabaseClient(
    'https://puffcvvmdvcidgniezvj.supabase.co',
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InB1ZmZjdnZtZHZjaWRnbmllenZqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk1MjI1NTcsImV4cCI6MjA5NTA5ODU1N30.R7S_uvtmrqsonHAZ2Z5AIaP7gUZJVcOegCxoELI-N3I',
    authOptions: const AuthClientOptions(
      authFlowType: AuthFlowType.implicit,
    ),
  );

  try {
    print('Testing signUp...');
    final res = await tempClient.auth.signUp(
      email: 'developermausam9@gmail.com',
      password: 'Mausam@123',
    );
    print('Success! User ID: ${res.user?.id}');
    print('User confirmed: ${res.user?.emailConfirmedAt}');
  } catch (e, stack) {
    print('Caught error: $e');
    print(stack);
  } finally {
    tempClient.dispose();
  }
}
