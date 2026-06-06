import 'package:equatable/equatable.dart';

class TableModel extends Equatable {
  final String id;
  final String cafeId;
  final String name;
  final int capacity;
  final bool isActive;
  final String status; // 'free', 'occupied', 'preparing', 'ready', 'billing_pending', 'completed'
  final DateTime? createdAt;

  const TableModel({
    required this.id,
    required this.cafeId,
    required this.name,
    this.capacity = 4,
    this.isActive = true,
    this.status = 'free',
    this.createdAt,
  });

  factory TableModel.fromJson(Map<String, dynamic> json) {
    return TableModel(
      id: json['id'] as String,
      cafeId: json['cafe_id'] as String,
      name: json['name'] as String,
      capacity: json['capacity'] as int? ?? 4,
      isActive: json['is_active'] as bool? ?? true,
      status: json['status'] as String? ?? 'free',
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'cafe_id': cafeId,
      'name': name,
      'capacity': capacity,
      'is_active': isActive,
      'status': status,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  TableModel copyWith({
    String? name,
    int? capacity,
    bool? isActive,
    String? status,
  }) {
    return TableModel(
      id: this.id,
      cafeId: this.cafeId,
      name: name ?? this.name,
      capacity: capacity ?? this.capacity,
      isActive: isActive ?? this.isActive,
      status: status ?? this.status,
      createdAt: this.createdAt,
    );
  }

  @override
  List<Object?> get props => [id, cafeId, name, capacity, isActive, status, createdAt];
}
