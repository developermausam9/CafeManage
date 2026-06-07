import 'package:equatable/equatable.dart';

class OrderModel extends Equatable {
  final String id;
  final String cafeId;
  final int? billNumber;
  final String? tableId;
  final String? customerId;
  final String? waiterId;
  final String? cashierId;
  final String type; // dine_in, takeaway, delivery
  final String status; // pending, kitchen, completed, cancelled
  final double subtotal;
  final double discount;
  final double taxAmount;
  final double serviceCharge;
  final double grandTotal;
  final String? paymentMethod; // cash, qr, card, due, mixed
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? tableName;
  final String? waiterName;

  // New payment fields
  final String? paymentStatus; // unpaid, partial, paid
  final double paidAmount;
  final double remainingDue;
  final DateTime? paidAt;
  final DateTime? completedAt;
  final String? customerDueId;

  // Room fields
  final String? roomId;
  final String? roomBookingId;
  final String? roomName;
  final double? roomCharge;

  const OrderModel({

    required this.id,
    required this.cafeId,
    this.billNumber,
    this.tableId,
    this.customerId,
    this.waiterId,
    this.cashierId,
    required this.type,
    this.status = 'pending',
    this.subtotal = 0.0,
    this.discount = 0.0,
    this.taxAmount = 0.0,
    this.serviceCharge = 0.0,
    this.grandTotal = 0.0,
    this.paymentMethod,
    this.createdAt,
    this.updatedAt,
    this.tableName,
    this.waiterName,
    this.paymentStatus = 'paid',
    this.paidAmount = 0.0,
    this.remainingDue = 0.0,
    this.paidAt,
    this.completedAt,
    this.customerDueId,
    this.roomId,
    this.roomBookingId,
    this.roomName,
    this.roomCharge,
  });


  factory OrderModel.fromJson(Map<String, dynamic> json) {
    return OrderModel(
      id: json['id'] as String,
      cafeId: json['cafe_id'] as String,
      billNumber: json['bill_number'] as int?,
      tableId: json['table_id'] as String?,
      customerId: json['customer_id'] as String?,
      waiterId: json['waiter_id'] as String?,
      cashierId: json['cashier_id'] as String?,
      type: json['type'] as String,
      status: json['status'] as String? ?? 'pending',
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0.0,
      discount: (json['discount'] as num?)?.toDouble() ?? 0.0,
      taxAmount: (json['tax_amount'] as num?)?.toDouble() ?? 0.0,
      serviceCharge: (json['service_charge'] as num?)?.toDouble() ?? 0.0,
      grandTotal: (json['grand_total'] as num?)?.toDouble() ?? 0.0,
      paymentMethod: json['payment_method'] as String?,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'] as String).toLocal() : null,
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at'] as String).toLocal() : null,
      tableName: json['table'] != null ? json['table']['name'] as String? : null,
      waiterName: json['waiter'] != null ? json['waiter']['full_name'] as String? : null,
      paymentStatus: json['payment_status'] as String? ?? 'paid',
      paidAmount: (json['paid_amount'] as num?)?.toDouble() ?? 0.0,
      remainingDue: (json['remaining_due'] as num?)?.toDouble() ?? 0.0,
      paidAt: json['paid_at'] != null ? DateTime.parse(json['paid_at'] as String).toLocal() : null,
      completedAt: json['completed_at'] != null ? DateTime.parse(json['completed_at'] as String).toLocal() : null,
      customerDueId: json['customer_due_id'] as String?,
      roomId: json['room_id'] as String?,
      roomBookingId: json['room_booking_id'] as String?,
      roomName: json['room'] != null ? json['room']['room_number'] as String? : null,
      roomCharge: json['room_booking'] != null ? (json['room_booking']['room_charge'] as num?)?.toDouble() : null,
    );
  }


  OrderModel copyWith({
    String? status,
    String? paymentMethod,
    String? cashierId,
    double? discount,
    double? taxAmount,
    double? grandTotal,
    String? paymentStatus,
    double? paidAmount,
    double? remainingDue,
    DateTime? paidAt,
    DateTime? completedAt,
    String? customerDueId,
    DateTime? updatedAt,
    String? roomId,
    String? roomBookingId,
    String? roomName,
    double? roomCharge,
  }) {
    return OrderModel(
      id: this.id,
      cafeId: this.cafeId,
      billNumber: this.billNumber,
      tableId: this.tableId,
      customerId: this.customerId,
      waiterId: this.waiterId,
      cashierId: cashierId ?? this.cashierId,
      type: this.type,
      status: status ?? this.status,
      subtotal: this.subtotal,
      discount: discount ?? this.discount,
      taxAmount: taxAmount ?? this.taxAmount,
      serviceCharge: this.serviceCharge,
      grandTotal: grandTotal ?? this.grandTotal,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      createdAt: this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      tableName: this.tableName,
      waiterName: this.waiterName,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      paidAmount: paidAmount ?? this.paidAmount,
      remainingDue: remainingDue ?? this.remainingDue,
      paidAt: paidAt ?? this.paidAt,
      completedAt: completedAt ?? this.completedAt,
      customerDueId: customerDueId ?? this.customerDueId,
      roomId: roomId ?? this.roomId,
      roomBookingId: roomBookingId ?? this.roomBookingId,
      roomName: roomName ?? this.roomName,
      roomCharge: roomCharge ?? this.roomCharge,
    );
  }


  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'cafe_id': cafeId,
      'bill_number': billNumber,
      'table_id': tableId,
      'customer_id': customerId,
      'waiter_id': waiterId,
      'cashier_id': cashierId,
      'type': type,
      'status': status,
      'subtotal': subtotal,
      'discount': discount,
      'tax_amount': taxAmount,
      'service_charge': serviceCharge,
      'grand_total': grandTotal,
      'payment_method': paymentMethod,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'payment_status': paymentStatus,
      'paid_amount': paidAmount,
      'remaining_due': remainingDue,
      'paid_at': paidAt?.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'customer_due_id': customerDueId,
      'room_id': roomId,
      'room_booking_id': roomBookingId,
      'room_charge': roomCharge,
    };
  }


  @override
  List<Object?> get props => [
        id,
        cafeId,
        billNumber,
        tableId,
        customerId,
        waiterId,
        cashierId,
        type,
        status,
        subtotal,
        discount,
        taxAmount,
        serviceCharge,
        grandTotal,
        paymentMethod,
        createdAt,
        updatedAt,
        tableName,
        waiterName,
        paymentStatus,
        paidAmount,
        remainingDue,
        paidAt,
        completedAt,
        customerDueId,
        roomId,
        roomBookingId,
        roomName,
        roomCharge,
      ];
}

