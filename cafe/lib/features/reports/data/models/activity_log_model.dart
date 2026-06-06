import 'package:equatable/equatable.dart';

class ActivityLogModel extends Equatable {
  final String id;
  final String cafeId;
  final String? profileId;
  final String action;
  final String? description;
  final DateTime? createdAt;

  const ActivityLogModel({
    required this.id,
    required this.cafeId,
    this.profileId,
    required this.action,
    this.description,
    this.createdAt,
  });

  factory ActivityLogModel.fromJson(Map<String, dynamic> json) {
    return ActivityLogModel(
      id: json['id'] as String,
      cafeId: json['cafe_id'] as String,
      profileId: json['profile_id'] as String?,
      action: json['action'] as String,
      description: json['description'] as String?,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'cafe_id': cafeId,
      'profile_id': profileId,
      'action': action,
      'description': description,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [
        id,
        cafeId,
        profileId,
        action,
        description,
        createdAt,
      ];
}
