import 'package:equatable/equatable.dart';

class TableModel extends Equatable {
  final String id;
  final String cafeId;
  final String name;
  final bool isOccupied;
  final DateTime? createdAt;

  const TableModel({
    required this.id,
    required this.cafeId,
    required this.name,
    this.isOccupied = false,
    this.createdAt,
  });

  factory TableModel.fromJson(Map<String, dynamic> json) {
    return TableModel(
      id: json['id'] as String,
      cafeId: json['cafe_id'] as String,
      name: json['name'] as String,
      isOccupied: json['is_occupied'] as bool? ?? false,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'cafe_id': cafeId,
      'name': name,
      'is_occupied': isOccupied,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [id, cafeId, name, isOccupied, createdAt];
}
