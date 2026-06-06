import 'package:equatable/equatable.dart';

class CategoryModel extends Equatable {
  final String id;
  final String cafeId;
  final String name;
  final DateTime? createdAt;

  const CategoryModel({
    required this.id,
    required this.cafeId,
    required this.name,
    this.createdAt,
  });

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    return CategoryModel(
      id: json['id'] as String,
      cafeId: json['cafe_id'] as String,
      name: json['name'] as String,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'cafe_id': cafeId,
      'name': name,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [id, cafeId, name, createdAt];
}
