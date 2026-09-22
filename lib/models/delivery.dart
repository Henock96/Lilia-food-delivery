import 'dart:developer' as developer;

import 'order.dart';

/// Cycle de vie d'une course, aligné sur l'enum backend.
///
/// `accepter` sépare « j'ai pris la mission et je vais chercher le repas » de
/// `en_transit` « j'ai le repas et je roule vers le client ». Sans cette
/// distinction, accepter une mission faisait croire au client que sa commande
/// était déjà en route.
enum DeliveryStatus { en_attente, assigner, accepter, en_transit, livrer, echec }

extension DeliveryStatusX on DeliveryStatus {
  String get label => switch (this) {
    DeliveryStatus.en_attente => 'En attente',
    DeliveryStatus.assigner => 'Assignée',
    DeliveryStatus.accepter => 'À récupérer',
    DeliveryStatus.en_transit => 'En livraison',
    DeliveryStatus.livrer => 'Livrée',
    DeliveryStatus.echec => 'Échec',
  };

  /// Repli appliqué à une valeur que cette version ne connaît pas.
  ///
  /// Exposé pour que le comportement de production — assertions désactivées —
  /// reste vérifiable en test.
  static const DeliveryStatus fallbackForUnknown = DeliveryStatus.en_attente;

  /// Parse un `DeliveryStatus` émis par le backend.
  ///
  /// ⚠️ Le repli était **silencieux**, et c'est ce silence qui a coûté : quand
  /// le backend a introduit `ACCEPTER` le 29/08/2026, toute course acceptée
  /// s'est affichée « En attente » chez le livreur pendant plusieurs jours,
  /// sans qu'une seule ligne ne le signale — la carte de mission disparaissait
  /// entre l'acceptation et l'arrivée au restaurant.
  ///
  /// `lilia-food-admin` a corrigé le même défaut par un `assert` ; les deux
  /// applications sont désormais alignées. `assert` n'existe qu'en **debug** :
  /// en production le repli s'applique toujours et l'écran reste utilisable.
  /// Bruyant pour celui qui peut corriger, silencieux pour celui qui livre.
  ///
  /// Une valeur **absente** n'est pas une dérive de contrat : plusieurs
  /// réponses ne portent pas de statut (`Delivery.fromJson` sur un payload
  /// minimal). Seule une valeur non vide et non reconnue est signalée.
  static DeliveryStatus fromString(String s) {
    switch (s.toUpperCase()) {
      case 'EN_ATTENTE':
        return DeliveryStatus.en_attente;
      case 'ASSIGNER':
        return DeliveryStatus.assigner;
      case 'ACCEPTER':
        return DeliveryStatus.accepter;
      case 'EN_TRANSIT':
        return DeliveryStatus.en_transit;
      case 'LIVRER':
        return DeliveryStatus.livrer;
      case 'ECHEC':
        return DeliveryStatus.echec;
      default:
        assert(
          s.isEmpty,
          'DeliveryStatus inconnu reçu du backend : "$s" — '
          "l'enum de l'app livreur est en retard sur Prisma.",
        );
        if (s.isNotEmpty) {
          developer.log(
            'DeliveryStatus inconnu : $s',
            name: 'lilia.delivery.status',
          );
        }
        return fallbackForUnknown;
    }
  }

  String toApiString() => switch (this) {
    DeliveryStatus.en_attente => 'EN_ATTENTE',
    DeliveryStatus.assigner => 'ASSIGNER',
    DeliveryStatus.accepter => 'ACCEPTER',
    DeliveryStatus.en_transit => 'EN_TRANSIT',
    DeliveryStatus.livrer => 'LIVRER',
    DeliveryStatus.echec => 'ECHEC',
  };

  /// La course est en cours : elle occupe le livreur et doit rester visible
  /// dans ses missions actives.
  bool get isActive =>
      this == DeliveryStatus.assigner ||
      this == DeliveryStatus.accepter ||
      this == DeliveryStatus.en_transit;
}

class Delivery {
  final String id;
  final String orderId;
  final DeliveryStatus status;
  final DeliveryOrder? order;
  final DateTime createdAt;
  final DateTime? estimatedArrival;
  /// Quand le livreur a accepté la mission (il part au restaurant).
  final DateTime? acceptedAt;
  /// Quand le livreur a réellement récupéré le repas.
  final DateTime? pickedUpAt;
  final DateTime? deliveredAt;
  final double? lastLatitude;
  final double? lastLongitude;

  // ─── Ce que CETTE course rapporte au livreur ──────────────────────────────

  /// Rémunération due pour cette course, en XAF. Figée à l'acceptation : un
  /// changement de taux ne modifie pas une course déjà acceptée.
  ///
  /// ⚠️ `null` = **inconnu**, et l'écran doit l'afficher comme tel. Les courses
  /// antérieures au 18/09/2026 n'ont aucune économie — aucun backfill n'a été
  /// fait, parce qu'inventer des montants jamais versés serait pire que
  /// l'absence. Afficher « 0 XAF » dirait au livreur qu'il n'a rien gagné.
  final int? driverPayXaf;

  /// Modèle appliqué (`SALARY`, `PER_DELIVERY`, `SALARY_PLUS_PER_DELIVERY`).
  /// Rend un montant de 0 lisible : au salaire, zéro par course est la bonne
  /// réponse, et l'écran doit l'expliquer au lieu d'afficher un zéro sec.
  final String? driverCompensationModel;

  /// Part du livreur, en pourcentage, telle qu'appliquée à cette course.
  final double? driverSharePercent;

  const Delivery({
    required this.id,
    required this.orderId,
    required this.status,
    this.order,
    required this.createdAt,
    this.estimatedArrival,
    this.acceptedAt,
    this.pickedUpAt,
    this.deliveredAt,
    this.lastLatitude,
    this.lastLongitude,
    this.driverPayXaf,
    this.driverCompensationModel,
    this.driverSharePercent,
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
      acceptedAt: _dateValue(json['acceptedAt']),
      pickedUpAt: _dateValue(json['pickedUpAt']),
      deliveredAt: _dateValue(json['deliveredAt']),
      lastLatitude: _doubleValue(json['lastLatitude']),
      lastLongitude: _doubleValue(json['lastLongitude']),
      // `driverEconomicsFrozenAt` est le discriminant, pas le montant : une
      // course gelée à 0 (livreur au salaire) et une course sans économie
      // rendraient toutes deux `0` si on lisait `driverPayXaf` seul. Ce sont
      // deux situations très différentes pour celui qui est payé.
      driverPayXaf: json['driverEconomicsFrozenAt'] != null
          ? _intValue(json['driverPayXaf'])
          : null,
      driverCompensationModel: _nullableString(
        json['driverCompensationModel'],
      ),
      driverSharePercent: _doubleValue(json['driverSharePercent']),
    );
  }
}

String _stringValue(Object? value, [String fallback = '']) =>
    value is String ? value : fallback;

double? _doubleValue(Object? value) => value is num ? value.toDouble() : null;

int? _intValue(Object? value) => value is num ? value.toInt() : null;

String? _nullableString(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

DateTime? _dateValue(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value);
}
