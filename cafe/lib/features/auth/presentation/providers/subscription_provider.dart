import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../super_admin/data/models/subscription_model.dart';

class SubscriptionProvider extends ChangeNotifier {
  final SupabaseClient client;
  
  SubscriptionModel? _subscription;
  SubscriptionModel? get subscription => _subscription;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  SubscriptionProvider(this.client);

  Future<void> fetchSubscription(String cafeId) async {
    _isLoading = true;
    notifyListeners();

    try {
      final res = await client.from('subscriptions').select().eq('cafe_id', cafeId).maybeSingle();
      if (res != null) {
        _subscription = SubscriptionModel.fromJson(res);
        // Cache the subscription!
        final box = Hive.box('cache');
        await box.put('subscription_$cafeId', jsonEncode(_subscription!.toJson()));
      } else {
        // Fallback or default
        _subscription = SubscriptionModel(
          cafeId: cafeId,
          planType: 'Basic',
          monthlyFee: 500,
          paymentStatus: 'active',
          isActive: true,
        );
      }
    } catch (e) {
      debugPrint('Error fetching subscription: $e');
      // Load from cache fallback!
      try {
        final box = Hive.box('cache');
        final cachedData = box.get('subscription_$cafeId');
        if (cachedData != null) {
          _subscription = SubscriptionModel.fromJson(jsonDecode(cachedData));
          debugPrint('[SubscriptionProvider] Offline — restored subscription from cache: ${_subscription?.planType}');
        } else {
          // If offline and no cached subscription, default to Premium for offline testing!
          _subscription = SubscriptionModel(
            cafeId: cafeId,
            planType: 'Premium',
            monthlyFee: 1500,
            paymentStatus: 'active',
            isActive: true,
          );
          debugPrint('[SubscriptionProvider] Offline — no cached subscription found, defaulted to Premium for offline testing.');
        }
      } catch (err) {
        debugPrint('Error loading cached subscription: $err');
      }
    }

    _isLoading = false;
    notifyListeners();
  }

  bool get hasStandardOrPremium => 
      _subscription?.planType == 'Standard' || _subscription?.planType == 'Premium';
      
  bool get hasPremium => _subscription?.planType == 'Premium';

  bool get isActive => _subscription?.isActive ?? true;
}
