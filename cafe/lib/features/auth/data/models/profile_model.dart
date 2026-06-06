import 'package:equatable/equatable.dart';

class ProfileModel extends Equatable {
  final String id;
  final String? cafeId;
  final String fullName;
  final String role;
  final String? phone;
  final bool isActive;
  final DateTime? createdAt;

  const ProfileModel({
    required this.id,
    this.cafeId,
    required this.fullName,
    required this.role,
    this.phone,
    this.isActive = true,
    this.createdAt,
  });

  factory ProfileModel.fromJson(Map<String, dynamic> json) {
    return ProfileModel(
      id: json['id'] as String,
      cafeId: json['cafe_id'] as String?,
      fullName: json['full_name'] as String,
      role: json['role'] as String,
      phone: json['phone'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'cafe_id': cafeId,
      'full_name': fullName,
      'role': role,
      'phone': phone,
      'is_active': isActive,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  bool get isSuperAdmin => role == 'super_admin';

  @override
  List<Object?> get props => [id, cafeId, fullName, role, phone, isActive, createdAt];
}
