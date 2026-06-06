import 'package:equatable/equatable.dart';

class InventoryLogModel extends Equatable {
  final String id;
  final String cafeId;
  final String productId;
  final String? profileId;
  final String action; // in, out, adjustment
  final int quantity;
  final String? supplierName;
  final String? notes;
  final DateTime? createdAt;

  const InventoryLogModel({
    required this.id,
    required this.cafeId,
    required this.productId,
    this.profileId,
    required this.action,
    required this.quantity,
    this.supplierName,
    this.notes,
    this.createdAt,
  });

  factory InventoryLogModel.fromJson(Map<String, dynamic> json) {
    return InventoryLogModel(
      id: json['id'] as String,
      cafeId: json['cafe_id'] as String,
      productId: json['product_id'] as String,
      profileId: json['profile_id'] as String?,
      action: json['action'] as String,
      quantity: json['quantity'] as int,
      supplierName: json['supplier_name'] as String?,
      notes: json['notes'] as String?,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'cafe_id': cafeId,
      'product_id': productId,
      'profile_id': profileId,
      'action': action,
      'quantity': quantity,
      'supplier_name': supplierName,
      'notes': notes,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [
        id,
        cafeId,
        productId,
        profileId,
        action,
        quantity,
        supplierName,
        notes,
        createdAt,
      ];
}
