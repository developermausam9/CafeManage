import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/error/exceptions.dart';
import '../models/inventory_log_model.dart';

abstract class InventoryRemoteDataSource {
  Future<List<InventoryLogModel>> getInventoryLogs(String cafeId);
  Future<InventoryLogModel> addInventoryLog(InventoryLogModel log);
}

class InventoryRemoteDataSourceImpl implements InventoryRemoteDataSource {
  final SupabaseClient client;

  InventoryRemoteDataSourceImpl(this.client);

  @override
  Future<List<InventoryLogModel>> getInventoryLogs(String cafeId) async {
    try {
      final response = await client
          .from('inventory_logs')
          .select()
          .eq('cafe_id', cafeId)
          .order('created_at', ascending: false);
          
      return (response as List).map((json) => InventoryLogModel.fromJson(json)).toList();
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  @override
  Future<InventoryLogModel> addInventoryLog(InventoryLogModel log) async {
    try {
      // Create log
      final response = await client
          .from('inventory_logs')
          .insert(log.toJson()..remove('id'))
          .select()
          .single();
          
      return InventoryLogModel.fromJson(response);
    } catch (e) {
      throw ServerException(e.toString());
    }
  }
}
