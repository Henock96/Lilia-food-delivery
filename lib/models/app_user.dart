enum DriverStatus { available, on_delivery, offline }

extension DriverStatusX on DriverStatus {
  String get label => switch (this) {
    DriverStatus.available => 'Disponible',
    DriverStatus.on_delivery => 'En livraison',
    DriverStatus.offline => 'Hors ligne',
  };

  static DriverStatus fromString(String s) => switch (s.toUpperCase()) {
    'ON_DELIVERY' => DriverStatus.on_delivery,
    'OFFLINE' => DriverStatus.offline,
    _ => DriverStatus.available,
  };

  String toApiString() => switch (this) {
    DriverStatus.available => 'AVAILABLE',
    DriverStatus.on_delivery => 'ON_DELIVERY',
    DriverStatus.offline => 'OFFLINE',
  };
}

class AppUser {
  final String id;
  final String firebaseUid;
  final String nom;
  final String? phone;
  final String? imageUrl;
  final String role;
  final DriverStatus? driverStatus;

  const AppUser({
    required this.id,
    required this.firebaseUid,
    required this.nom,
    this.phone,
    this.imageUrl,
    required this.role,
    this.driverStatus,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: _stringValue(json['id']),
    firebaseUid: _stringValue(json['firebaseUid']),
    nom: _stringValue(json['nom'], 'Livreur'),
    phone: _nullableString(json['phone']),
    imageUrl: _nullableString(json['imageUrl']),
    role: _stringValue(json['role'], 'LIVREUR'),
    driverStatus: json['driverStatus'] != null
        ? DriverStatusX.fromString(_stringValue(json['driverStatus']))
        : null,
  );
}

String _stringValue(Object? value, [String fallback = '']) =>
    value is String ? value : fallback;

String? _nullableString(Object? value) => value is String ? value : null;
