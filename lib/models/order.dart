import 'package:intl/intl.dart';
import 'package:lilia_food_delivery/models/vendor_type.dart';

class DeliveryRestaurant {
  final String? id;
  final String nom;
  final String? adresse;
  final String? phone;
  final VendorType vendorType;

  const DeliveryRestaurant({
    this.id,
    required this.nom,
    this.adresse,
    this.phone,
    this.vendorType = VendorType.RESTAURANT,
  });

  factory DeliveryRestaurant.fromJson(Map<String, dynamic> json) =>
      DeliveryRestaurant(
        id: _nullableString(json['id']),
        nom: _stringValue(json['nom'], 'Restaurant'),
        adresse: _nullableString(json['adresse']),
        phone: _nullableString(json['phone']),
        vendorType: VendorType.fromString(json['vendorType'] as String?),
      );
}

class OrderItem {
  final String id;
  final String productNom;
  final int quantity;
  final int unitPrice;
  final bool madeToOrder;

  const OrderItem({
    required this.id,
    required this.productNom,
    required this.quantity,
    required this.unitPrice,
    this.madeToOrder = false,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) => OrderItem(
        id: _stringValue(json['id']),
        productNom: _productName(json['product']),
        quantity: _intValue(json['quantite']),
        unitPrice: _intValue(json['prix']),
        madeToOrder: (json['product'] is Map<String, dynamic>)
            ? ((json['product'] as Map<String, dynamic>)['madeToOrder'] as bool? ?? false)
            : false,
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
  final bool isPreorder;
  final DateTime? scheduledFor;

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
    this.isPreorder = false,
    this.scheduledFor,
  });

  /// Meilleur numéro pour appeler : contactPhone > phone du profil
  String? get effectivePhone => contactPhone ?? clientPhone;

  /// "Jeudi 30 mai à 14:30" — null si pas de scheduledFor
  String? get scheduledForFormatted {
    if (scheduledFor == null) return null;
    final local = scheduledFor!.toLocal();
    final dayFormat = DateFormat('EEEE d MMMM', 'fr_FR');
    final timeFormat = DateFormat('HH:mm');
    final day = dayFormat.format(local);
    return '${day[0].toUpperCase()}${day.substring(1)} à ${timeFormat.format(local)}';
  }

  /// Vrai si pas une preorder, OU si on est à moins d'1h de scheduledFor.
  /// Sert à griser le bouton "Accepter" si on tente de récupérer trop tôt.
  bool get isReadyToPickup {
    if (!isPreorder || scheduledFor == null) return true;
    return scheduledFor!.subtract(const Duration(hours: 1))
        .isBefore(DateTime.now());
  }

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
      restaurant: json['restaurant'] != null &&
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
      isPreorder: json['isPreorder'] as bool? ?? false,
      scheduledFor: DateTime.tryParse(json['scheduledFor']?.toString() ?? ''),
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
