import 'package:equatable/equatable.dart';

class ProductModel extends Equatable {
  final String id;
  final String cafeId;
  final String? categoryId;
  final String name;
  final double sellingPrice;
  final double costPrice;
  final int stockQuantity;
  final bool isAvailable;
  final String? imageUrl;
  final bool isStockTracked;
  final String? unitType; // 'pcs', 'packet', 'bottle', 'stick'
  final int unitsPerPacket; // e.g. 20 sticks per packet
  final DateTime? createdAt;

  const ProductModel({
    required this.id,
    required this.cafeId,
    this.categoryId,
    required this.name,
    required this.sellingPrice,
    this.costPrice = 0.0,
    this.stockQuantity = 0,
    this.isAvailable = true,
    this.imageUrl,
    this.isStockTracked = true,
    this.unitType = 'pcs',
    this.unitsPerPacket = 1,
    this.createdAt,
  });

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    return ProductModel(
      id: json['id'] as String,
      cafeId: json['cafe_id'] as String,
      categoryId: json['category_id'] as String?,
      name: json['name'] as String,
      sellingPrice: (json['price'] as num?)?.toDouble() ?? (json['selling_price'] as num).toDouble(),
      costPrice: (json['cost_price'] as num?)?.toDouble() ?? 0.0,
      stockQuantity: json['stock_quantity'] as int? ?? 0,
      isAvailable: json['is_available'] as bool? ?? true,
      imageUrl: json['image_url'] as String?,
      isStockTracked: json['is_stock_tracked'] as bool? ?? true,
      unitType: json['unit_type'] as String? ?? 'pcs',
      unitsPerPacket: json['units_per_packet'] as int? ?? 1,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'cafe_id': cafeId,
      'category_id': categoryId,
      'name': name,
      'price': sellingPrice,
      'cost_price': costPrice,
      'stock_quantity': stockQuantity,
      'is_available': isAvailable,
      'image_url': imageUrl,
      'is_stock_tracked': isStockTracked,
      'unit_type': unitType,
      'units_per_packet': unitsPerPacket,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [
        id,
        cafeId,
        categoryId,
        name,
        sellingPrice,
        costPrice,
        stockQuantity,
        isAvailable,
        imageUrl,
        isStockTracked,
        unitType,
        unitsPerPacket,
        createdAt,
      ];

  ProductModel copyWith({
    String? id,
    String? cafeId,
    String? categoryId,
    String? name,
    double? sellingPrice,
    double? costPrice,
    int? stockQuantity,
    bool? isAvailable,
    String? imageUrl,
    bool? isStockTracked,
    String? unitType,
    int? unitsPerPacket,
    DateTime? createdAt,
  }) {
    return ProductModel(
      id: id ?? this.id,
      cafeId: cafeId ?? this.cafeId,
      categoryId: categoryId ?? this.categoryId,
      name: name ?? this.name,
      sellingPrice: sellingPrice ?? this.sellingPrice,
      costPrice: costPrice ?? this.costPrice,
      stockQuantity: stockQuantity ?? this.stockQuantity,
      isAvailable: isAvailable ?? this.isAvailable,
      imageUrl: imageUrl ?? this.imageUrl,
      isStockTracked: isStockTracked ?? this.isStockTracked,
      unitType: unitType ?? this.unitType,
      unitsPerPacket: unitsPerPacket ?? this.unitsPerPacket,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

