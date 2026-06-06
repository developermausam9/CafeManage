import 'package:equatable/equatable.dart';

class ExpenseModel extends Equatable {
  final String id;
  final String cafeId;
  final String? profileId;
  final String category;
  final double amount;
  final String? description;
  final DateTime? date;
  final DateTime? createdAt;

  const ExpenseModel({
    required this.id,
    required this.cafeId,
    this.profileId,
    required this.category,
    required this.amount,
    this.description,
    this.date,
    this.createdAt,
  });

  factory ExpenseModel.fromJson(Map<String, dynamic> json) {
    return ExpenseModel(
      id: json['id'] as String,
      cafeId: json['cafe_id'] as String,
      profileId: json['profile_id'] as String?,
      category: json['category'] as String,
      amount: (json['amount'] as num).toDouble(),
      description: json['description'] as String?,
      date: json['date'] != null ? DateTime.parse(json['date']) : null,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'cafe_id': cafeId,
      'profile_id': profileId,
      'category': category,
      'amount': amount,
      'description': description,
      'date': date?.toIso8601String(),
      'created_at': createdAt?.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [
        id,
        cafeId,
        profileId,
        category,
        amount,
        description,
        date,
        createdAt,
      ];
}
