import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../../core/network/supabase_config.dart';
import '../../data/models/table_model.dart';

class TableProvider extends ChangeNotifier {
  final SupabaseClient _client = SupabaseConfig.client;
  List<TableModel> _tables = [];
  List<TableModel> get tables => _tables.where((t) => t.isActive).toList();
  List<TableModel> get allTables => _tables;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _cafeId;
  StreamSubscription? _subscription;

  void init(String cafeId) {
    _cafeId = cafeId;
    fetchTables();
    _subscribeToTables(cafeId);
  }

  Future<void> fetchTables() async {
    if (_cafeId == null) return;
    _isLoading = true;
    notifyListeners();
    final box = Hive.box('cache');
    final cacheKey = 'tables_$_cafeId';
    try {
      final response = await _client
          .from('tables')
          .select()
          .eq('cafe_id', _cafeId!)
          .order('name', ascending: true);
      _tables = (response as List).map((json) => TableModel.fromJson(json)).toList();
      await box.put(cacheKey, jsonEncode(response));
    } catch (e) {
      debugPrint("Error fetching tables, trying cache fallback: $e");
      final cached = box.get(cacheKey);
      if (cached != null) {
        try {
          final List list = jsonDecode(cached);
          _tables = list.map((json) => TableModel.fromJson(json)).toList();
          _tables.sort((a, b) => a.name.compareTo(b.name));
          debugPrint("[TableProvider] Offline — loaded tables from cache: ${_tables.length}");
        } catch (_) {}
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _subscribeToTables(String cafeId) {
    _subscription?.cancel();
    _subscription = _client
        .from('tables')
        .stream(primaryKey: ['id'])
        .eq('cafe_id', cafeId)
        .listen((data) async {
          _tables = data.map((json) => TableModel.fromJson(json)).toList();
          _tables.sort((a, b) => a.name.compareTo(b.name));
          
          final box = Hive.box('cache');
          final cacheKey = 'tables_$cafeId';
          await box.put(cacheKey, jsonEncode(data));
          
          notifyListeners();
        }, onError: (err) {
          debugPrint("Realtime tables stream error: $err");
        });
  }

  Future<bool> createTable(String name, int capacity) async {
    if (_cafeId == null) return false;
    try {
      await _client.from('tables').insert({
        'cafe_id': _cafeId,
        'name': name,
        'capacity': capacity,
        'status': 'free',
        'is_occupied': false,
        'is_active': true,
      });
      return true;
    } catch (e) {
      debugPrint("Error creating table: $e");
      return false;
    }
  }

  Future<bool> updateTable(String id, {String? name, int? capacity, bool? isActive, String? status}) async {
    try {
      final updates = <String, dynamic>{};
      if (name != null) updates['name'] = name;
      if (capacity != null) updates['capacity'] = capacity;
      if (isActive != null) updates['is_active'] = isActive;
      if (status != null) {
        updates['status'] = status;
        updates['is_occupied'] = status != 'free';
      }
      await _client.from('tables').update(updates).eq('id', id);
      return true;
    } catch (e) {
      debugPrint("Error updating table: $e");
      return false;
    }
  }

  Future<bool> deleteTable(String id) async {
    try {
      await _client.from('tables').delete().eq('id', id);
      return true;
    } catch (e) {
      debugPrint("Error deleting table: $e");
      return false;
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
