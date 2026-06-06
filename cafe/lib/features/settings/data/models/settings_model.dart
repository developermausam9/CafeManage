import 'package:equatable/equatable.dart';

class SettingsModel extends Equatable {
  final String cafeId;
  final double taxPercentage;
  final double serviceChargePercentage;
  final String? receiptFooterMessage;
  final String? printerMacAddress;
  final String language;
  final bool waiterBillingEnabled;
  final DateTime? updatedAt;

  const SettingsModel({
    required this.cafeId,
    this.taxPercentage = 13.0,
    this.serviceChargePercentage = 10.0,
    this.receiptFooterMessage,
    this.printerMacAddress,
    this.language = 'en',
    this.waiterBillingEnabled = false,
    this.updatedAt,
  });

  factory SettingsModel.fromJson(Map<String, dynamic> json) {
    return SettingsModel(
      cafeId: json['cafe_id'] as String,
      taxPercentage: (json['tax_percentage'] as num?)?.toDouble() ?? 13.0,
      serviceChargePercentage: (json['service_charge_percentage'] as num?)?.toDouble() ?? 10.0,
      receiptFooterMessage: json['receipt_footer_message'] as String?,
      printerMacAddress: json['printer_mac_address'] as String?,
      language: json['language'] as String? ?? 'en',
      waiterBillingEnabled: json['waiter_billing_enabled'] as bool? ?? false,
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'cafe_id': cafeId,
      'tax_percentage': taxPercentage,
      'service_charge_percentage': serviceChargePercentage,
      'receipt_footer_message': receiptFooterMessage,
      'printer_mac_address': printerMacAddress,
      'language': language,
      'waiter_billing_enabled': waiterBillingEnabled,
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [
        cafeId,
        taxPercentage,
        serviceChargePercentage,
        receiptFooterMessage,
        printerMacAddress,
        language,
        waiterBillingEnabled,
        updatedAt,
      ];
}
