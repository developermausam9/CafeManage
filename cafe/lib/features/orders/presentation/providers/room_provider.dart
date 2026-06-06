import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../../core/network/supabase_config.dart';
import '../../data/models/room_model.dart';

class RoomProvider extends ChangeNotifier {
  final SupabaseClient _client = SupabaseConfig.client;
  List<RoomModel> _rooms = [];
  List<RoomModel> get rooms => _rooms;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _cafeId;
  StreamSubscription? _subscription;

  void init(String cafeId) {
    _cafeId = cafeId;
    fetchRooms();
    _subscribeToRooms(cafeId);
  }

  Future<void> fetchRooms() async {
    if (_cafeId == null) return;
    _isLoading = true;
    notifyListeners();
    final box = Hive.box('cache');
    final cacheKey = 'rooms_$_cafeId';
    try {
      final response = await _client
          .from('rooms')
          .select()
          .eq('cafe_id', _cafeId!)
          .order('room_number', ascending: true);
      _rooms = (response as List).map((json) => RoomModel.fromJson(json)).toList();
      await box.put(cacheKey, jsonEncode(response));
    } catch (e) {
      debugPrint("Error fetching rooms, trying cache fallback: $e");
      final cached = box.get(cacheKey);
      if (cached != null) {
        try {
          final List list = jsonDecode(cached);
          _rooms = list.map((json) => RoomModel.fromJson(json)).toList();
          _rooms.sort((a, b) => a.roomNumber.compareTo(b.roomNumber));
          debugPrint("[RoomProvider] Offline — loaded rooms from cache: ${_rooms.length}");
        } catch (_) {}
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _subscribeToRooms(String cafeId) {
    _subscription?.cancel();
    _subscription = _client
        .from('rooms')
        .stream(primaryKey: ['id'])
        .eq('cafe_id', cafeId)
        .listen((data) async {
          _rooms = data.map((json) => RoomModel.fromJson(json)).toList();
          _rooms.sort((a, b) => a.roomNumber.compareTo(b.roomNumber));
          
          final box = Hive.box('cache');
          final cacheKey = 'rooms_$cafeId';
          await box.put(cacheKey, jsonEncode(data));
          
          notifyListeners();
        }, onError: (err) {
          debugPrint("Realtime rooms stream error: $err");
        });
  }

  Future<bool> createRoom({
    required String roomNumber,
    required String type,
    required double pricePerNight,
    int floorNumber = 1,
    int maxOccupancy = 2,
  }) async {
    if (_cafeId == null) return false;
    try {
      await _client.from('rooms').insert({
        'cafe_id': _cafeId,
        'room_number': roomNumber,
        'type': type,
        'status': 'available',
        'price_per_night': pricePerNight,
        'floor_number': floorNumber,
        'max_occupancy': maxOccupancy,
      });
      return true;
    } catch (e) {
      debugPrint("Error creating room: $e");
      return false;
    }
  }

  Future<bool> updateRoom(
    String id, {
    String? roomNumber,
    String? type,
    String? status,
    double? pricePerNight,
    int? floorNumber,
    int? maxOccupancy,
  }) async {
    try {
      final updates = <String, dynamic>{};
      if (roomNumber != null) updates['room_number'] = roomNumber;
      if (type != null) updates['type'] = type;
      if (status != null) updates['status'] = status;
      if (pricePerNight != null) updates['price_per_night'] = pricePerNight;
      if (floorNumber != null) updates['floor_number'] = floorNumber;
      if (maxOccupancy != null) updates['max_occupancy'] = maxOccupancy;

      await _client.from('rooms').update(updates).eq('id', id);
      return true;
    } catch (e) {
      debugPrint("Error updating room: $e");
      return false;
    }
  }

  Future<bool> deleteRoom(String id) async {
    try {
      await _client.from('rooms').delete().eq('id', id);
      return true;
    } catch (e) {
      debugPrint("Error deleting room: $e");
      return false;
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
