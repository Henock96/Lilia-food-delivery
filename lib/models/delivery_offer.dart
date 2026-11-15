import 'vendor_type.dart';

/// Une course proposée à tous les livreurs disponibles — dispatch FCFS
/// (« premier arrivé, premier servi », 10/11/2026).
///
/// Miroir de la projection d'offre du backend (`delivery-offer-projection.ts`)
/// : **avant** d'avoir accepté, le livreur ne voit ni le client, ni l'adresse
/// exacte, ni le moindre montant. Les champs absents ici le sont aussi dans
/// la réponse ; le détail complet n'arrive qu'après le claim.
class DeliveryOffer {
  const DeliveryOffer({
    required this.deliveryId,
    required this.orderRef,
    required this.restaurantName,
    required this.vendorType,
    required this.restaurantQuartier,
    required this.deliveryQuartier,
    required this.itemCount,
    required this.isPreorder,
    required this.scheduledFor,
    required this.readySince,
    required this.round,
  });

  final String deliveryId;

  /// Référence courte « #ABC123 », pas l'identifiant de commande.
  final String orderRef;
  final String restaurantName;
  final VendorType vendorType;
  final String? restaurantQuartier;
  final String? deliveryQuartier;
  final int itemCount;
  final bool isPreorder;
  final DateTime? scheduledFor;

  /// Depuis quand la commande attend un livreur.
  final DateTime? readySince;

  /// Numéro de la diffusion en cours (1 à 5).
  final int round;

  factory DeliveryOffer.fromJson(Map<String, dynamic> json) {
    final restaurant = json['restaurant'];
    final r = restaurant is Map<String, dynamic>
        ? restaurant
        : const <String, dynamic>{};
    return DeliveryOffer(
      deliveryId: json['deliveryId'] as String,
      orderRef: json['orderRef'] as String? ?? '',
      restaurantName: r['nom'] as String? ?? 'Point de retrait',
      vendorType: VendorType.fromString(r['vendorType'] as String?),
      restaurantQuartier: r['quartier'] as String?,
      deliveryQuartier: json['deliveryQuartier'] as String?,
      itemCount: (json['itemCount'] as num?)?.toInt() ?? 0,
      isPreorder: json['isPreorder'] == true,
      scheduledFor: _date(json['scheduledFor']),
      readySince: _date(json['readySince']),
      round: (json['round'] as num?)?.toInt() ?? 0,
    );
  }

  static DateTime? _date(Object? v) =>
      v is String ? DateTime.tryParse(v)?.toLocal() : null;
}

/// Pourquoi le serveur ne propose rien à ce livreur (`meta.driver.reason`).
/// Le serveur décide ; l'app affiche.
enum OfferIneligibility {
  dispatchDisabled,
  accountBlocked,
  profileInactive,
  appNotCapable,
  offline,
  busy;

  static OfferIneligibility? fromString(String? s) => switch (s) {
    'DISPATCH_DISABLED' => dispatchDisabled,
    'ACCOUNT_BLOCKED' => accountBlocked,
    'PROFILE_INACTIVE' => profileInactive,
    'APP_NOT_CAPABLE' => appNotCapable,
    'OFFLINE' => offline,
    'BUSY' => busy,
    _ => null,
  };

  String get message => switch (this) {
    dispatchDisabled =>
      'Les commandes vous sont attribuées par l’équipe Lilia pour le moment.',
    accountBlocked =>
      'Votre compte ne permet plus de recevoir de course. Contactez Lilia Food.',
    profileInactive =>
      'Votre profil livreur n’est pas en service. Contactez l’administration.',
    appNotCapable =>
      'Mettez l’application à jour pour recevoir les commandes disponibles.',
    offline => 'Passez « Disponible » pour voir les commandes à prendre.',
    busy => 'Terminez votre mission en cours pour en prendre une autre.',
  };
}

/// La liste et ce que le serveur dit du livreur qui la demande.
class AvailableDeliveries {
  const AvailableDeliveries({
    required this.offers,
    required this.dispatchEnabled,
    required this.ineligibility,
    this.ineligibilityRaw,
  });

  final List<DeliveryOffer> offers;
  final bool dispatchEnabled;

  /// `null` = éligible : la liste est à prendre au sérieux, même vide.
  final OfferIneligibility? ineligibility;

  /// Raison inconnue de cette version de l'app, affichée brute.
  final String? ineligibilityRaw;

  bool get eligible => ineligibility == null && ineligibilityRaw == null;

  factory AvailableDeliveries.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    final meta = json['meta'];
    final m = meta is Map<String, dynamic> ? meta : const <String, dynamic>{};
    final driver = m['driver'];
    final d = driver is Map<String, dynamic>
        ? driver
        : const <String, dynamic>{};
    final reason = d['reason'] as String?;
    final known = OfferIneligibility.fromString(reason);
    return AvailableDeliveries(
      offers: data is List
          ? data
                .whereType<Map<String, dynamic>>()
                .map(DeliveryOffer.fromJson)
                .toList()
          : const [],
      dispatchEnabled: m['dispatchEnabled'] == true,
      ineligibility: known,
      ineligibilityRaw: reason != null && known == null ? reason : null,
    );
  }

  AvailableDeliveries without(String deliveryId) => AvailableDeliveries(
    offers: offers.where((o) => o.deliveryId != deliveryId).toList(),
    dispatchEnabled: dispatchEnabled,
    ineligibility: ineligibility,
    ineligibilityRaw: ineligibilityRaw,
  );
}
