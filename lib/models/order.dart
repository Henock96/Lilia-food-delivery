class DeliveryRestaurant {
  final String? id;
  final String nom;
  final String? adresse;
  final String? phone;

  const DeliveryRestaurant({
    this.id,
    required this.nom,
    this.adresse,
    this.phone,
  });

  factory DeliveryRestaurant.fromJson(Map<String, dynamic> json) =>
      DeliveryRestaurant(
        id: _nullableString(json['id']),
        nom: _stringValue(json['nom'], 'Restaurant'),
        adresse: _nullableString(json['adresse']),
        phone: _nullableString(json['phone']),
      );
}

class OrderItem {
  final String id;
  final String productNom;
  final int quantity;
  final int unitPrice;

  const OrderItem({
    required this.id,
    required this.productNom,
    required this.quantity,
    required this.unitPrice,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) => OrderItem(
    id: _stringValue(json['id']),
    productNom: _productName(json['product']),
    quantity: _intValue(json['quantite']),
    unitPrice: _intValue(json['prix']),
  );
}

class DeliveryAddress {
  final String? quartier;
  final String? details;

  const DeliveryAddress({this.quartier, this.details});

  factory DeliveryAddress.fromJson(Map<String, dynamic> json) =>
      DeliveryAddress(
        quartier: _nullableString(json['quartier']),
        details: _nullableString(json['details']),
      );

  String get formatted =>
      [quartier, details].where((s) => s != null && s.isNotEmpty).join(', ');
}

class DeliveryOrder {
  final String id;
  final int total;
  final int subTotal;
  final int deliveryFee;
  final DeliveryRestaurant? restaurant;
  final List<OrderItem> items;
  final DeliveryAddress? adresse;
  final double? clientLatitude;
  final double? clientLongitude;
  final String? clientNom;
  final String? clientPhone;
  final String? contactPhone;

  const DeliveryOrder({
    required this.id,
    required this.total,
    required this.subTotal,
    required this.deliveryFee,
    this.restaurant,
    required this.items,
    this.adresse,
    this.clientLatitude,
    this.clientLongitude,
    this.clientNom,
    this.clientPhone,
    this.contactPhone,
  });

  /// Meilleur numéro pour appeler : contactPhone (saisi au checkout) > phone du profil
  String? get effectivePhone => contactPhone ?? clientPhone;

  factory DeliveryOrder.fromJson(Map<String, dynamic> json) {
    final rawUser = json['user'];
    final user = rawUser is Map<String, dynamic> ? rawUser : null;
    final deliveryAddressStr = _nullableString(json['deliveryAddress']);
    DeliveryAddress? adresse;
    if (json['adresse'] is Map<String, dynamic>) {
      adresse = DeliveryAddress.fromJson(
        json['adresse'] as Map<String, dynamic>,
      );
    } else if (json['adresse'] is String &&
        (json['adresse'] as String).isNotEmpty) {
      adresse = DeliveryAddress(details: json['adresse'] as String);
    } else if (deliveryAddressStr != null && deliveryAddressStr.isNotEmpty) {
      adresse = DeliveryAddress(details: deliveryAddressStr);
    }
    return DeliveryOrder(
      id: _stringValue(json['id']),
      total: _intValue(json['total']),
      subTotal: _intValue(json['subTotal']),
      deliveryFee: _intValue(json['deliveryFee']),
      restaurant:
          json['restaurant'] != null &&
              json['restaurant'] is Map<String, dynamic>
          ? DeliveryRestaurant.fromJson(
              json['restaurant'] as Map<String, dynamic>,
            )
          : null,
      items: (json['items'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(OrderItem.fromJson)
          .toList(),
      adresse: adresse,
      clientLatitude: _doubleValue(json['deliveryLatitude']),
      clientLongitude: _doubleValue(json['deliveryLongitude']),
      clientNom: _nullableString(user?['nom']),
      clientPhone: _nullableString(user?['phone']),
      contactPhone: _nullableString(json['contactPhone']),
    );
  }
}

String _stringValue(Object? value, [String fallback = '']) =>
    value is String ? value : fallback;

String? _nullableString(Object? value) => value is String ? value : null;

int _intValue(Object? value) => value is num ? value.toInt() : 0;

double? _doubleValue(Object? value) => value is num ? value.toDouble() : null;

String _productName(Object? product) {
  if (product is Map<String, dynamic>) {
    return _stringValue(product['nom'], 'Produit');
  }
  return 'Produit';
}
