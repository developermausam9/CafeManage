import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/error/exceptions.dart';
import '../models/expense_model.dart';

abstract class ExpenseRemoteDataSource {
  Future<List<ExpenseModel>> getExpenses(String cafeId);
  Future<ExpenseModel> addExpense(ExpenseModel expense);
}

class ExpenseRemoteDataSourceImpl implements ExpenseRemoteDataSource {
  final SupabaseClient client;

  ExpenseRemoteDataSourceImpl(this.client);

  @override
  Future<List<ExpenseModel>> getExpenses(String cafeId) async {
    try {
      final response = await client
          .from('expenses')
          .select()
          .eq('cafe_id', cafeId)
          .order('date', ascending: false);
          
      return (response as List).map((json) => ExpenseModel.fromJson(json)).toList();
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  @override
  Future<ExpenseModel> addExpense(ExpenseModel expense) async {
    try {
      final response = await client
          .from('expenses')
          .insert(expense.toJson()..remove('id'))
          .select()
          .single();
          
      return ExpenseModel.fromJson(response);
    } catch (e) {
      throw ServerException(e.toString());
    }
  }
}
