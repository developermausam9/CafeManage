import 'package:equatable/equatable.dart';

class SupplierModel extends Equatable {
  final String id;
  final String cafeId;
  final String name;
  final String phone;
  final String company;
  final double totalPayable;
  final DateTime createdAt;

  const SupplierModel({
    required this.id,
    required this.cafeId,
    required this.name,
    required this.phone,
    required this.company,
    this.totalPayable = 0.0,
    required this.createdAt,
  });

  factory SupplierModel.fromJson(Map<String, dynamic> json) {
    return SupplierModel(
      id: json['id'] as String,
      cafeId: json['cafe_id'] as String,
      name: json['name'] as String,
      phone: json['phone'] as String,
      company: json['company'] as String,
      totalPayable: (json['total_payable'] as num).toDouble(),
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'cafe_id': cafeId,
      'name': name,
      'phone': phone,
      'company': company,
      'total_payable': totalPayable,
      'created_at': createdAt.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [id, cafeId, name, phone, company, totalPayable, createdAt];
}
