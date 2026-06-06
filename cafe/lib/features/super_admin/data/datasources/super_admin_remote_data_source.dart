import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/network/supabase_config.dart';
import '../models/subscription_model.dart';
import '../models/billing_record_model.dart';
import '../../../cafes/data/models/cafe_model.dart';

class SuperAdminRemoteDataSource {
  final SupabaseClient client;

  SuperAdminRemoteDataSource(this.client);

  Future<void> createCafe({
    required String cafeName,
    required String ownerName,
    required String email,
    required String phone,
    required String password,
    required String address,
    required String panVat,
    required String planType,
    required double monthlyFee,
    required DateTime subscriptionStart,
    required DateTime subscriptionEnd,
    required String status,
  }) async {
    try {
      await client.rpc('create_cafe_with_owner_v2', params: {
        'p_cafe_name': cafeName,
        'p_address': address,
        'p_pan_vat': panVat,
        'p_phone': phone,
        'p_owner_name': ownerName,
        'p_email': email,
        'p_password': password,
        'p_plan_type': planType,
        'p_monthly_fee': monthlyFee,
        'p_subscription_start': subscriptionStart.toIso8601String(),
        'p_subscription_end': subscriptionEnd.toIso8601String(),
        'p_status': status,
      });
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  Future<void> updateCafe({
    required String cafeId,
    required String ownerId,
    required String subscriptionId,
    required String cafeName,
    required String ownerName,
    required String phone,
    required String address,
    required String panVat,
    required String planType,
    required double monthlyFee,
    required DateTime subscriptionEnd,
    required String status,
  }) async {
    try {
      // Update Cafe
      await client.from('cafes').update({
        'name': cafeName,
        'address': address,
        'pan_vat_number': panVat,
        'status': status,
      }).eq('id', cafeId);

      // Update Profile
      await client.from('profiles').update({
        'full_name': ownerName,
        'phone': phone,
      }).eq('id', ownerId);

      // Update Subscription
      await client.from('subscriptions').update({
        'plan_type': planType,
        'monthly_fee': monthlyFee,
        'subscription_end': subscriptionEnd.toIso8601String(),
        'is_active': status == 'active',
      }).eq('cafe_id', cafeId);
      
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  Future<List<Map<String, dynamic>>> getAllCafes() async {
    // Fetch all cafes
    final cafes = await client.from('cafes').select('*').order('created_at', ascending: false);
    
    // Fetch subscriptions for these cafes
    final subscriptions = await client.from('subscriptions').select('*');
    
    // Fetch owners (profiles with role=owner)
    final owners = await client.from('profiles').select('*').eq('role', 'owner');
    
    List<Map<String, dynamic>> result = [];
    
    for (var cafe in cafes) {
      final cafeId = cafe['id'];
      
      final subscription = subscriptions.firstWhere(
        (sub) => sub['cafe_id'] == cafeId, 
        orElse: () => <String, dynamic>{}
      );
      
      final owner = owners.firstWhere(
        (own) => own['cafe_id'] == cafeId, 
        orElse: () => <String, dynamic>{}
      );
      
      result.add({
        ...cafe,
        'subscription': subscription.isEmpty ? null : subscription,
        'owner': owner.isEmpty ? null : owner,
      });
    }
    
    return result;
  }

  Future<void> suspendCafe(String cafeId) async {
    await client.from('cafes').update({'status': 'suspended'}).eq('id', cafeId);
  }

  Future<void> reactivateCafe(String cafeId) async {
    await client.from('cafes').update({'status': 'active'}).eq('id', cafeId);
  }

  Future<void> updateSubscription(SubscriptionModel subscription) async {
    await client.from('subscriptions').upsert(subscription.toJson());
  }

  Future<void> addBillingRecord(BillingRecordModel record) async {
    await client.from('billing_records').insert(record.toJson());
  }

  Future<List<BillingRecordModel>> getBillingRecords(String cafeId) async {
    final res = await client.from('billing_records').select().eq('cafe_id', cafeId).order('payment_date', ascending: false);
    return res.map((json) => BillingRecordModel.fromJson(json)).toList();
  }

  Future<Map<String, dynamic>> getSuperAdminStats() async {
    final cafes = await client.from('cafes').select('id, status');
    final subscriptions = await client.from('subscriptions').select('monthly_fee, is_active');
    
    int totalCafes = cafes.length;
    int activeCafes = cafes.where((c) => c['status'] == 'active').length;
    int suspendedCafes = cafes.where((c) => c['status'] == 'suspended').length;
    
    double mrr = subscriptions
        .where((s) => s['is_active'] == true)
        .fold(0.0, (sum, s) => sum + (s['monthly_fee'] as num).toDouble());
        
    return {
      'total_cafes': totalCafes,
      'active_cafes': activeCafes,
      'suspended_cafes': suspendedCafes,
      'mrr': mrr,
    };
  }
}
