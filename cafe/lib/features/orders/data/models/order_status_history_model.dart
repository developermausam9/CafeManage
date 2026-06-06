import 'package:equatable/equatable.dart';

class OrderStatusHistoryModel extends Equatable {
  final String id;
  final String orderId;
  final String status;
  final String? changedBy;
  final String? changedByName;
  final DateTime changedAt;

  const OrderStatusHistoryModel({
    required this.id,
    required this.orderId,
    required this.status,
    this.changedBy,
    this.changedByName,
    required this.changedAt,
  });

  factory OrderStatusHistoryModel.fromJson(Map<String, dynamic> json) {
    return OrderStatusHistoryModel(
      id: json['id'] as String,
      orderId: json['order_id'] as String,
      status: json['status'] as String,
      changedBy: json['changed_by'] as String?,
      changedByName: json['profiles'] != null ? json['profiles']['full_name'] as String? : null,
      changedAt: DateTime.parse(json['changed_at'] as String).toLocal(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'order_id': orderId,
      'status': status,
      'changed_by': changedBy,
      'changed_at': changedAt.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [id, orderId, status, changedBy, changedByName, changedAt];
}
