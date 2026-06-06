import 'package:equatable/equatable.dart';

class CustomerDueModel extends Equatable {
  final String id;
  final String cafeId;
  final String name;
  final String phone;
  final double totalDue;
  final DateTime lastUpdatedAt;

  const CustomerDueModel({
    required this.id,
    required this.cafeId,
    required this.name,
    required this.phone,
    required this.totalDue,
    required this.lastUpdatedAt,
  });

  factory CustomerDueModel.fromJson(Map<String, dynamic> json) {
    return CustomerDueModel(
      id: json['id'] as String,
      cafeId: json['cafe_id'] as String,
      name: json['name'] as String,
      phone: json['phone'] as String,
      totalDue: (json['total_due'] as num).toDouble(),
      lastUpdatedAt: DateTime.parse(json['last_updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'cafe_id': cafeId,
      'name': name,
      'phone': phone,
      'total_due': totalDue,
      'last_updated_at': lastUpdatedAt.toIso8601String(),
    };
  }

  CustomerDueModel copyWith({
    String? id,
    String? cafeId,
    String? name,
    String? phone,
    double? totalDue,
    DateTime? lastUpdatedAt,
  }) {
    return CustomerDueModel(
      id: id ?? this.id,
      cafeId: cafeId ?? this.cafeId,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      totalDue: totalDue ?? this.totalDue,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
    );
  }

  @override
  List<Object?> get props => [id, cafeId, name, phone, totalDue, lastUpdatedAt];
}
