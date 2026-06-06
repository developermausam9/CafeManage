import 'package:equatable/equatable.dart';

class DuePaymentModel extends Equatable {
  final String id;
  final String cafeId;
  final String customerId;
  final String? cashierId;
  final double amount;
  final String paymentMethod;
  final String? notes;
  final DateTime? createdAt;

  const DuePaymentModel({
    required this.id,
    required this.cafeId,
    required this.customerId,
    this.cashierId,
    required this.amount,
    required this.paymentMethod,
    this.notes,
    this.createdAt,
  });

  factory DuePaymentModel.fromJson(Map<String, dynamic> json) {
    return DuePaymentModel(
      id: json['id'] as String,
      cafeId: json['cafe_id'] as String,
      customerId: json['customer_id'] as String,
      cashierId: json['cashier_id'] as String?,
      amount: (json['amount'] as num).toDouble(),
      paymentMethod: json['payment_method'] as String,
      notes: json['notes'] as String?,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'cafe_id': cafeId,
      'customer_id': customerId,
      'cashier_id': cashierId,
      'amount': amount,
      'payment_method': paymentMethod,
      'notes': notes,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [
        id,
        cafeId,
        customerId,
        cashierId,
        amount,
        paymentMethod,
        notes,
        createdAt,
      ];
}
