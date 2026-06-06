import 'package:equatable/equatable.dart';

class PurchaseInvoiceModel extends Equatable {
  final String id;
  final String cafeId;
  final String? supplierId;
  final String productId;
  final int quantity;
  final double purchasePrice;
  final double totalCost;
  final DateTime createdAt;

  const PurchaseInvoiceModel({
    required this.id,
    required this.cafeId,
    this.supplierId,
    required this.productId,
    required this.quantity,
    required this.purchasePrice,
    required this.totalCost,
    required this.createdAt,
  });

  factory PurchaseInvoiceModel.fromJson(Map<String, dynamic> json) {
    return PurchaseInvoiceModel(
      id: json['id'] as String,
      cafeId: json['cafe_id'] as String,
      supplierId: json['supplier_id'] as String?,
      productId: json['product_id'] as String,
      quantity: json['quantity'] as int,
      purchasePrice: (json['purchase_price'] as num).toDouble(),
      totalCost: (json['total_cost'] as num).toDouble(),
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'cafe_id': cafeId,
      'supplier_id': supplierId,
      'product_id': productId,
      'quantity': quantity,
      'purchase_price': purchasePrice,
      'total_cost': totalCost,
      'created_at': createdAt.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [id, cafeId, supplierId, productId, quantity, purchasePrice, totalCost, createdAt];
}
