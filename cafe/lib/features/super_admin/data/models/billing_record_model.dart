import 'package:equatable/equatable.dart';

class BillingRecordModel extends Equatable {
  final String id;
  final String cafeId;
  final double amount;
  final DateTime paymentDate;
  final DateTime? dueDate;
  final String paymentMethod;
  final String? notes;
  final String status;

  const BillingRecordModel({
    required this.id,
    required this.cafeId,
    required this.amount,
    required this.paymentDate,
    this.dueDate,
    required this.paymentMethod,
    this.notes,
    required this.status,
  });

  factory BillingRecordModel.fromJson(Map<String, dynamic> json) {
    return BillingRecordModel(
      id: json['id'] as String,
      cafeId: json['cafe_id'] as String,
      amount: (json['amount'] as num).toDouble(),
      paymentDate: DateTime.parse(json['payment_date'] as String),
      dueDate: json['due_date'] != null ? DateTime.parse(json['due_date'] as String) : null,
      paymentMethod: json['payment_method'] as String,
      notes: json['notes'] as String?,
      status: json['status'] as String? ?? 'paid',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id.isNotEmpty) 'id': id,
      'cafe_id': cafeId,
      'amount': amount,
      'payment_date': paymentDate.toIso8601String(),
      'due_date': dueDate?.toIso8601String(),
      'payment_method': paymentMethod,
      'notes': notes,
      'status': status,
    };
  }

  @override
  List<Object?> get props => [
    id, cafeId, amount, paymentDate, dueDate, paymentMethod, notes, status
  ];
}
