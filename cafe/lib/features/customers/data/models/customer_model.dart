import 'package:equatable/equatable.dart';

class CustomerModel extends Equatable {
  final String id;
  final String cafeId;
  final String name;
  final String? phone;
  final double totalDue;
  final DateTime? createdAt;

  const CustomerModel({
    required this.id,
    required this.cafeId,
    required this.name,
    this.phone,
    this.totalDue = 0.0,
    this.createdAt,
  });

  factory CustomerModel.fromJson(Map<String, dynamic> json) {
    return CustomerModel(
      id: json['id'] as String,
      cafeId: json['cafe_id'] as String,
      name: json['name'] as String,
      phone: json['phone'] as String?,
      totalDue: (json['total_due'] as num?)?.toDouble() ?? 0.0,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'cafe_id': cafeId,
      'name': name,
      'phone': phone,
      'total_due': totalDue,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [id, cafeId, name, phone, totalDue, createdAt];
}
