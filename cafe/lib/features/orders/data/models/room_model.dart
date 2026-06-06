import 'package:equatable/equatable.dart';

class RoomModel extends Equatable {
  final String id;
  final String cafeId;
  final String roomNumber;
  final String type; // standard, deluxe, suite, family
  final String status; // available, occupied, dirty, maintenance
  final double pricePerNight;
  final int floorNumber;
  final int maxOccupancy;
  final DateTime? createdAt;

  const RoomModel({
    required this.id,
    required this.cafeId,
    required this.roomNumber,
    required this.type,
    this.status = 'available',
    required this.pricePerNight,
    this.floorNumber = 1,
    this.maxOccupancy = 2,
    this.createdAt,
  });

  factory RoomModel.fromJson(Map<String, dynamic> json) {
    return RoomModel(
      id: json['id'] as String,
      cafeId: json['cafe_id'] as String,
      roomNumber: json['room_number'] as String,
      type: json['type'] as String? ?? 'standard',
      status: json['status'] as String? ?? 'available',
      pricePerNight: (json['price_per_night'] as num?)?.toDouble() ?? 0.0,
      floorNumber: json['floor_number'] as int? ?? 1,
      maxOccupancy: json['max_occupancy'] as int? ?? 2,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'] as String).toLocal() : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'cafe_id': cafeId,
      'room_number': roomNumber,
      'type': type,
      'status': status,
      'price_per_night': pricePerNight,
      'floor_number': floorNumber,
      'max_occupancy': maxOccupancy,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  RoomModel copyWith({
    String? roomNumber,
    String? type,
    String? status,
    double? pricePerNight,
    int? floorNumber,
    int? maxOccupancy,
  }) {
    return RoomModel(
      id: this.id,
      cafeId: this.cafeId,
      roomNumber: roomNumber ?? this.roomNumber,
      type: type ?? this.type,
      status: status ?? this.status,
      pricePerNight: pricePerNight ?? this.pricePerNight,
      floorNumber: floorNumber ?? this.floorNumber,
      maxOccupancy: maxOccupancy ?? this.maxOccupancy,
      createdAt: this.createdAt,
    );
  }

  @override
  List<Object?> get props => [id, cafeId, roomNumber, type, status, pricePerNight, floorNumber, maxOccupancy, createdAt];
}
