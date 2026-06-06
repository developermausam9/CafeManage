import 'package:equatable/equatable.dart';
import '../../../cafes/data/models/cafe_model.dart';
import '../../../auth/data/models/profile_model.dart';
import 'subscription_model.dart';

class CafeWithSubscriptionModel extends Equatable {
  final CafeModel cafe;
  final ProfileModel? owner;
  final SubscriptionModel? subscription;

  const CafeWithSubscriptionModel({
    required this.cafe,
    this.owner,
    this.subscription,
  });

  factory CafeWithSubscriptionModel.fromJson(Map<String, dynamic> json) {
    // The JSON comes from a join query or custom structure
    return CafeWithSubscriptionModel(
      cafe: CafeModel.fromJson(json), // Base keys should match
      owner: json['owner'] != null ? ProfileModel.fromJson(json['owner']) : null,
      subscription: json['subscription'] != null ? SubscriptionModel.fromJson(json['subscription']) : null,
    );
  }

  @override
  List<Object?> get props => [cafe, owner, subscription];
}
