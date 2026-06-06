import 'package:equatable/equatable.dart';

class NotificationModel extends Equatable {
  final String id;
  final String cafeId;
  final String? recipientUserId;
  final String? recipientRole;
  final String title;
  final String message;
  final String type;
  final bool isRead;
  final DateTime createdAt;
  final Map<String, dynamic> metadata;

  const NotificationModel({
    required this.id,
    required this.cafeId,
    this.recipientUserId,
    this.recipientRole,
    required this.title,
    required this.message,
    required this.type,
    this.isRead = false,
    required this.createdAt,
    this.metadata = const {},
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id'] as String,
      cafeId: json['cafe_id'] as String,
      recipientUserId: json['recipient_user_id'] as String?,
      recipientRole: json['recipient_role'] as String?,
      title: json['title'] as String,
      message: json['message'] as String,
      type: json['type'] as String,
      isRead: json['is_read'] as bool? ?? false,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at'] as String).toLocal() 
          : DateTime.now(),
      metadata: json['metadata'] as Map<String, dynamic>? ?? const {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'cafe_id': cafeId,
      'recipient_user_id': recipientUserId,
      'recipient_role': recipientRole,
      'title': title,
      'message': message,
      'type': type,
      'is_read': isRead,
      'created_at': createdAt.toUtc().toIso8601String(),
      'metadata': metadata,
    };
  }

  NotificationModel copyWith({
    String? id,
    String? cafeId,
    String? recipientUserId,
    String? recipientRole,
    String? title,
    String? message,
    String? type,
    bool? isRead,
    DateTime? createdAt,
    Map<String, dynamic>? metadata,
  }) {
    return NotificationModel(
      id: id ?? this.id,
      cafeId: cafeId ?? this.cafeId,
      recipientUserId: recipientUserId ?? this.recipientUserId,
      recipientRole: recipientRole ?? this.recipientRole,
      title: title ?? this.title,
      message: message ?? this.message,
      type: type ?? this.type,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  List<Object?> get props => [
        id,
        cafeId,
        recipientUserId,
        recipientRole,
        title,
        message,
        type,
        isRead,
        createdAt,
        metadata,
      ];
}
