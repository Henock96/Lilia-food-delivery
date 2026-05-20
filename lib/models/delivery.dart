import 'order.dart';

enum DeliveryStatus { en_attente, assigner, en_transit, livrer, echec }

extension DeliveryStatusX on DeliveryStatus {
  String get label => switch (this) {
    DeliveryStatus.en_attente => 'En attente',
    DeliveryStatus.assigner => 'Assignée',
    DeliveryStatus.en_transit => 'En transit',
    DeliveryStatus.livrer => 'Livrée',
    DeliveryStatus.echec => 'Échec',
  };

  static DeliveryStatus fromString(String s) => switch (s.toUpperCase()) {
    'ASSIGNER' => DeliveryStatus.assigner,
    'EN_TRANSIT' => DeliveryStatus.en_transit,
    'LIVRER' => DeliveryStatus.livrer,
    'ECHEC' => DeliveryStatus.echec,
    _ => DeliveryStatus.en_attente,
  };

  String toApiString() => switch (this) {
    DeliveryStatus.en_attente => 'EN_ATTENTE',
    DeliveryStatus.assigner => 'ASSIGNER',
    DeliveryStatus.en_transit => 'EN_TRANSIT',
    DeliveryStatus.livrer => 'LIVRER',
    DeliveryStatus.echec => 'ECHEC',
  };
}

class Delivery {
  final String id;
  final String orderId;
  final DeliveryStatus status;
  final DeliveryOrder? order;
  final DateTime createdAt;
  final DateTime? estimatedArrival;
  final DateTime? pickedUpAt;
  final DateTime? deliveredAt;
  final double? lastLatitude;
  final double? lastLongitude;

  const Delivery({
    required this.id,
    required this.orderId,
    required this.status,
    this.order,
    required this.createdAt,
    this.estimatedArrival,
    this.pickedUpAt,
    this.deliveredAt,
    this.lastLatitude,
    this.lastLongitude,
  });

  factory Delivery.fromJson(Map<String, dynamic> json) {
    final orderJson = json['order'];
    return Delivery(
      id: _stringValue(json['id']),
      orderId: _stringValue(json['orderId']),
      status: DeliveryStatusX.fromString(_stringValue(json['status'])),
      order: orderJson is Map<String, dynamic>
          ? DeliveryOrder.fromJson(orderJson)
          : null,
      createdAt:
          _dateValue(json['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      estimatedArrival: _dateValue(json['estimatedArrival']),
      pickedUpAt: _dateValue(json['pickedUpAt']),
      deliveredAt: _dateValue(json['deliveredAt']),
      lastLatitude: _doubleValue(json['lastLatitude']),
      lastLongitude: _doubleValue(json['lastLongitude']),
    );
  }
}

String _stringValue(Object? value, [String fallback = '']) =>
    value is String ? value : fallback;

double? _doubleValue(Object? value) => value is num ? value.toDouble() : null;

DateTime? _dateValue(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value);
}
