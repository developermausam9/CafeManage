import 'package:equatable/equatable.dart';

class SubscriptionModel extends Equatable {
  final String cafeId;
  final String planType;
  final double monthlyFee;
  final String paymentStatus;
  final DateTime? nextDueDate;
  final DateTime? subscriptionStart;
  final DateTime? subscriptionEnd;
  final bool isActive;

  const SubscriptionModel({
    required this.cafeId,
    required this.planType,
    required this.monthlyFee,
    required this.paymentStatus,
    this.nextDueDate,
    this.subscriptionStart,
    this.subscriptionEnd,
    required this.isActive,
  });

  factory SubscriptionModel.fromJson(Map<String, dynamic> json) {
    return SubscriptionModel(
      cafeId: json['cafe_id'] as String,
      planType: json['plan_type'] as String? ?? 'Basic',
      monthlyFee: (json['monthly_fee'] as num?)?.toDouble() ?? 500.0,
      paymentStatus: json['payment_status'] as String? ?? 'active',
      nextDueDate: json['next_due_date'] != null ? DateTime.parse(json['next_due_date']) : null,
      subscriptionStart: json['subscription_start'] != null ? DateTime.parse(json['subscription_start']) : null,
      subscriptionEnd: json['subscription_end'] != null ? DateTime.parse(json['subscription_end']) : null,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'cafe_id': cafeId,
      'plan_type': planType,
      'monthly_fee': monthlyFee,
      'payment_status': paymentStatus,
      'next_due_date': nextDueDate?.toIso8601String(),
      'subscription_start': subscriptionStart?.toIso8601String(),
      'subscription_end': subscriptionEnd?.toIso8601String(),
      'is_active': isActive,
    };
  }

  @override
  List<Object?> get props => [
    cafeId, planType, monthlyFee, paymentStatus, nextDueDate, subscriptionStart, subscriptionEnd, isActive
  ];
}
