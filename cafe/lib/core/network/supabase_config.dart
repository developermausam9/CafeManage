import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  static const String supabaseUrl = 'https://puffcvvmdvcidgniezvj.supabase.co';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InB1ZmZjdnZtZHZjaWRnbmllenZqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk1MjI1NTcsImV4cCI6MjA5NTA5ODU1N30.R7S_uvtmrqsonHAZ2Z5AIaP7gUZJVcOegCxoELI-N3I';

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
}
