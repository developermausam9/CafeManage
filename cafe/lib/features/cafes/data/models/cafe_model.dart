import 'package:equatable/equatable.dart';

class CafeModel extends Equatable {
  final String id;
  final String name;
  final String? panVatNumber;
  final String? phone;
  final String? address;
  final String? logoUrl;
  final String status;
  final String? ownerEmail;
  final DateTime? createdAt;

  const CafeModel({
    required this.id,
    required this.name,
    this.panVatNumber,
    this.phone,
    this.address,
    this.logoUrl,
    this.status = 'active',
    this.ownerEmail,
    this.createdAt,
  });

  factory CafeModel.fromJson(Map<String, dynamic> json) {
    return CafeModel(
      id: json['id'] as String,
      name: json['name'] as String,
      panVatNumber: json['pan_vat_number'] as String?,
      phone: json['phone'] as String?,
      address: json['address'] as String?,
      logoUrl: json['logo_url'] as String?,
      status: json['status'] as String? ?? 'active',
      ownerEmail: json['owner_email'] as String?,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'pan_vat_number': panVatNumber,
      'phone': phone,
      'address': address,
      'logo_url': logoUrl,
      'status': status,
      'owner_email': ownerEmail,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [id, name, panVatNumber, phone, address, logoUrl, status, ownerEmail, createdAt];
}
