import 'package:equatable/equatable.dart';

class ExpenseModel extends Equatable {
  final String id;
  final String cafeId;
  final String category; // rent, salary, electricity, internet, gas, supplier payment, other
  final double amount;
  final String description;
  final DateTime date;
  final DateTime createdAt;

  const ExpenseModel({
    required this.id,
    required this.cafeId,
    required this.category,
    required this.amount,
    required this.description,
    required this.date,
    required this.createdAt,
  });

  factory ExpenseModel.fromJson(Map<String, dynamic> json) {
    return ExpenseModel(
      id: json['id'] as String,
      cafeId: json['cafe_id'] as String,
      category: json['category'] as String,
      amount: (json['amount'] as num).toDouble(),
      description: json['description'] as String,
      date: DateTime.parse(json['date']),
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'cafe_id': cafeId,
      'category': category,
      'amount': amount,
      'description': description,
      'date': date.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [id, cafeId, category, amount, description, date, createdAt];
}
