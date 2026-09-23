// Noms calqués sur l’enum backend (`ON_DELIVERY`) ; le format réseau passe par
// `fromString` / `toApiString`, jamais par `.name`.
// ignore: constant_identifier_names
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

/// Validité du compte, décidée par un administrateur.
///
/// À ne pas confondre avec [DriverProfile.isActive] (le livreur est-il en
/// service ?) ni avec [DriverStatus] (est-il disponible maintenant ?).
/// L'écran de profil affichait « Statut compte : Actif » **écrit en dur** :
/// un livreur suspendu le voyait en vert pendant que toutes ses requêtes
/// recevaient un 403.
enum AccountStatus { active, blocked, deleted, inactive, unknown }

extension AccountStatusX on AccountStatus {
  String get label => switch (this) {
    AccountStatus.active => 'Actif',
    AccountStatus.blocked => 'Suspendu',
    AccountStatus.deleted => 'Supprimé',
    AccountStatus.inactive => 'Inactif',
    AccountStatus.unknown => 'Inconnu',
  };

  bool get isUsable => this == AccountStatus.active;

  /// Toute valeur inattendue tombe sur `unknown` plutôt que sur `active` :
  /// une app plus ancienne que le serveur doit se taire, pas rassurer à tort.
  static AccountStatus fromString(String? s) => switch (s?.toUpperCase()) {
    'ACTIVE' => AccountStatus.active,
    'BLOCKED' => AccountStatus.blocked,
    'DELETED' => AccountStatus.deleted,
    'INACTIVE' => AccountStatus.inactive,
    _ => AccountStatus.unknown,
  };
}

enum VehicleType { moto, velo, voiture, pieton }

extension VehicleTypeX on VehicleType {
  String get label => switch (this) {
    VehicleType.moto => 'Moto',
    VehicleType.velo => 'Vélo',
    VehicleType.voiture => 'Voiture',
    VehicleType.pieton => 'À pied',
  };

  static VehicleType fromString(String? s) => switch (s?.toUpperCase()) {
    'VELO' => VehicleType.velo,
    'VOITURE' => VehicleType.voiture,
    'PIETON' => VehicleType.pieton,
    _ => VehicleType.moto,
  };
}

/// Profil métier du livreur (septembre 2026).
///
/// `null` tant que le serveur n'en renvoie pas : une app à jour contre un
/// backend ancien affiche « profil non renseigné » au lieu de planter.
class DriverProfile {
  final VehicleType vehicleType;
  final String? plateNumber;
  final String? licenseNumber;
  final DateTime? licenseExpiry;
  final bool isActive;
  final DateTime? activatedAt;

  /// Quartiers d'affectation. Vide = toute la ville.
  final List<String> zones;

  const DriverProfile({
    required this.vehicleType,
    this.plateNumber,
    this.licenseNumber,
    this.licenseExpiry,
    required this.isActive,
    this.activatedAt,
    this.zones = const [],
  });

  factory DriverProfile.fromJson(Map<String, dynamic> json) => DriverProfile(
    vehicleType: VehicleTypeX.fromString(_nullableString(json['vehicleType'])),
    plateNumber: _nullableString(json['plateNumber']),
    licenseNumber: _nullableString(json['licenseNumber']),
    licenseExpiry: _nullableDate(json['licenseExpiry']),
    isActive: json['isActive'] == true,
    activatedAt: _nullableDate(json['activatedAt']),
    zones: (json['zones'] as List<dynamic>? ?? const [])
        .map((z) => _stringValue((z as Map<String, dynamic>?)?['nom']))
        .where((n) => n.isNotEmpty)
        .toList(),
  );

  /// Le permis expire-t-il dans moins de 30 jours (ou est-il déjà expiré) ?
  /// Le livreur est le mieux placé pour le renouveler — encore faut-il le lui
  /// dire avant que la course lui soit refusée.
  bool get licenseExpiringSoon {
    final exp = licenseExpiry;
    if (exp == null) return false;
    return exp.difference(DateTime.now()).inDays <= 30;
  }
}

class AppUser {
  final String id;
  final String firebaseUid;
  final String nom;
  final String? email;
  final String? phone;
  final String? imageUrl;
  final String role;
  final DriverStatus? driverStatus;
  final AccountStatus statusUser;
  final DriverProfile? driverProfile;

  const AppUser({
    required this.id,
    required this.firebaseUid,
    required this.nom,
    this.email,
    this.phone,
    this.imageUrl,
    required this.role,
    this.driverStatus,
    this.statusUser = AccountStatus.unknown,
    this.driverProfile,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: _stringValue(json['id']),
    firebaseUid: _stringValue(json['firebaseUid']),
    nom: _stringValue(json['nom'], 'Livreur'),
    email: _nullableString(json['email']),
    phone: _nullableString(json['phone']),
    imageUrl: _nullableString(json['imageUrl']),
    role: _stringValue(json['role'], 'LIVREUR'),
    driverStatus: json['driverStatus'] != null
        ? DriverStatusX.fromString(_stringValue(json['driverStatus']))
        : null,
    statusUser: AccountStatusX.fromString(_nullableString(json['statusUser'])),
    driverProfile: json['driverProfile'] is Map<String, dynamic>
        ? DriverProfile.fromJson(json['driverProfile'] as Map<String, dynamic>)
        : null,
  );

  /// Le livreur peut-il réellement recevoir une course ?
  ///
  /// Reprend la règle du serveur (`assertAssignable`), pour que l'application
  /// puisse **expliquer** pourquoi elle est muette au lieu d'afficher une
  /// liste de missions vide sans raison.
  bool get canReceiveMissions =>
      statusUser.isUsable && (driverProfile?.isActive ?? false);
}

String _stringValue(Object? value, [String fallback = '']) =>
    value is String ? value : fallback;

String? _nullableString(Object? value) => value is String ? value : null;

DateTime? _nullableDate(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;
